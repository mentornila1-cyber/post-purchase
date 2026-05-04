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
| `rule_based` | Safe deterministic default | Filters out already-purchased products/variants, then scores remaining active offers using product/variant matches, price fit, and discount | Reliable checkout behavior and explainable MVP logic |
| `manual_priority` | Merchant override | Picks the highest-priority active offer that was not already purchased | Campaigns where the merchant wants direct control |
| `ai_reasoning` | Runtime AI-assisted selection | Sends order context and eligible offers to OpenAI, validates the structured recommendation, merges AI score adjustments with deterministic scoring, and falls back to rules on failure | Demonstrating personalized, revenue-focused offer reasoning |

All three return the same result shape: the selected offer, a
merchant-readable decision reason, a score breakdown, and candidate scores.
That shared interface keeps the checkout extension and analytics code
independent of the selection method.

All three strategies receive the same normalized order context and active
offer catalog. They differ only in how they use those inputs.

Example order context:

```json
{
  "reference_id": "9c5824a4870ca31c9957f815926bfd17",
  "subtotal": 749.95,
  "currency": "USD",
  "customer_id": 8485193285692,
  "destination_country": "US",
  "line_items": [
    {
      "product_id": "gid://shopify/Product/8906386735164",
      "variant_id": "gid://shopify/ProductVariant/44848386539580",
      "title": "The Collection Snowboard: Liquid",
      "quantity": 1,
      "price": 749.95
    }
  ]
}
```

Example active offers:

```json
[
  {
    "id": 1,
    "title": "Ski Wax",
    "shopify_product_id": "gid://shopify/Product/111",
    "shopify_variant_id": "gid://shopify/ProductVariant/222",
    "discounted_price": 19.96,
    "discount_type": "percentage",
    "discount_value": 20,
    "trigger_product_ids": ["gid://shopify/Product/8906386735164"],
    "trigger_variant_ids": ["gid://shopify/ProductVariant/44848386539580"],
    "priority": 100,
    "active": true
  }
]
```

### `rule_based` (default)

Deterministic scoring. Rails first removes any offer whose product or variant
is already in the completed order. It then scores every remaining active offer
with `OfferScoringService` and selects the highest positive score. If every
score is `0` or lower, no offer is shown.

For every active offer, the scorer computes a total from these dimensions:

| Dimension | Points | Fires when... |
|---|---|---|
| product_match | +50 | Offer's `trigger_product_ids` contains a purchased product |
| variant_match | +40 | Offer's `trigger_variant_ids` contains a purchased variant |
| price_fit | +15 | Offer price is 15–50% of the order subtotal |
| discount | +10 | Offer has a non-zero discount |

The highest scorer with a positive total wins. Each decision is stored in
`OfferDecision` with the full `score_breakdown` and a human-readable
`decision_reason` so selections are auditable.

Priority is intentionally not part of `rule_based`; use `manual_priority`
when the merchant's priority field should control selection. If two offers
have the same rule-based score, the older/lower-id offer wins as a simple POC
tie-breaker.

The admin offer form supports selecting multiple trigger products and
multiple trigger variants. Product triggers match any purchased variant of
that product; variant triggers add a more specific match when the order
contains one of the selected variants.

With the example above, `rule_based` sees that the purchased snowboard
matches both the Ski Wax trigger product and trigger variant, then adds the
discount bonus. That makes Ski Wax a high-scoring cross-sell without relying
on merchant priority.

### `manual_priority`

Merchant-controlled ordering. Rails loads active offers by
`priority DESC, id ASC`, removes any offer whose product or variant is already
in the completed order, then chooses the first remaining offer.

This strategy ignores trigger products, trigger variants, discount size, and
price fit. That is deliberate: it is for campaign moments where the merchant
wants direct control over what gets promoted. The saved decision reason looks
like:

```text
Manual priority: highest-priority eligible offer (priority 90)
```

With the example above, `manual_priority` does not care that Ski Wax matches
the snowboard trigger. It only checks that Ski Wax was not already purchased,
then compares priority against the other active offers.

### `ai_reasoning`

LLM-assisted deterministic strategy. When `OPENAI_API_KEY` is configured,
Rails sends a compact order summary and active offer catalog to OpenAI's
Responses API with this instruction prompt:

```text
You select one Shopify post-purchase upsell or cross-sell offer.
Choose only from the provided offer IDs.
Do not choose a product or variant the customer already purchased.
Prefer offers that are relevant to the purchased item, priced as a
low-friction add-on, discounted enough to feel urgent, and likely to
increase order value.
Return concise JSON only.
```

The response is constrained to structured JSON shaped like this:

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

The AI input includes:

- order subtotal, currency, destination country
- purchased product/variant IDs, titles, quantities, and prices
- eligible active offers only
- each offer's title, description, product/variant IDs, price, discount,
  priority, and deterministic base score
- scoring guidance for relevance, margin/price fit, and customer intent

With the example above, `ai_reasoning` sends the snowboard line item plus
the eligible offer catalog to OpenAI. The model can then explain that Ski Wax
is relevant because it is a low-friction maintenance add-on for a snowboard,
while Rails still validates that the selected offer ID is allowed.

The backend never blindly trusts the model. It verifies that the returned
offer ID belongs to the active eligible offers, rejects products already in
the order, merges the AI-provided score adjustments with the deterministic
`OfferScoringService` score, and stores the full breakdown in
`OfferDecision`. If OpenAI is not configured, times out, returns invalid
JSON, or chooses an invalid offer, the strategy falls back to `rule_based`.

In plain English: the model can influence relevance, but Rails still controls
the candidate set, validates the selected offer, stores the rationale, and
keeps a deterministic fallback.

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

## Architectural decisions

### 1. Start from Shopify's official Ruby template

I started from `shopify-app-template-ruby` instead of wiring OAuth,
embedded-app auth, session storage, webhooks, and Shopify API setup by hand.
That kept the project focused on the assignment's actual problem:
post-purchase offers, checkout lifecycle integration, offer selection, and
analytics.

The tradeoff is that the repo carries some standard Shopify template
structure, such as `User`, `Shop`, embedded auth routes, and webhook
controllers. I kept that structure because it is familiar to Shopify
developers and gives the app a production-shaped foundation.

### 2. Support three offer-selection strategies

The app intentionally has three ways to decide which offer to show:
`rule_based`, `manual_priority`, and `ai_reasoning`. This makes the offer
engine easier to compare and reason about instead of betting everything on
one approach.

`rule_based` is the reliable deterministic baseline, `manual_priority` gives
the merchant direct campaign control, and `ai_reasoning` tests whether a
runtime LLM can choose a more relevant cross-sell from the order context. All
three strategies return the same result shape, so the checkout controller,
extension, and analytics layer do not care which strategy won.

### 3. Keep the checkout extension as thin as possible

The extension handles Shopify lifecycle work only: `ShouldRender` asks Rails
for an offer, `Render` displays it, accept signs/applies the changeset, and
decline tracks rejection. Rails owns the stateful logic: JWT decoding, offer
selection, analytics, and changeset signing.

This keeps buyer-facing checkout code small and reduces risk in the most
sensitive part of the flow.

### 4. Treat Rails as the trusted system boundary

The extension never receives `SHOPIFY_API_SECRET` and never builds arbitrary
changesets on its own. When the buyer accepts an offer, the extension sends
`reference_id` and `offer_id` to Rails. Rails re-loads the active offer,
builds the changeset, signs it server-side, and returns the token for
`applyChangeset()`.

That separation keeps secrets and trust decisions out of browser code.

### 5. Make every offer decision explainable

Every selected offer writes an `OfferDecision` with the winning offer,
candidate scores, score breakdown, and a human-readable reason. This is
especially useful for AI-assisted selection: the model can recommend, but
Rails validates the response and records why it was accepted.

That turns the offer engine into something auditable instead of a black box,
which matters for both debugging and merchant trust.

### 6. Use `reference_id` for post-purchase idempotency

Shopify can call `ShouldRender` more than once for the same checkout. The
app uses `reference_id` as an idempotency key: the first request creates the
`OfferDecision` and impression, and later requests for the same purchase
reuse the decision without rerunning scoring or AI.

This keeps analytics clean and avoids unnecessary OpenAI calls.

### 7. Read merchant setup data from Shopify

The offer form loads active products and variants from Shopify Admin GraphQL
instead of asking merchants to paste product and variant IDs. The app still
stores concrete product/variant identifiers on `Offer`, because the
post-purchase changeset must add one specific variant.

This keeps setup closer to how a real Shopify admin app would work while
staying simple enough for the POC.

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
- **SQLite database.** Fine locally; switch to Postgres for any real
  deployment.
- **No background workers used.** Event tracking writes synchronously.
  At scale, push these to Sidekiq.

---

## Production improvements

If this were graduating to a real revenue app, I would keep the first
production focus on post-purchase reliability and measurable lift.

### 1. Make checkout fast and reliable

Checkout should stay fast even when AI, analytics, or Shopify Admin API calls
are slow. The app already reuses an `OfferDecision` for duplicate
`ShouldRender` calls with the same `reference_id`; production can broaden
that into a short-lived cache keyed by
`(shop_id, strategy, order-context hash, active-offer-set hash)` so equivalent
inputs avoid another OpenAI call.

I would also precompute AI reasoning outside checkout with a scheduled worker.
That worker could build "reasoning profiles" for common purchase scenarios:
product-to-offer pairings, bundle recommendations, low-cost accessory matches,
and margin-friendly alternatives. At checkout time, Rails would first read the
prepared recommendation table and only call OpenAI when the input is novel or
stale.

### 2. Improve offer intelligence

The current scoring uses product/variant triggers, price fit, discount, and
AI reasoning. Production should enrich the purchase context with Admin API
data for product type/tags, skip out-of-stock variants, add margin-aware
scoring, and support customer-level logic such as frequency capping and
purchase history. A more advanced scorer could also add an explicit
already-purchased or previously-shown penalty, but this POC keeps that as an
eligibility filter instead of a score dimension.

This is also where I would add a `Strategies::RotationAB` strategy to split
traffic across multiple offers and use the existing `OfferEvent` data to
measure lift.

### 3. Improve analytics

The current dashboard covers impressions, accepts, rejects, conversion rate,
revenue, top offers, and recent events. A production version should add date
filters, per-offer funnels, revenue per impression, customer/cohort segments,
and exportable reporting.

Longer term, the goal would be measuring incremental lift rather than only
counting accepted offer revenue.

### 4. Make data and operations production-grade

SQLite is fine for local development. Production should use Postgres for app
data, Redis for cache/idempotency, and Sidekiq for async work such as
analytics writes, webhook sync, and AI precomputation.

I would also add Sentry/Datadog monitoring, alerts on `error` event rate,
webhook-driven order syncing to backfill `order_id` and customer data, strict
CORS allowlists, least-privilege Shopify scopes, and secret management for
`SHOPIFY_API_SECRET` and `OPENAI_API_KEY`.

### 5. Make merchant setup better

The current offer form loads active products and variants through Admin
GraphQL, but it uses simple selects and only fetches the first 50 products. A
production version should use Shopify's ResourcePicker, product search,
pagination, inventory/price validation, and a preview/test mode so merchants
can confidently configure offers without touching raw IDs.

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
