# Post-Purchase Upsell App

A Shopify app that runs upsell and cross-sell offers in the post-purchase
checkout flow. After a buyer completes payment, the app inspects the order,
selects the most relevant offer, presents it as an additional purchase, and
tracks the result for analytics.

```
Customer pays
  → Shopify loads the post-purchase extension
  → Extension asks the Rails backend for an offer
  → Rails picks the best active offer for this order
  → Extension shows it; buyer accepts or declines
  → If accepted, Rails signs a changeset; extension applies it
  → Buyer continues to the thank-you page
  → Admin dashboard updates with impressions, accepts, rejects, revenue
```

---

## Tech stack

| Layer | Choice |
|---|---|
| Backend | Rails 7.1 (the official `shopify_app` Ruby template) |
| Database | SQLite (dev), trivially swappable for Postgres in production |
| Admin frontend | React 18 + Shopify Polaris (embedded app) |
| Buyer surface | `@shopify/post-purchase-ui-extensions-react` (classic post-purchase extension) |
| Shopify APIs | Post-purchase JWT / changesets, Admin GraphQL product catalog |
| Tooling | Shopify CLI, Vite, react-query, JWT (`jwt` gem) |

This project started from Shopify's official Ruby app template:
`https://github.com/Shopify/shopify-app-template-ruby`. The post-purchase
extension was generated with Shopify CLI:

```bash
shopify app generate extension --template post_purchase_ui --name my-post-purchase-ui-extension
```

---

## Architecture

```
┌─ Shopify checkout (browser) ────────────────────┐
│                                                 │
│   Post-purchase extension (React)               │
│   • ShouldRender → POST /api/post_purchase/offer│
│                  → Rails decodes Shopify JWT    │
│   • Render       → shows offer + buttons        │
│   • Accept       → POST .../sign_changeset      │
│                  → applyChangeset(token)        │
│                  → POST .../events  (accepted)  │
│   • Decline      → POST .../events  (rejected)  │
│                                                 │
└────────────────────┬────────────────────────────┘
                     │ HTTPS (text/plain body)
                     │
┌────────────────────▼────────────────────────────┐
│  Rails backend                                  │
│                                                 │
│  Controllers                                    │
│   • PostPurchase::OffersController              │
│   • PostPurchase::ChangesetsController          │
│   • PostPurchase::EventsController              │
│   • OffersController        (admin CRUD)        │
│   • Shopify::ProductsController                 │
│                            (active product data)│
│   • AnalyticsController     (dashboard data)    │
│   • EventsController        (event log)         │
│   • ShopSettingsController  (strategy picker)   │
│                                                 │
│  Services (app/services/post_purchase/)         │
│   • OrderContextParser   – extracts order from  │
│                            the JWT input_data   │
│   • OfferSelector        – dispatches to a      │
│                            strategy             │
│   • Strategies::         – RuleBased,           │
│                            ManualPriority,      │
│                            AiReasoning          │
│   • OfferScoringService  – deterministic score  │
│   • ChangesetBuilder     – builds the           │
│                            applyChangeset body  │
│   • ChangesetSigner      – HS256 JWT signing    │
│   • EventTracker         – persists events,     │
│                            never raises         │
│   • AnalyticsService     – metrics for the      │
│                            dashboard            │
│                                                 │
│  Services (app/services/shopify/)               │
│   • ProductCatalogService – Admin GraphQL query │
│                             for active products │
│                             and variants        │
│                                                 │
│  Models                                         │
│   • Shop                 – Shopify session +    │
│                            selection_strategy   │
│   • User                 – online session model │
│                            from shopify_app     │
│   • Offer                – upsell catalog       │
│   • OfferEvent           – impression / accepted│
│                            / rejected / error   │
│   • OfferDecision        – why an offer won     │
│                            (audit trail)        │
└─────────────────────────────────────────────────┘
```

---

## Local setup

### Prerequisites

- Ruby 3.3
- Node.js (LTS)
- Yarn
- Shopify CLI (`npm install -g @shopify/cli @shopify/app`)
- A Shopify Partners account with a development store

### One-time install

```bash
# Install JS dependencies
yarn install

# Install gems and run migrations
cd web && bundle install && bin/rails db:migrate db:seed && cd ..
```

### Run the app

```bash
# Optional: enables the AI-assisted offer strategy.
# Without this, ai_reasoning falls back to rule_based.
export OPENAI_API_KEY="your_api_key_here"
export OPENAI_MODEL="gpt-5.4-mini"

yarn dev
```

The Shopify CLI starts:

- A `*.trycloudflare.com` tunnel
- The Rails backend on its own port (proxied through the tunnel)
- The React admin frontend (Vite)
- A live-rebuilding extension worker

Open the URL the CLI prints to install the app on your dev store.
If you previously installed the app with older scopes, reinstall it so the
admin offer form can read products and variants for its selectors.
The app currently requests `read_products,write_products`; `read_products`
is what powers the offer product and trigger selectors.

### Wire the post-purchase extension to your dev store

1. In your dev store admin, go to **Settings → Checkout**, scroll to
   **Post-purchase page**, and select this app's extension. Without this
   the extension never loads, even if everything else is configured.
2. Open `extensions/post-purchase-ui-extension/src/index.jsx` and update
   the `APP_URL` constant to the tunnel URL the CLI is currently printing.
   This URL changes every time `yarn dev` restarts.

### Test with Bogus Gateway

1. Make sure Bogus Gateway is enabled in your dev store payment settings.
2. To demo AI selection, set `OPENAI_API_KEY` before `yarn dev` and choose
   **AI reasoning** on the Dashboard's strategy card. Without a key, this
   strategy safely falls back to rule-based scoring.
3. Add a snowboard to the cart.
4. Check out using card number `1`, any future expiry, any CVC.
5. The post-purchase offer renders before the thank-you page.
6. Accept or decline.
7. Open the embedded admin app — Dashboard / Event log will reflect the event.

---

## Configuring offers

The Offers page is the merchant-facing offer catalog. It loads active
Shopify products and variants from `GET /api/shopify/products`, which is
backed by Admin GraphQL. Creating an offer works like this:

1. Select one offer product and one offer variant. The variant GID is stored
   on the offer; the post-purchase changeset derives the numeric variant ID
   from that GID when needed.
2. Original price and image URL are filled from Shopify product data when
   available. They remain editable so the demo can recover if Shopify data is
   incomplete.
3. Enter discount type/value. The discounted price is calculated in the form
   and persisted with the offer.
4. Select one or more trigger products, and optionally one or more trigger
   variants from those products. The offer becomes eligible when the completed
   order contains any selected trigger.
5. Set priority and active/inactive status.

This keeps the admin workflow closer to a real Shopify app: merchants pick
products from their store instead of pasting product and variant IDs by hand.

---

## How offer selection works

Selection is dispatched to a **strategy** based on the shop's
`selection_strategy` column. Three strategies live behind the same
interface in `web/app/services/post_purchase/strategies/`:

| Strategy | Purpose | How it decides | Best use |
|---|---|---|---|
| `rule_based` | Safe deterministic default | Scores each active offer using product/variant matches, price fit, discount, priority, and an already-purchased penalty | Reliable checkout behavior and explainable MVP logic |
| `manual_priority` | Merchant override | Picks the highest-priority active offer that was not already purchased | Campaigns where the merchant wants direct control |
| `ai_reasoning` | Runtime AI-assisted selection | Sends order context and eligible offers to OpenAI, validates the structured recommendation, merges AI score adjustments with deterministic scoring, and falls back to rules on failure | Demonstrating personalized, revenue-focused offer reasoning |

All three return the same result shape: the selected offer, a
merchant-readable decision reason, a score breakdown, and candidate scores.
That shared interface keeps the checkout extension and analytics code
independent of the selection method.

### `rule_based` (default)

Deterministic scoring. For every active offer the
`OfferScoringService` computes a total from these dimensions:

| Dimension | Points | Fires when... |
|---|---|---|
| product_match | +50 | Offer's `trigger_product_ids` contains a purchased product |
| variant_match | +40 | Offer's `trigger_variant_ids` contains a purchased variant |
| price_fit | +15 | Offer price is 15–50% of the order subtotal |
| discount | +10 | Offer has a non-zero discount |
| priority | up to +10 | `priority / 10`, capped at 10 |
| already_purchased_penalty | −100 | Offered product/variant is already in the order |

The highest scorer with a positive total wins. Each decision is stored in
`OfferDecision` with the full `score_breakdown` and a human-readable
`decision_reason` so selections are auditable.

The admin offer form supports selecting multiple trigger products and
multiple trigger variants. Product triggers match any purchased variant of
that product; variant triggers add a more specific match when the order
contains one of the selected variants.

### `manual_priority`

Pure `priority DESC` ordering. Triggers and scoring are ignored — the
merchant is in full control via the **Priority** field on each offer.
Already-purchased offers are filtered out so we never re-offer the same
thing.

### `ai_reasoning`

LLM-assisted deterministic strategy. When `OPENAI_API_KEY` is configured,
Rails sends a compact order summary and active offer catalog to OpenAI's
Responses API and asks for structured JSON:

```json
{
  "offer_id": "123",
  "rationale": "Thermal socks complement a snowboard order...",
  "score_adjustments": {
    "relevance": 22,
    "margin_fit": 12,
    "customer_intent": 10
  }
}
```

The backend never blindly trusts the model. It verifies that the returned
offer ID belongs to the active eligible offers, rejects products already in
the order, merges the AI-provided score adjustments with the deterministic
`OfferScoringService` score, and stores the full breakdown in
`OfferDecision`. If OpenAI is not configured, times out, returns invalid
JSON, or chooses an invalid offer, the strategy falls back to `rule_based`.

The merchant switches strategy on the Dashboard's "Offer selection
strategy" card, backed by `GET/PATCH /api/shop_settings`.

---

## Event tracking and analytics

Every meaningful step writes an `OfferEvent`:

- `impression` — written when an offer is selected and returned to the
  extension. Repeated `ShouldRender` calls for the same `reference_id` reuse
  the original `OfferDecision` and do not write duplicate impressions.
- `accepted` — written after `applyChangeset` succeeds. Includes
  `revenue_added` for the dashboard's revenue total.
- `rejected` — written when the buyer clicks "No thanks".
- `error` — written if anything in the selection / signing / apply chain
  fails. The buyer flow always continues (`done()` is always called) so
  tracking failures never block checkout.

The dashboard at `/` (the embedded admin app's home page) reads
`/api/analytics/offers`, which returns:

- Total impressions / acceptances / rejections
- Conversion rate (`accepts / impressions × 100`)
- Total revenue generated
- Top offers ranked by revenue
- Recent events feed

The Event log page at `/events` reads `/api/events?type=...&limit=...`
for filterable history.

### Duplicate `ShouldRender` calls

Shopify may invoke `Checkout::PostPurchase::ShouldRender` more than once for
the same checkout. In local testing, the first call can contain partial
purchase context, such as no customer/destination and a `0.0` subtotal, while
a later call for the same `referenceId` contains fuller order context.

The app treats `reference_id` as an idempotency key. The first request creates
an `OfferDecision` and tracks one impression. Later requests with the same
`reference_id` reuse that decision, skip AI/scoring, and avoid duplicate
impression events. This keeps analytics clean even when Shopify re-evaluates
the extension lifecycle.

---

## Key technical decisions

### 1. Keep the checkout extension thin

The post-purchase extension only does lifecycle work: `ShouldRender`
asks Rails whether an offer should appear, `Render` displays the selected
offer, and accept/decline sends the buyer's response back to Rails. Offer
selection, analytics writes, and changeset signing all stay out of the
extension.

This keeps the buyer-facing code small and resilient. The tradeoff is
that the extension needs the current app tunnel URL during local
development, so `APP_URL` must be updated when `shopify app dev` starts a
new tunnel.

### 2. Use Rails as the trusted backend

Rails owns the sensitive and stateful work: decoding Shopify's
post-purchase JWT, looking up the shop, selecting an offer, persisting
events, and signing the post-purchase changeset with `SHOPIFY_API_SECRET`.
The extension never receives the Shopify secret and cannot submit an
arbitrary changeset.

The extension sends only `{reference_id, offer_id}` to
`POST /api/post_purchase/sign_changeset`. Rails re-loads the active offer,
builds the changeset server-side, signs it, and returns the token that the
extension passes to `applyChangeset()`.

### 3. Treat Shopify checkout as a reliability boundary

Checkout should never be blocked by analytics, AI, or network hiccups.
For that reason, every post-purchase endpoint is defensive: offer
selection errors return `{render: false}`, event tracking failures are
logged without raising, and accept errors are tracked before calling
`done()`.

The AI strategy follows the same rule. OpenAI can improve relevance, but
if it is missing, slow, or returns invalid JSON, Rails falls back to
deterministic rule-based scoring.

### 4. Strategy objects instead of controller branching

Offer selection lives behind one interface:
`call(shop:, order_context:) → { offer:, decision_reason:,
score_breakdown:, candidates: }`. `OfferSelector` reads
`Shop#selection_strategy` and dispatches to `RuleBased`, `ManualPriority`,
or `AiReasoning`.

This keeps the checkout controller stable while allowing the merchant to
switch strategy from the React/Polaris dashboard. Adding another strategy
would be a new service object, not a rewrite of the extension or
analytics layer.

### 5. Make offer decisions explainable

Every selected offer writes an `OfferDecision` row with the winning offer,
candidate scores, score breakdown, and a human-readable reason. This is
especially important for AI-assisted selection: the LLM recommends, but
Rails validates and records the rationale.

That gives the merchant an audit trail instead of a black box, and it
also makes the walkthrough easier: `OfferDecision.last` shows exactly why
the customer saw a specific offer.

### 6. Separate merchant admin from buyer checkout

The buyer surface is the Shopify post-purchase extension. The merchant
surface is a React app using Shopify Polaris and App Bridge, backed by
Rails JSON endpoints for offers, analytics, event logs, and shop
settings.

This split keeps the checkout UI focused on conversion while the embedded
admin app handles configuration and reporting. The Rails backend is the
shared contract between both surfaces.

### 7. Read offer setup data from Shopify

The offer form does not ask merchants to paste product IDs and variant IDs
from memory. It calls `GET /api/shopify/products`, and Rails uses the
Shopify Admin GraphQL API to return active products and variants for the
current shop.

The form still stores the concrete product and variant identifiers on
`Offer`, because the post-purchase changeset needs a specific variant to
add. Rails can derive the numeric variant ID from the Shopify variant GID,
so the admin UI only needs one variant selector.

---

## Limitations

These are intentional scope cuts. Listed here so future contributors
know what's *not* working and where the boundaries are.

- **Tag and product-type triggers don't fire.** The post-purchase JWT
  exposes `product.id`, `product.title`, `variant.id`, and metafields —
  but not `productType` or `tags`. The codebase used to score on those
  dimensions; those fields remain in the database from the original schema,
  but the admin UI no longer exposes them because they could not fire on
  real post-purchase data. Re-enabling requires an Admin API call to enrich
  line items.
- **`price_fit` can be inconsistent.** Shopify's
  `initialPurchase.totalPriceSet.shopMoney.amount` for the post-purchase
  context can be `0.0` on the first `ShouldRender` call, then populated on a
  later call for the same `referenceId`. The scorer handles this safely, but
  the dimension is less reliable than product/variant matching.
- **AI calls still run inline on the first `ShouldRender`.** This is
  acceptable for a demo because the strategy has a short timeout, falls back
  to `rule_based`, and now reuses the first `OfferDecision` if Shopify calls
  `ShouldRender` again for the same `reference_id`. Production should go
  further by caching equivalent order/offer inputs and preparing heavier
  reasoning ahead of checkout.
- **Product catalog loading is intentionally small.** The Offers page reads
  the first 50 active products and up to 50 variants per product through
  Admin GraphQL. That is enough for a development-store demo; production
  needs search and pagination.
- **CORS allows `*` origin.** Fine for dev; production would lock down
  to Shopify's checkout domains.
- **No ResourcePicker yet.** The offer form loads active products and
  variants through Shopify Admin GraphQL, but selection is still plain
  product/variant selects. A production version would replace this with
  App Bridge ResourcePicker for search, pagination, and a native Shopify
  admin feel.
- **SQLite database.** Fine locally; switch to Postgres for any real
  deployment.
- **No background workers used.** Event tracking writes synchronously.
  At scale, push these to Sidekiq.

---

## Production improvements

If this were graduating to a real revenue app, the rough order I'd
attack:

1. **Admin API enrichment of line items.** One GraphQL call during
   `ShouldRender` to resolve `productType` and `tags` for the purchased
   products, with a short cache on `(shop_id, product_id)`. Re-enables
   tag/type triggers.
2. **Broaden the decision cache beyond one checkout.** The app already
   reuses an `OfferDecision` for duplicate `ShouldRender` calls with the
   same `reference_id`. Production can go further: two buyers can produce
   the same effective input, such as the same purchased products, destination
   market, active offer set, and strategy version. Cache the selected offer
   by a fingerprint such as
   `(shop_id, strategy, order-context hash, active-offer-set hash)` with a
   short TTL so equivalent inputs can avoid another OpenAI call.
3. **Precompute AI reasoning outside checkout.** Add a scheduled worker
   that periodically builds "reasoning profiles" for common purchase
   scenarios: product-to-offer pairings, bundle recommendations, low-cost
   accessory matches, and margin-friendly alternatives. At checkout time,
   Rails would first read this prepared recommendation table and only call
   OpenAI when the input is novel or stale. This keeps the buyer path fast
   while still letting AI improve offer quality.
4. **Harden the AI strategy.** Add richer eval fixtures for different
   product bundles, cap model latency aggressively, log cache hit rate,
   and monitor fallback rate as an operational signal.
5. **Inventory awareness.** Skip offers whose variant is out of stock
   (another GraphQL hop, also cacheable).
6. **A/B testing.** Add a `Strategies::RotationAB` that splits traffic
   across multiple offers and uses the existing `OfferEvent` data to
   compute lift.
7. **Frequency capping.** Don't show the same customer the same offer
   twice in N days — a query against `OfferEvent`.
8. **Real Shopify resource picker** in the admin Offers form so merchants
   can search/select variants instead of pasting IDs.
9. **Observability.** Datadog/Sentry on the controllers; alerts on
   `error` event-type rate.
10. **Webhook-driven order syncing** to backfill `order_id` and customer
   data on `OfferEvent` after the order is created.
11. **Margin-aware scoring.** Add a `margin` field on Offer; the scorer
   prefers high-margin offers when ties happen.
12. **Move CORS off `*`** to an allowlist of Shopify checkout origins.
13. **Postgres + Sidekiq** for production; Redis for stronger cross-process
    idempotency and async analytics writes.
14. **Least-privilege Shopify scopes.** The demo currently requests
    `read_products,write_products`; the current offer flow only needs product
    reads, so production should remove unused scopes unless future admin
    features require them.
15. **Production secret management.** `SHOPIFY_API_SECRET` /
    `OPENAI_API_KEY` from the platform's secret store.

---

## Project layout

```
post-purchase/
├── extensions/
│   └── post-purchase-ui-extension/
│       └── src/index.jsx           # ShouldRender + Render + UI
│
├── web/
│   ├── app/
│   │   ├── controllers/
│   │   │   ├── post_purchase/      # extension-facing endpoints
│   │   │   ├── shopify/
│   │   │   │   └── products_controller.rb
│   │   │   │                            # Admin API product/variant catalog
│   │   │   ├── webhooks/           # Shopify app lifecycle/privacy webhooks
│   │   │   ├── analytics_controller.rb
│   │   │   ├── events_controller.rb
│   │   │   ├── home_controller.rb  # embedded app shell
│   │   │   ├── offers_controller.rb
│   │   │   └── shop_settings_controller.rb
│   │   ├── models/
│   │   │   ├── offer.rb
│   │   │   ├── offer_event.rb
│   │   │   ├── offer_decision.rb
│   │   │   ├── shop.rb
│   │   │   └── user.rb
│   │   └── services/
│   │       ├── post_purchase/
│   │       │   ├── strategies/
│   │       │   │   ├── base.rb
│   │       │   │   ├── rule_based.rb
│   │       │   │   ├── manual_priority.rb
│   │       │   │   └── ai_reasoning.rb
│   │       │   ├── analytics_service.rb
│   │       │   ├── changeset_builder.rb
│   │       │   ├── changeset_signer.rb
│   │       │   ├── event_tracker.rb
│   │       │   ├── offer_scoring_service.rb
│   │       │   ├── offer_selector.rb
│   │       │   └── order_context_parser.rb
│   │       └── shopify/
│   │           └── product_catalog_service.rb
│   │                                     # Active products/variants for admin selects
│   ├── db/
│   │   ├── migrate/                # offers, offer_events, offer_decisions, selection_strategy
│   │   └── seeds.rb                # Ski Wax demo offer
│   └── frontend/
│       ├── App.jsx                 # NavMenu + routes
│       └── pages/
│           ├── ExitIframe.jsx      # Shopify embedded-app escape page
│           ├── NotFound.jsx
│           ├── index.jsx           # Dashboard (home)
│           ├── offers.jsx          # CRUD admin
│           ├── events.jsx          # Filterable event log
│           └── testing.jsx         # In-app testing instructions
│
└── shopify.app.toml
```
