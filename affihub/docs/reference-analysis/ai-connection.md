# Porting Note: ai-connection (Codex OAuth/PKCE)

## Reference
`decolua/9router` (MIT license), provider definition `open-sse/providers/registry/codex.js`
([source](https://github.com/decolua/9router/blob/abc5ec2666d240d50cdee3f003fa9b64bd44d4d0/open-sse/providers/registry/codex.js)) — OAuth/PKCE config for `auth.openai.com`
reusing the public Codex CLI `client_id` (`app_EMoamEEZ73f0CkXaXp7hrann`), then calling
`chatgpt.com/backend-api/codex/responses` directly (unofficial ChatGPT backend endpoint, not
`api.openai.com`). Marked `deprecated: true` + `RISK_NOTICE` in the source repo — ToS risk,
accepted by the project owner for this POC (see `openspec/changes/02-poc-ai-connection-codex-auth/proposal.md`).

## Implementation (what 9router does)
- Authorize URL: `https://auth.openai.com/oauth/authorize` with `client_id`, `redirect_uri=http://localhost:1455/auth/callback`
  (fixed port, configured server-side for this client_id — cannot be changed), `scope=openid profile email offline_access`,
  `response_type=code`, `code_challenge_method=S256`, `code_challenge`, `state`.
- PKCE: `code_verifier` random, `code_challenge = base64url(sha256(code_verifier))`.
- Token exchange: POST `https://auth.openai.com/oauth/token` (`grant_type=authorization_code`, `code`, `code_verifier`,
  `redirect_uri`, `client_id`) → `access_token`/`refresh_token`/`id_token`/`expires_in`.
- Refresh: POST same endpoint, `grant_type=refresh_token`. 9router config: `refreshLeadMs: 600000` (10 min lead before
  expiry) — proactively refreshes before expiry, not reactive-on-401. Refresh token is **rotated**: the response's new
  `refresh_token` must overwrite the old one; reusing an already-rotated refresh_token revokes the whole ChatGPT session.
- `id_token` is a JWT; 9router decodes payload (no signature verification) to read `https://api.openai.com/auth`
  claims (`chatgpt_account_id`, `chatgpt_plan_type`) for display only — never used to authorize anything.
- Prompt call: POST `https://chatgpt.com/backend-api/codex/responses` with headers `originator: codex_cli_rs`,
  `User-Agent: codex_cli_rs/<version>`, `version: <version>`, `Authorization: Bearer <access_token>`, `chatgpt-account-id: <id>`.
  Headers imitate the real Codex CLI so the backend accepts the request as a CLI session instead of rejecting it.
  The 9router executor normalizes `input` into Responses API message objects, sets a model, forces `stream: true`
  and `store: false`, and asks for `Accept: text/event-stream`. Rails sends its test prompt as one `user` message
  with `input_text`, uses the shared model setting from `config/codex.yml` (`gpt-6-luna`), and accumulates
  `response.output_text.delta` SSE events. Luna is selected for focused, cost-efficient writing tasks; keep
  model selection in provider config so Test Connection and future content-generation calls share the same choice.
- Callback: 9router (Node) spins up a tiny local HTTP listener bound to `127.0.0.1:1455`, handles exactly one
  `/auth/callback` request, then shuts the listener down.

## Rails mapping
- `app/clients/codex_client.rb` — PORO: `build_authorize_url`, `exchange_token`, `refresh_token`, `send_prompt`.
  Isolates every unofficial-endpoint detail in one object (Risk mitigation from design.md).
- `app/clients/codex_callback_listener.rb` — Ruby port of the Node listener: WEBrick `HTTPServer` wrapping a
  TCPServer bound synchronously by the caller, handling exactly one `/auth/callback` request in a background `Thread`.
- `app/operations/ai_connections/connect_operation.rb` — binds the port synchronously, builds the authorize URL,
  spawns the listener thread, returns the URL for the controller to redirect to.
- `app/operations/ai_connections/refresh_token_operation.rb` — rotation + `access_token_expires_at` update.
- `app/models/ai_connection.rb#ensure_fresh_token!` — proactive refresh gate, 10-minute lead (ported constant).

## Not ported
- 9router's multi-provider registry/UI, its own usage-dashboard endpoint (`/backend-api/wham/usage`) — out of scope
  (one AI provider only, per `docs/PROJECT_SPEC.md`).
- Any persistence/queueing 9router does for its own multi-tenant server — this POC is single-user, synchronous.

## Data flow / state lifecycle
`disconnected` → (Connect clicked, OAuth consent, callback exchange succeeds) → `connected`. On refresh failure
(refresh_token already rotated/revoked) → back to `disconnected`, user must reconnect. See design.md Decision 1/3/3b
for the full callback and refresh state machine.

## Error handling
- Port 1455 already bound → `Errno::EADDRINUSE` raised synchronously in `ConnectOperation#call`, surfaced as a form
  error before any redirect happens (never silently fails after the user already left for `auth.openai.com`).
- State mismatch / exchange failure / double-callback / timeout → listener redirects to `callback_result` with an
  `outcome`/`reason` query param; no `AIConnection` is created.
- Refresh failure → `AIConnectionDisconnectedError`, propagated (not rescued) out of `ensure_fresh_token!` into the
  calling Operation, which converts it to a user-facing "Codex disconnected, reconnect" error.

## Security
No raw token (`access_token`/`refresh_token`/`id_token`) is ever logged or serialized. `encrypts` (Active Record
Encryption, configured in change 01) at rest for all three. `id_token` is decoded but never verified/trusted for
authorization — display only.

## License
`decolua/9607router` / `decolua/9router` is MIT-licensed; behavior (flow/headers/constants) was read and re-implemented
in Ruby, no source code copied verbatim.

## Implementation plan
1. Migration: add `id_token`, `chatgpt_account_id`, `chatgpt_plan_type` to `ai_connections`.
2. `CodexClient` (authorize URL → exchange → refresh → send_prompt), TDD per method.
3. `CodexCallbackListener`, TDD (success, state mismatch, exchange failure, double-callback, timeout).
4. `ConnectOperation` (synchronous bind + spawn).
5. `RefreshTokenOperation` + `AIConnection#ensure_fresh_token!`.
6. `TestConnectionOperation`.
7. Serializer (no token fields) + log filtering.
8. Controller/routes/view (via `ui-ux` skill) + manual OAuth verification.

## Verification
Full RSpec suite green (HTTP stubbed with WebMock at the Net::HTTP transport boundary — real `CodexClient` exercised,
only the socket faked) plus a manual end-to-end Connect/Test Connection click-through with a real ChatGPT login
(task 10.3/10.4 — cannot be automated).

## Source read for the Responses request/stream contract

- `open-sse/providers/registry/codex.js` (blob `abc5ec2666d240d50cdee3f003fa9b64bd44d4d0`): declares `id`, `category`, `transport`, `oauth`, `models`, and service capabilities. It imports the Codex review-model helper and is a provider definition, not an OAuth client interface.
- `open-sse/providers/registry/index.js`: statically imports provider definitions and exports the registry array; the Codex entry is included in that array.
- `open-sse/providers/index.js`: imports the registry array, normalizes each entry into shared `PROVIDERS`, `PROVIDER_MODELS`, `PROVIDER_OAUTH`, and `PROVIDER_MEDIA` maps, injecting canonical OAuth fields into transport config when needed.
- This shape supports a common configuration/transport pipeline, but does not define a reusable OAuth/refresh/prompt method contract. Rails therefore uses a small application-owned provider contract and a Codex adapter; it does not port the registry, map-building pipeline, or plugin framework.
- `open-sse/executors/codex.js`: normalizes input, adds model, forces stream and disables storage.
- `open-sse/executors/base.js`: sends JSON and uses `Accept: text/event-stream` for streams.
