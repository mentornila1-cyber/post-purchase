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
| Frontend | React 18 + Shopify Polaris (embedded admin app) |
| Buyer surface | `@shopify/post-purchase-ui-extensions-react` (classic post-purchase extension) |
| Tooling | Shopify CLI, Vite, react-query, JWT (`jwt` gem) |

---

## Architecture

```
┌─ Shopify checkout (browser) ────────────────────┐
│                                                 │
│   Post-purchase extension (React)               │
│   • ShouldRender → POST /api/post_purchase/offer│
│   • Render       → shows offer + buttons        │
│   • Accept       → POST .../sign_changeset      │
│                  → applyChangeset(token)        │
│                  → POST .../events  (accepted)  │
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
│  Models                                         │
│   • Shop                 – Shopify session +    │
│                            selection_strategy   │
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
yarn dev
```

The Shopify CLI starts:

- A `*.trycloudflare.com` tunnel
- The Rails backend on its own port (proxied through the tunnel)
- The React admin frontend (Vite)
- A live-rebuilding extension worker

Open the URL the CLI prints to install the app on your dev store.

### Wire the post-purchase extension to your dev store

1. In your dev store admin, go to **Settings → Checkout**, scroll to
   **Post-purchase page**, and select this app's extension. Without this
   the extension never loads, even if everything else is configured.
2. Open `extensions/post-purchase-ui-extension/src/index.jsx` and update
   the `APP_URL` constant to the tunnel URL the CLI is currently printing.
   This URL changes every time `yarn dev` restarts.

### Test with Bogus Gateway

1. Make sure Bogus Gateway is enabled in your dev store payment settings.
2. Add a snowboard to the cart.
3. Check out using card number `1`, any future expiry, any CVC.
4. The post-purchase offer renders before the thank-you page.
5. Accept or decline.
6. Open the embedded admin app — Dashboard / Event log will reflect the event.

---

## How offer selection works

Selection is dispatched to a **strategy** based on the shop's
`selection_strategy` column. Three strategies live behind the same
interface in `web/app/services/post_purchase/strategies/`:

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

### `manual_priority`

Pure `priority DESC` ordering. Triggers and scoring are ignored — the
merchant is in full control via the **Priority** field on each offer.
Already-purchased offers are filtered out so we never re-offer the same
thing.

### `ai_reasoning`

Scaffold for an LLM-driven strategy. Checks for `ANTHROPIC_API_KEY` and
falls back to `rule_based` when not configured. The Anthropic API call
itself is documented as a future improvement — see "Production
improvements" below.

The merchant switches strategy on the Dashboard's "Offer selection
strategy" card, backed by `GET/PATCH /api/shop_settings`.

---

## Event tracking and analytics

Every meaningful step writes an `OfferEvent`:

- `impression` — written when an offer is selected and returned to the
  extension.
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

---

## Key technical decisions

### 1. Token in body, not Authorization header

The extension sends the post-purchase JWT inside the JSON body, not as
`Authorization: Bearer ...`. This keeps the request CORS-"simple"
(`Content-Type: text/plain`, no custom headers) so the browser never
issues a preflight OPTIONS. Cloudflare's `trycloudflare.com` dev tunnels
intercept OPTIONS and respond without `Access-Control-Allow-Origin`,
which would break the preflight even though the actual POST works fine.
Sending a simple request sidesteps the issue entirely and works the same
in dev and prod.

### 2. Server-side offer lookup before signing

The post-purchase changeset is signed with `SHOPIFY_API_SECRET`, which
must never leave the backend. The extension sends only `{reference_id,
offer_id}` to `POST /api/post_purchase/sign_changeset`. The backend
re-loads the offer from the database, validates it's still active, builds
the changeset server-side, and only then signs. The extension cannot
inject arbitrary changes — it just receives the signed token and forwards
it to `applyChangeset()`.

### 3. Strategies behind a single interface

Offer selection started as a single deterministic scorer, then we needed
to support manual and AI-driven approaches. Rather than branching inside
the selector, each approach is a `Strategies::*` class implementing one
method: `call(shop:, order_context:) → { offer:, decision_reason:,
score_breakdown:, candidates: }`. The selector is a thin dispatcher that
reads `Shop#selection_strategy` and instantiates the right class. Adding
a new strategy means one new file and zero changes to controllers or
models.

### 4. `OfferDecision` audit trail

Every selection writes an `OfferDecision` row capturing the winning
offer, the full score breakdown, every candidate considered, and a
human-readable reason. Pulling up `OfferDecision.last` shows exactly why
a particular customer was shown a particular offer — this is what makes
the system explainable rather than a black box.

### 5. Failures never block checkout

Every controller in `PostPurchase::*` has a top-level `rescue
StandardError`. Selection failure → returns `{render: false}`. Tracking
failure → swallowed and logged. Apply failure → tracked as `error` event
and `done()` is still called. The buyer never sees a broken page; the
merchant sees the failure in the Event log.

### 6. Two anchors to `/` in NavMenu

The App Bridge `NavMenu` requires a bare `rel="home"` link to wire up
the "click the app's name" navigation, but rendering the labeled
Dashboard link separately is what makes it visible in the nav. Hence
two anchors to `/` — one bare with `rel="home"` and one labeled
"Dashboard".

---

## Limitations

These are intentional scope cuts. Listed here so future contributors
know what's *not* working and where the boundaries are.

- **Tag and product-type triggers don't fire.** The post-purchase JWT
  exposes `product.id`, `product.title`, `variant.id`, and metafields —
  but not `productType` or `tags`. The codebase used to score on those
  dimensions; the branches were removed because they could never fire
  on real data. Re-enabling requires an Admin API call to enrich line
  items.
- **`price_fit` rarely fires.** Shopify's
  `initialPurchase.totalPriceSet.shopMoney.amount` for the post-purchase
  context is often `0.0` (it represents what's left to charge, not the
  order total), so the price-fit dimension is effectively dormant.
- **`ai_reasoning` is a scaffold.** It's wired as a strategy and falls
  back to `rule_based` when `ANTHROPIC_API_KEY` is unset, but the
  Anthropic API call itself is a TODO.
- **CORS allows `*` origin.** Fine for dev; production would lock down
  to Shopify's checkout domains.
- **Manual Shopify product/variant IDs.** No resource picker — merchants
  paste GIDs into the offer form. Acceptable for an MVP.
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
2. **Wire up the AI strategy.** Send `{order_context, candidate_offers}`
   to Claude with a structured-output prompt; store the rationale in
   `OfferDecision.decision_reason`. Cache by
   `(reference_id, offer-set hash)` to avoid redundant calls.
3. **Inventory awareness.** Skip offers whose variant is out of stock
   (another GraphQL hop, also cacheable).
4. **A/B testing.** Add a `Strategies::RotationAB` that splits traffic
   across multiple offers and uses the existing `OfferEvent` data to
   compute lift.
5. **Frequency capping.** Don't show the same customer the same offer
   twice in N days — a query against `OfferEvent`.
6. **Real Shopify resource picker** in the admin Offers form (App Bridge
   ResourcePicker).
7. **Observability.** Datadog/Sentry on the controllers; alerts on
   `error` event-type rate.
8. **Webhook-driven order syncing** to backfill `order_id` and customer
   data on `OfferEvent` after the order is created.
9. **Margin-aware scoring.** Add a `margin` field on Offer; the scorer
   prefers high-margin offers when ties happen.
10. **Move CORS off `*`** to an allowlist of Shopify checkout origins.
11. **Postgres + Sidekiq** for production; Redis for deduplication of
    duplicate `impression` writes.
12. **Production secret management.** `SHOPIFY_API_SECRET` /
    `ANTHROPIC_API_KEY` from the platform's secret store.

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
│   │   │   ├── analytics_controller.rb
│   │   │   ├── events_controller.rb
│   │   │   ├── offers_controller.rb
│   │   │   └── shop_settings_controller.rb
│   │   ├── models/
│   │   │   ├── offer.rb
│   │   │   ├── offer_event.rb
│   │   │   ├── offer_decision.rb
│   │   │   └── shop.rb
│   │   └── services/post_purchase/
│   │       ├── strategies/
│   │       │   ├── base.rb
│   │       │   ├── rule_based.rb
│   │       │   ├── manual_priority.rb
│   │       │   └── ai_reasoning.rb
│   │       ├── analytics_service.rb
│   │       ├── changeset_builder.rb
│   │       ├── changeset_signer.rb
│   │       ├── event_tracker.rb
│   │       ├── offer_scoring_service.rb
│   │       ├── offer_selector.rb
│   │       └── order_context_parser.rb
│   ├── db/
│   │   ├── migrate/                # offers, offer_events, offer_decisions, selection_strategy
│   │   └── seeds.rb                # Ski Wax demo offer
│   └── frontend/
│       ├── App.jsx                 # NavMenu + routes
│       └── pages/
│           ├── index.jsx           # Dashboard (home)
│           ├── offers.jsx          # CRUD admin
│           ├── events.jsx          # Filterable event log
│           └── testing.jsx         # In-app testing instructions
│
└── shopify.app.toml
```
