/**
 * Post-purchase upsell extension.
 *
 * Flow:
 *  1. ShouldRender: ask Rails for an offer (POST /api/post_purchase/offer).
 *     Store the offer + token in extension storage and render only when one
 *     is available.
 *  2. Render: show the offer. Accept signs the changeset server-side, applies
 *     it, then calls done(). Decline tracks rejection and calls done().
 *
 * Note on hooks: the classic post-purchase extension framework
 * (@shopify/post-purchase-ui-extensions-react ^0.13) does NOT support React
 * hooks. The App component must be a pure renderer with async button
 * handlers — no useState / useEffect / useMemo.
 */
import React from "react";

import {
  extend,
  render,
  BlockStack,
  Button,
  ButtonGroup,
  CalloutBanner,
  Heading,
  Image,
  Layout,
  Text,
  TextBlock,
  TextContainer,
  Tiles,
  View,
} from "@shopify/post-purchase-ui-extensions-react";

// Update this to your Rails backend URL (the same URL configured as
// `application_url` in shopify.app.toml). When running `shopify app dev`,
// Shopify CLI rewrites application_url to the active tunnel URL — paste it
// here. Production deploys should set this to the deployed app URL.
const APP_URL = "https://capabilities-proposition-went-jersey.trycloudflare.com";

const apiUrl = (path) => `${APP_URL.replace(/\/$/, "")}${path}`;

// Sends a "simple" CORS request (text/plain, no custom headers) so the
// browser never issues a preflight OPTIONS — some dev tunnels (cloudflared)
// strip CORS headers from OPTIONS responses and break preflight. The token
// rides in the body instead of the Authorization header for the same reason.
async function postJson(path, token, body) {
  const response = await fetch(apiUrl(path), {
    method: "POST",
    headers: { "Content-Type": "text/plain;charset=UTF-8" },
    body: JSON.stringify({ token, ...(body || {}) }),
  });
  if (!response.ok) {
    throw new Error(`Request to ${path} failed with status ${response.status}`);
  }
  return response.json();
}

extend("Checkout::PostPurchase::ShouldRender", async ({ inputData, storage }) => {
  try {
    const referenceId = inputData?.initialPurchase?.referenceId;
    const token = inputData?.token;
    if (!referenceId || !token) {
      return { render: false };
    }

    const data = await postJson("/api/post_purchase/offer", token, {
      reference_id: referenceId,
    });

    if (!data?.render || !data?.offer) {
      return { render: false };
    }

    await storage.update({ offer: data.offer, token, referenceId });
    return { render: true };
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error("[post-purchase] ShouldRender error:", error);
    return { render: false };
  }
});

render("Checkout::PostPurchase::Render", App);

export function App({ storage, applyChangeset, done }) {
  const initial = storage.initialData || {};
  const offer = initial.offer;
  const token = initial.token;
  const referenceId = initial.referenceId;

  const trackEvent = (eventType, extra) => {
    return postJson("/api/post_purchase/events", token, {
      event_type: eventType,
      reference_id: referenceId,
      offer_id: offer?.id,
      ...(extra || {}),
    }).catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[post-purchase] event tracking failed:", error);
    });
  };

  const handleDecline = async () => {
    await trackEvent("rejected");
    done();
  };

  const handleAccept = async () => {
    try {
      const { token: signedToken } = await postJson(
        "/api/post_purchase/sign_changeset",
        token,
        { reference_id: referenceId, offer_id: offer.id },
      );
      if (!signedToken) throw new Error("Backend did not return a signed token");

      await applyChangeset(signedToken);

      await trackEvent("accepted", {
        revenue_added: Number(offer.discounted_price) || 0,
        offered_price: Number(offer.discounted_price) || 0,
      });
      done();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[post-purchase] accept error:", error);
      await trackEvent("error", { error_message: String(error?.message || error) });
      // Always continue safely.
      done();
    }
  };

  if (!offer) {
    return (
      <BlockStack spacing="loose">
        <CalloutBanner>No offer available.</CalloutBanner>
        <Button onPress={done}>Continue</Button>
      </BlockStack>
    );
  }

  return (
    <BlockStack spacing="loose">
      <CalloutBanner title="Complete your order with this recommended add-on">
        One-time offer for your order — added at the discounted price.
      </CalloutBanner>

      <Layout
        maxInlineSize={0.95}
        media={[
          { viewportSize: "small", sizes: [1, 30, 1] },
          { viewportSize: "medium", sizes: [300, 30, 0.5] },
          { viewportSize: "large", sizes: [400, 30, 0.33] },
        ]}
      >
        <View>
          {offer.image_url ? <Image source={offer.image_url} /> : null}
        </View>
        <View />
        <BlockStack spacing="xloose">
          <TextContainer>
            <Heading>{offer.title}</Heading>
            {offer.description ? <TextBlock>{offer.description}</TextBlock> : null}
          </TextContainer>

          <Tiles>
            <BlockStack spacing="tight">
              <TextBlock subdued>Original price</TextBlock>
              <Text>{`${offer.currency} ${offer.original_price}`}</Text>
            </BlockStack>
            <BlockStack spacing="tight">
              <TextBlock subdued>Today only</TextBlock>
              <Text emphasized size="medium">{`${offer.currency} ${offer.discounted_price}`}</Text>
            </BlockStack>
          </Tiles>

          <ButtonGroup>
            <Button submit onPress={handleAccept}>
              Add to my order
            </Button>
            <Button subdued onPress={handleDecline}>
              No thanks
            </Button>
          </ButtonGroup>
        </BlockStack>
      </Layout>
    </BlockStack>
  );
}
