# Architecture Overview

Navigation/index only — **not** the source of truth for behavior. If anything here conflicts with
an OpenSpec artifact (`../../../openspec/changes/0X-*/specs/**/spec.md` or `design.md`), the
OpenSpec artifact wins; fix this file to match, not the other way around. Purpose of this file:
let a developer get oriented on the full file/folder layout and domain model in 5 minutes before
touching any code, without having to open 7 OpenSpec changes first.

Read this **before** writing or editing any code in this repo (see root rule in `../../CLAUDE.md`).

## 1. Where things actually come from

| Source | What it's for |
|---|---|
| `docs/PROJECT_SPEC.md` | Full scope, domain model, reference-repo map, 34-step DoD |
| `../../CLAUDE.md` (this file's section "HMVC layers") | Code-level convention: Operation `call`/`step_*`, Controller JSON-vs-HTML split, no Query layer, ERB not Slim |
| `../../openspec/changes/0X-*/proposal.md` + `design.md` + `specs/**/spec.md` | Per-capability behavior contract + technical decisions — authoritative, this file only summarizes |
| `docs/reference-analysis/<subsystem>.md` | Porting Note per subsystem (written during `tasks.md` execution, before implementing that subsystem) — not written yet, one per capability below |

## 2. Build order (7 sequential OpenSpec changes)

Mỗi change N phân biệt 2 gate riêng (xem `proposal.md` của từng change, mục "Precondition"):
- **Code gate** (đủ để bắt đầu viết task code/test của change N+1): change N hoàn tất mọi task TRỪ nhóm "Verify thủ công" cuối cùng.
- **Archive gate** (coi change N "xong hẳn", archive nó): change N ở trạng thái `archived` VÀ "Verify thủ công" cuối đã xác nhận thành công.

Không bắt buộc archive N xong mới được code N+1 — chỉ cần qua code gate. Nhưng KHÔNG archive N+1 trước khi N đã archive (archive luôn phải tuần tự đúng thứ tự dưới đây).

```
01 foundation-domain-model        migrations + models + login (no new capability spec)
02 ai-connection-codex-auth       Codex OAuth/PKCE + Test Connection
03 affiliate-product-pipeline     ACCESSTRADE import + Product Library filter/score
04 ai-content-generation          Codex content generation + review lifecycle
05 facebook-social-connection     Facebook connect + Page discovery/sync
06 publication-workflow           Post Now/Schedule + Meta Graph publish + retry
07 dashboard-e2e-verification     status Dashboard + 34-step DoD verification (no new capability spec)
```

## 3. Domain model (all tables created in change `01`, as empty-skeleton models)

| Model | Owner (`belongs_to :user`?) | Key fields | Created in |
|---|---|---|---|
| `User` | — | `password_digest`, `email` | 01 |
| `AIConnection` | yes, unique per user | `access_token`/`refresh_token`/`id_token` (encrypted), `chatgpt_account_id`, `chatgpt_plan_type`, status | 01 (skeleton) → 02 (real OAuth) |
| `AffiliateProvider` / `AffiliateConnection` | `AffiliateConnection belongs_to :user` | provider credential (encrypted) | 01 (skeleton) → 03 (real import) |
| `Product` | — (shared affiliate data, not user-owned) | unique `(affiliate_provider, source_product_id)`; `original_product_url` ≠ `affiliate_url` both real from provider; `raw_source_data`, `last_synced_at` | 01 (skeleton) → 03 (real import/filter/score) |
| `SocialConnection` | yes, unique `(user_id, provider)` | Facebook user-level token (encrypted) | 01 (skeleton) → 05 (real OAuth) |
| `SocialDestination` | via `SocialConnection` | `belongs_to :social_connection`, unique `(social_connection_id, page_id)`, Page-level token (encrypted, separate from user token) | 01 (skeleton) → 05 (real discover/sync) |
| `Content` | via `Product` | `body` (single text column — hook+caption+CTA+hashtags combined, see change 04 design Decision 4), `generation_count`, enum status `generated/review/approved/rejected`, `affiliate_url` (app-attached, not AI) | 01 (skeleton) → 04 (real generate/review/edit/regenerate) |
| `Publication` | via `SocialDestination` → `SocialConnection` | `content_id`, `social_destination_id`, enum status `draft/scheduled/publishing/published/failed`, `scheduled_at`, `provider_post_id`, `published_url` (nullable — see change 06 design Decision 5), `published_at`, `error_code`/`error_message`, `attempt_count`, `provider_metadata` | 01 (skeleton) → 06 (real publish workflow) |

## 4. File/folder map (HMVC — see `../../CLAUDE.md` for the full convention)

```
app/
  models/            User, AiConnection, AffiliateProvider, AffiliateConnection, Product,
                      SocialConnection, SocialDestination, Content, Publication
  controllers/        SessionsController, AiConnectionsController, ProductsController,
                      ContentsController, SocialConnectionsController, FacebookPagesController,
                      PublicationsController, DashboardController
                      — all inherit MainController directly (HTML, ERB views), NOT ApiController
                      — every action responds via `render_operation` (see concerns/ below), never
                      a hand-rolled if/else on operator.success?
    concerns/          OperationRenderable (render_operation helper, created in change 01, included
                      in MainController) — the ONE place success/failure response shape is defined
  forms/              SessionForm, Contents::UpdateForm, Publications::CreateForm
  operations/          Sessions::AuthenticateOperation
                      AiConnections::{ConnectOperation,RefreshTokenOperation,TestConnectionOperation}
                      AffiliateProducts::ImportOperation
                      Contents::{BuildPrompt,GenerateOperation,RegenerateOperation,UpdateOperation}
                      SocialConnections::{ConnectOperation,DiscoverPagesOperation,SyncDestinationOperation}
                      Publications::CreateOperation
                      Dashboard::BuildStatusOperation
  clients/             (PORO HTTP wrappers — I/O + response parsing only, no business rule)
                      CodexClient, CodexCallbackListener, AccesstradeClient, MetaGraphClient
  publishers/          MetaGraphPublisher (publish + permalink_url fetch, returns a Result object)
                      PublisherResolver (provider+type -> Publisher class, PORO map — lives here,
                      NOT app/services/*; there is no Service layer in this project, see
                      ../../CLAUDE.md "HMVC layers")
  jobs/                PublishJob (Solid Queue, claims Scheduled->Publishing atomically before publishing)
  serializers/          AiConnectionSerializer (hides raw token)
  views/**/*.html.erb   ERB, not Slim — HTML controllers render directly, do not use
                      Renderable's render_resource/render_collection (those are JSON-only)
```

`app/clients/*` and `app/publishers/*` are not part of the `rails_hmvc` gem's generated layers —
they're this project's own addition for external-API I/O (Client) and provider-specific publish
logic (Publisher), kept outside Operation per change `02` design Decision 2 (Operation = business
rule, Client = I/O only, easier to test and swap independently).

## 5. External integrations (reference-first — see `docs/PROJECT_SPEC.md` reference map)

| Integration | Real endpoint | Nature | Risk |
|---|---|---|---|
| Codex (change 02) | OAuth: `auth.openai.com`; inference: `chatgpt.com/backend-api/codex/responses` | Reverse-engineered ChatGPT backend, not official OpenAI API — uses ChatGPT Plus/Pro/Team quota, not API billing | Accepted by user; endpoint can break/be blocked anytime, see change 02 proposal.md |
| ACCESSTRADE (change 03) | ACCESSTRADE API | Official affiliate API | Rate limits only |
| Facebook (change 05, 06) | Meta Graph API (official) | Official | App Review permission scope, see change 05 design Risks |

## 6. Known cross-cutting decisions (full rationale in each change's `design.md`)

- Credential encryption: Rails 8 built-in `ActiveRecord::Encryption` (`encrypts`), no external gem.
- All background publish goes through Solid Queue (`PublishJob`), never synchronous in a request.
- `Publication` status only ever becomes `Published` after a real parsed Meta Graph API success
  response — never because "the job finished without raising."
- State-changing actions that must not double-fire (Post Now, Retry, `PublishJob` claiming
  Scheduled→Publishing) use an atomic `update_all(status: ...)` with a `WHERE status = <source>`
  condition, checking the affected-row count — never a plain read-then-write.

## 7. Seed user (login credential for manual verify steps)

POC has no signup — `db/seeds.rb` creates exactly one `User` via `find_or_create_by!`. Use these
credentials for every "Verify thủ công" manual-login step across changes 01–07:

- development/test: `demo@affihub.local` / `password123` (fixed fallback, only used when
  `SEED_USER_EMAIL`/`SEED_USER_PASSWORD` are unset and `Rails.env` is not `production`).
- production: no fallback — `SEED_USER_EMAIL`/`SEED_USER_PASSWORD` must be set in the deploy
  environment or `db:seed` raises immediately instead of creating a default-password user.
