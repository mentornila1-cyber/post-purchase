import { useState } from "react";
import { useQuery } from "react-query";
import {
  Page,
  Layout,
  Card,
  DataTable,
  EmptyState,
  Spinner,
  Select,
  Banner,
} from "@shopify/polaris";
import { TitleBar } from "@shopify/app-bridge-react";

const TYPE_OPTIONS = [
  { label: "All events", value: "" },
  { label: "Impression", value: "impression" },
  { label: "Accepted", value: "accepted" },
  { label: "Rejected", value: "rejected" },
  { label: "Error", value: "error" },
];

export default function EventsPage() {
  const [filter, setFilter] = useState("");

  const { data: events = [], isLoading, isError } = useQuery({
    queryKey: ["events", filter],
    queryFn: async () => {
      const url = filter ? `/api/events?type=${filter}` : "/api/events";
      const res = await fetch(url);
      if (!res.ok) throw new Error("Failed to load events");
      return res.json();
    },
  });

  return (
    <Page title="Event log">
      <TitleBar title="Event log" />
      <Layout>
        <Layout.Section>
          <Card sectioned>
            <Select
              label="Filter by type"
              labelInline
              options={TYPE_OPTIONS}
              value={filter}
              onChange={setFilter}
            />
          </Card>
        </Layout.Section>

        <Layout.Section>
          <Card sectioned>
            {isLoading ? (
              <Spinner />
            ) : isError ? (
              <Banner status="critical">Could not load events.</Banner>
            ) : events.length === 0 ? (
              <EmptyState heading="No events match this filter">
                <p>Place a test order on your dev store to generate events.</p>
              </EmptyState>
            ) : (
              <DataTable
                columnContentTypes={["text", "text", "text", "text", "numeric", "text"]}
                headings={["Time", "Event", "Offer", "Reference", "Revenue", "Error"]}
                rows={events.map((e) => [
                  new Date(e.created_at).toLocaleString(),
                  e.event_type,
                  e.offer_title || "—",
                  e.reference_id || "—",
                  e.revenue_added > 0 ? `USD ${e.revenue_added.toFixed(2)}` : "—",
                  e.error_message || "—",
                ])}
              />
            )}
          </Card>
        </Layout.Section>
      </Layout>
    </Page>
  );
}
