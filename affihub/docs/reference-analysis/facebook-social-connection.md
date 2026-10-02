# Porting Note: Facebook Social Connection and Page destination

## References and license

- `gitroomhq/postiz-app`: current repository license is GNU AGPL v3 or later. Its broad social integration model is useful as a boundary reference only. No source code is copied. [Repository](https://github.com/gitroomhq/postiz-app)
- `thenavidm/facebook-mcp`: current `main` is an MIT-licensed Facebook Pages MCP server. It describes official Graph API usage, user token exchange, Page-token acquisition, and the need for a developer app. It does not define Rails OAuth callback or persistence contracts, so those remain application-owned. No source code is copied. [Repository](https://github.com/thenavidm/facebook-mcp)
- Meta's official docs: [Graph API](https://developers.facebook.com/docs/graph-api), [Facebook Login access tokens](https://developers.facebook.com/docs/facebook-login/guides/access-tokens/), and [Pages API](https://developers.facebook.com/docs/pages-api/). The docs host returned HTTP 429 during this review. The client version remains config-driven; verify it in the Meta app before a real demo.

## Findings applied

- `SocialConnection` is the account-level Facebook connection; `SocialDestination` is one Page under that account. Publishing must use the Page token attached to the destination.
- Standard OAuth uses an app-owned callback URL on the existing Rails server and a session-bound, one-time `state`. Codex's fixed localhost listener is not reused.
- Exchange the short-lived OAuth token for a long-lived user token before persisting. Fetch Page access tokens at sync time from the authenticated user token; do not cache tokens.
- Cache only discovered Page `id` and `name`, keyed by SocialConnection and expiring after ten minutes. Sync must verify the selected `page_id` against this recent list before requesting its token.
- Use the official Graph API transport only. Do not use browser automation, scrape pages, or reproduce Postiz code.

## Scope and risks

Only Facebook Pages are in scope. Discovery needs `pages_show_list`; publishing later needs `pages_manage_posts` and related read permission per Meta's current permission rules. The app's developer credentials and redirect URI must be configured outside source control. The local machine has no verified Facebook App credentials yet, so OAuth and live Page verification remain manual gates.

## Implementation mapping

- `MetaGraphClient`: one config-driven HTTP boundary for OAuth, discovery, Page token lookup, and later publishing.
- `SocialConnections::ConnectOperation`: short-token exchange followed by long-lived exchange; persist only the long-lived token.
- `SocialConnections::DiscoverPagesOperation`: call `/me/accounts`; cache only `{ page_id, name }` metadata.
- `SocialConnections::SyncDestinationOperation`: validate cached ownership, fetch a fresh Page token, and encrypt it through Active Record Encryption.
- Controllers handle OAuth state and delegate domain work to Operations. User-visible pages remain server-rendered Rails views.

## Verification status

Reference findings and license checks are recorded. The official Meta documentation rate-limited this review. Live OAuth, Page discovery, and Page-token verification require a developer app and Page owned by the operator; no credential or provider success is fabricated.
