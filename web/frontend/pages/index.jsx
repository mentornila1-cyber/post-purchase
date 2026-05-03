import { useQuery, useMutation, useQueryClient } from "react-query";
import {
  Page,
  Layout,
  Card,
  DataTable,
  EmptyState,
  Spinner,
  Stack,
  TextStyle,
  Heading,
  Banner,
  Select,
} from "@shopify/polaris";
import { TitleBar, useAppBridge } from "@shopify/app-bridge-react";

const formatMoney = (amount, currency = "USD") =>
  `${currency} ${Number(amount || 0).toFixed(2)}`;

const formatPercent = (value) => `${Number(value || 0).toFixed(1)}%`;

function Metric({ label, value }) {
  return (
    <Card sectioned>
      <Stack vertical spacing="extraTight">
        <TextStyle variation="subdued">{label}</TextStyle>
        <Heading>{value}</Heading>
      </Stack>
    </Card>
  );
}

const STRATEGY_LABELS = {
  rule_based: "Rule-based scoring (deterministic)",
  manual_priority: "Manual priority (highest priority wins)",
  ai_reasoning: "AI reasoning (OpenAI — falls back to rules without API key)",
};

function StrategyCard() {
  const shopify = useAppBridge();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["shop-settings"],
    queryFn: async () => {
      const res = await fetch("/api/shop_settings");
      if (!res.ok) throw new Error("Failed to load settings");
      return res.json();
    },
    refetchOnWindowFocus: false,
  });

  const updateMutation = useMutation({
    mutationFn: async (selection_strategy) => {
      const res = await fetch("/api/shop_settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ shop: { selection_strategy } }),
      });
      if (!res.ok) throw new Error("Update failed");
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["shop-settings"] });
      shopify.toast.show("Strategy updated");
    },
    onError: () => shopify.toast.show("Could not update strategy", { isError: true }),
  });

  if (isLoading || !data) return null;

  const options = (data.available_strategies || []).map((value) => ({
    label: STRATEGY_LABELS[value] || value,
    value,
  }));

  return (
    <Card title="Offer selection strategy" sectioned>
      <Stack vertical spacing="tight">
        <TextStyle variation="subdued">
          Controls how the post-purchase extension picks an offer for each completed checkout.
        </TextStyle>
        <Select
          label="Strategy"
          labelInline
          options={options}
          value={data.selection_strategy}
          onChange={(value) => updateMutation.mutate(value)}
          disabled={updateMutation.isLoading}
        />
      </Stack>
    </Card>
  );
}

export default function HomePage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["analytics-offers"],
    queryFn: async () => {
      const res = await fetch("/api/analytics/offers");
      if (!res.ok) throw new Error("Failed to load analytics");
      return res.json();
    },
    refetchOnWindowFocus: false,
  });

  if (isLoading) {
    return (
      <Page>
        <Spinner />
      </Page>
    );
  }

  if (isError) {
    return (
      <Page title="Dashboard">
        <Banner status="critical">Could not load analytics.</Banner>
      </Page>
    );
  }

  const {
    total_impressions = 0,
    total_acceptances = 0,
    total_rejections = 0,
    conversion_rate = 0,
    revenue_generated = 0,
    top_offers = [],
    recent_events = [],
  } = data || {};

  const hasData = total_impressions > 0;

  return (
    <Page title="Dashboard">
      <TitleBar title="Dashboard" />
      <Layout>
        <Layout.Section>
          <StrategyCard />
        </Layout.Section>

        <Layout.Section>
          <Stack distribution="fillEvenly">
            <Metric label="Impressions" value={total_impressions} />
            <Metric label="Acceptances" value={total_acceptances} />
            <Metric label="Rejections" value={total_rejections} />
            <Metric label="Conversion rate" value={formatPercent(conversion_rate)} />
            <Metric label="Revenue" value={formatMoney(revenue_generated)} />
          </Stack>
        </Layout.Section>

        <Layout.Section>
          <Card title="Top performing offers" sectioned>
            {top_offers.length === 0 ? (
              <EmptyState heading="No offer performance yet">
                <p>Place a test order to see analytics.</p>
              </EmptyState>
            ) : (
              <DataTable
                columnContentTypes={["text", "numeric", "numeric", "numeric", "numeric", "numeric"]}
                headings={[
                  "Offer",
                  "Impressions",
                  "Accepts",
                  "Rejects",
                  "Conversion",
                  "Revenue",
                ]}
                rows={top_offers.map((o) => [
                  o.title,
                  o.impressions,
                  o.acceptances,
                  o.rejections,
                  formatPercent(o.conversion_rate),
                  formatMoney(o.revenue),
                ])}
              />
            )}
          </Card>
        </Layout.Section>

        <Layout.Section>
          <Card title="Recent events" sectioned>
            {recent_events.length === 0 ? (
              <EmptyState heading="No events yet">
                <p>Events will appear here as customers see and respond to offers.</p>
              </EmptyState>
            ) : (
              <DataTable
                columnContentTypes={["text", "text", "text", "text", "numeric"]}
                headings={["Time", "Event", "Offer", "Reference", "Revenue"]}
                rows={recent_events.map((e) => [
                  new Date(e.created_at).toLocaleString(),
                  e.event_type,
                  e.offer_title || "—",
                  e.reference_id || "—",
                  formatMoney(e.revenue_added),
                ])}
              />
            )}
          </Card>
        </Layout.Section>

        {!hasData && (
          <Layout.Section>
            <Banner>
              No offer events have been tracked yet. Place a test order on your dev store to see
              analytics here.
            </Banner>
          </Layout.Section>
        )}
      </Layout>
    </Page>
  );
}
