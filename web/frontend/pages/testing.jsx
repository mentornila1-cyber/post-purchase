import { Page, Layout, Card, List, TextStyle, Stack, Heading } from "@shopify/polaris";
import { TitleBar } from "@shopify/app-bridge-react";

export default function TestingPage() {
  return (
    <Page title="Testing">
      <TitleBar title="Testing" />
      <Layout>
        <Layout.Section>
          <Card title="Test the post-purchase flow" sectioned>
            <Stack vertical spacing="loose">
              <p>
                Use Shopify's Bogus Gateway test payment provider on your development store to walk
                through the full buyer flow.
              </p>
              <List type="number">
                <List.Item>Run <TextStyle variation="code">yarn dev</TextStyle> and keep it running.</List.Item>
                <List.Item>
                  Update the <TextStyle variation="code">APP_URL</TextStyle> constant in
                  <TextStyle variation="code"> extensions/post-purchase-ui-extension/src/index.jsx</TextStyle>
                  to match the tunnel URL printed by the CLI.
                </List.Item>
                <List.Item>
                  In your dev store admin, go to <TextStyle variation="strong">Settings → Checkout</TextStyle> →
                  <TextStyle variation="strong"> Post-purchase page</TextStyle> and select this app's
                  extension.
                </List.Item>
                <List.Item>Add a trigger product to the cart (e.g. a snowboard).</List.Item>
                <List.Item>
                  Complete checkout using Bogus Gateway (card number{" "}
                  <TextStyle variation="code">1</TextStyle>, any future expiry, any CVC).
                </List.Item>
                <List.Item>The post-purchase offer should render before the thank-you page.</List.Item>
                <List.Item>Click <TextStyle variation="strong">Add to my order</TextStyle> or <TextStyle variation="strong">No thanks</TextStyle>.</List.Item>
                <List.Item>Open the Dashboard and Event log to confirm the event was tracked.</List.Item>
              </List>
            </Stack>
          </Card>
        </Layout.Section>

        <Layout.Section>
          <Card title="Trigger expectations" sectioned>
            <Stack vertical spacing="loose">
              <Heading element="h3">How offers are matched</Heading>
              <p>
                The current rule-based scorer awards points for product, variant, product type,
                and tag matches against the line items in the post-purchase token. Offers also
                receive points for having a discount and a high priority. The highest-scoring
                active offer wins.
              </p>
              <p>
                <TextStyle variation="subdued">
                  Note: in this MVP the post-purchase token only exposes line item product IDs and
                  variant IDs — not product types or tags. Tag and product-type triggers therefore
                  only fire when those fields are populated by an order context fetch.
                </TextStyle>
              </p>
            </Stack>
          </Card>
        </Layout.Section>

        <Layout.Section>
          <Card title="Troubleshooting" sectioned>
            <List>
              <List.Item>
                <TextStyle variation="strong">Extension never loads</TextStyle> — confirm the
                Post-purchase page setting in Shopify admin is set to this extension.
              </List.Item>
              <List.Item>
                <TextStyle variation="strong">"Failed to fetch" in the browser console</TextStyle> —
                the tunnel URL in <TextStyle variation="code">APP_URL</TextStyle> is stale. Restart{" "}
                <TextStyle variation="code">yarn dev</TextStyle> and update the constant.
              </List.Item>
              <List.Item>
                <TextStyle variation="strong">401 in Rails logs</TextStyle> — the JWT was rejected.
                Check that <TextStyle variation="code">SHOPIFY_API_SECRET</TextStyle> matches the
                signing secret. Check the <TextStyle variation="code">[PostPurchase]</TextStyle>{" "}
                log entries for details.
              </List.Item>
              <List.Item>
                <TextStyle variation="strong">applyChangeset error</TextStyle> — the variant ID on
                the offer needs to be a real numeric variant ID for your dev store.
              </List.Item>
            </List>
          </Card>
        </Layout.Section>
      </Layout>
    </Page>
  );
}
