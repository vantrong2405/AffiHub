# Porting Note: affiliate-product-pipeline (ACCESSTRADE)

## Reference
- **Primary**: `tunguyendg/aff-pipeline` (license: none declared in repo — no LICENSE file found; treat as
  all-rights-reserved, behavior-only reference, no code copied verbatim).
- **Fallback read for architecture**: `Duke0503/shopee-aff` (MIT) — enterprise multi-platform
  affiliate/reconciliation platform, uses AccessTrade Publisher API for TikTok Shop and a headless
  browser bridge for Shopee.
- **Fallback read for Shopee-specific detail**: `bcat95/shopee-aff` — documentation-only repo for
  **Shopee's own official Affiliate Open API** (GraphQL) plus an unofficial third-party data API
  (`data.addlivetag.com`). Classification: Shopee Open API = Official; `data.addlivetag.com` =
  Unofficial/reverse-engineered (now requires its own API key); no code license, docs repo.

## Finding that changed the plan

**ACCESSTRADE's real public API (`api.accesstrade.vn`) is a link-conversion service, not a product
catalog/search API.** Verified from `tunguyendg/aff-pipeline/lib/accesstrade.py` (docstring marked
"verified" with dates):

```
POST https://api.accesstrade.vn/v1/product_link/create
Headers: Authorization: Token <ACCESSTRADE_TOKEN>
Body:    { "campaign_id": "...", "urls": ["<shopee product url>", ...], "utm_source": "..." }
Response: { data: { success_link: [{ url_origin, short_link, aff_link }], error_link: [], suspend_url: [] } }
```

The official ACCESSTRADE docs also describe `GET /v1/product_detail` for a known `merchant` and
`product_id`, returning details for one product. This is a detail lookup, not catalog search or
discovery, and the reference CSV-to-link flow does not call it. The POC will not infer a catalog API
from this endpoint. See the [official product detail docs](https://developers.accesstrade.vn/api-accesstrade-tai-lieu-tich-hop/get-detailed-information-of-the-product).

This `product_link/create` endpoint takes Shopee product URLs **you already have** and returns a
trackable `aff_link`/`short_link` for each. This link-creation response does **not** return
title/price/rating/sold/images/category/commission; those facts are not supplied by this endpoint.

In the reference pipeline, those catalog fields come from **Dataminer** (a paid browser-extension
Shopee scraper) exporting CSV files by hand — not from any ACCESSTRADE endpoint, not from an
automated pull. `csv_loader.py`/`scorer.py`/`categorizer.py` process that CSV; `accesstrade.py` is
called only at the very end, on the already-filtered/scored product URLs, purely to mint affiliate
links.

`bcat95/shopee-aff` confirms the only *actual* product-catalog/search APIs in this space are run by
**Shopee itself** (official Open API, GraphQL, separate affiliate-program approval) or an unofficial
scraping service (`data.addlivetag.com`) — neither is ACCESSTRADE, and using either would mean a
second provider, which `docs/PROJECT_SPEC.md` and `affihub/CLAUDE.md` explicitly lock out ("Scope is
locked to ONE affiliate provider (ACCESSTRADE)").

**This means `proposal.md`'s "Implement import Product thật từ ACCESSTRADE API" (an automatic
catalog pull) does not correspond to any real ACCESSTRADE endpoint.** Continuing to code against an
invented `GET /products` style ACCESSTRADE endpoint would be fabricating an API that doesn't exist —
exactly what `docs/PROJECT_SPEC.md`'s reference-first rule is meant to prevent.

### Scope decision — CSV upload (selected to follow the primary reference)

Three real options, each with a different shape for `AffiliateProducts::ImportOperation` and the
Product Library UI:

1. **Manual product-URL input, ACCESSTRADE only for link conversion.** User pastes/enters a list of
   Shopee product URLs (+ whatever catalog facts they have, or none) into the app; the system calls
   the real `product_link/create` endpoint to get `affiliate_url`, and catalog fields
   (title/price/rating/...) stay nullable unless manually entered. This is the option that keeps
   ACCESSTRADE as the ONLY external provider, matching the locked scope, but changes "Import Product"
   from an automated catalog pull into "convert a URL I already have into a trackable Product."
2. **CSV upload, ACCESSTRADE only for link conversion.** Same as (1) but the user uploads a Dataminer
   (or similarly-shaped) CSV of scraped Shopee products for the catalog facts, matching the reference
   pipeline's actual shape more closely; ACCESSTRADE still only mints links at the end.
3. **Add a second real data source** (Shopee's official Open API, or the unofficial
   `data.addlivetag.com`) for catalog facts, keep ACCESSTRADE for link conversion. This contradicts
   the "ONE affiliate provider" lock and needs that constraint explicitly relaxed by the user first.

The plan selects option 2 because it follows the primary reference pipeline and preserves the
one-affiliate-provider scope. Change 03 SHALL implement the CSV-upload flow; it SHALL NOT build a
catalog browser or a product-search API that the reference does not provide.

## What IS confirmed and portable regardless of which option is chosen
- `AffiliateConnection` stores one ACCESSTRADE API token, server-to-server, no OAuth. The existing
  encrypted `api_key` field can hold the token; UI label is "API token". The API request uses
  `Authorization: Token <token>`.
- The real `product_link/create` request/response shape above is exactly right for whatever
  `AccesstradeClient#create_affiliate_links`-type method calls it — reference uses batches of up to
  20 URLs per call. This is batching, not pagination.
- Scoring: `tunguyendg/aff-pipeline`'s real formula (`scorer.py`) is a weighted **sum**, not a
  normalized-to-[0,1] weighted average in the earlier draft: `score = sold*1.0 + rating*100 +
  is_mall*200 + discount*1`, rounded to two decimals by the reference. The design and tasks now use
  this actual formula.

### Official ACCESSTRADE product-detail endpoint
The official API docs also describe `GET https://api.accesstrade.vn/v1/product_detail`, which
requires a known `merchant` and `product_id` and returns details for that one product. It is not a
catalog search/discovery endpoint and is not needed by the reference CSV-to-link flow, so this POC
does not call it. See https://developers.accesstrade.vn/api-accesstrade-tai-lieu-tich-hop/get-detailed-information-of-the-product.

### Rails implementation constraints
All endpoint URLs, paths, batch size, timeout, retry count, backoff, campaign ID, and other provider
constants SHALL live in `config/accesstrade.yml` and be loaded with `Rails.application.config_for`.
`AccesstradeClient` SHALL use one shared private HTTP request method for all calls. Do not port
hard-coded literals or duplicated HTTP transport code from the Python reference.

Reference values to configure: batch size 20 (actual code constant and README; an inline docstring
incorrectly says default 50), timeout 30 seconds, retry count 3, exponential retry wait `2 ** attempt`,
and 1 second between batches. Preserve API-token auth and do not log credentials.

## License
No LICENSE file in `tunguyendg/aff-pipeline` — behavior read and described here, no source copied.
`Duke0503/shopee-aff` is MIT. `bcat95/shopee-aff` is a documentation-only repo (no code license
concern).
