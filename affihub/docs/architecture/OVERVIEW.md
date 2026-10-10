# Architecture Overview

This file is a navigation index, not the source of product requirements. Product scope lives in
docs/PROJECT_SPEC.md; behavior contracts and implementation tasks live in the active OpenSpec
change at the workspace root.

## Current state

AffiHub retains the Rails 8.1.4/Ruby 3.3.10 scaffold, HMVC base classes, PostgreSQL, Solid Queue,
Tailwind/daisyUI, and RSpec. HMVC is configured for web controllers/forms/operations. The active
video workflow is implemented across product resources, Services, jobs, models, migrations, and
ERB screens. Remaining OpenSpec work is listed in
../../openspec/changes/affihub-mvp-video-workflow/tasks.md; unchecked runtime gates are not evidence
of provider approval or live behavior.

The local video domain has `VideoProject`, `SourceAsset`, and `RenderVersion` models with source/project
references and Active Storage file attachments. Status maps and model defaults live in
`config/video_workflow.yml` and are loaded with `Rails.application.config_for(:video_workflow)`.
The clean initial domain schema is in `db/migrate/20261006090158_create_video_workflow_domain.rb`;
Active Storage tables are created by
`db/migrate/20261006090157_create_active_storage_tables.active_storage.rb`. Product RSpec coverage
starts in `spec/models/`. `config/routes.rb` declares the dashboard root, product resource routes,
and Rails' health check at `/up`. The test database is migrated through the current schema. The
existing development database contains legacy POC tables and was left unchanged; these initial
migrations intentionally do not convert that legacy schema.

The active product contract remains
../../openspec/changes/affihub-mvp-video-workflow/. Project and local-source screens are implemented
through `VideoProjectsController` and `SourceAssetsController`, with resource-scoped Services and
ERB templates. Local MP4/MOV uploads enqueue `SourceAssets::InspectJob`; the source page displays
the saved processing state, verified media metadata, and an inline preview once inspection
succeeds. `RenderVersionsController` and its Services provide the source-scoped editor, queued
render creation, render history/detail, timecode frame comparison, and local MP4 download. The
editor uses installed daisyUI components for its form and status UI, with Stimulus only for adding
and removing timeline/overlay/delogo rows. `PreflightReports::CreateService` saves a read-only
audit snapshot for one immutable render and its selected destinations. It checks source/render
storage objects, edit configuration and saved render metadata, workflow leases/heartbeats, the
local worker registry, provider read APIs and media-transfer configuration, local YouTube quota
counters, saved AI estimates, and the MPT recovery gate; it does not start an upload, publish, or
request a new estimate. TikTok's
Creator Info result and editor overlays are reported separately. `PreflightReports::ShowService`
builds the timecoded source/render frame strip from the saved report at the configured interval and
keeps the report visible if frame extraction is unavailable. `PreflightReportsController#create`
creates reports under the selected project; `#show` scopes report access to that project and filters
the existing snapshot with the `destination_id` query parameter. The render detail page contains the
destination selection form, including project-only checks when no destination is selected. The
report page orders shared and destination checks from `config/video_workflow.yml`, displays status
labels from that config, links remediation only to existing source/render/social/Google routes, and
hands ready destinations to `Publications#new` for draft creation. It does not add a publish route or
start a post. Request and system specs cover persistence, nested project scope, filtering, and draft
handoff.
The paid AI branch remains gated because restart/reconcile verification has not been recorded in
`config/money_printer_turbo.yml`.
`Meta::Client` loads provider settings from
`config/meta.yml`, uses one private request method, and covers OAuth token exchange, Page listing,
Page video source probing, and Facebook Reels upload/status calls. Request specs stub the HTTP
boundary and cover secret redaction; live Meta permission and publish smoke tests remain unverified
because this local environment has no Meta app or Page test credentials. `SocialConnectionsController`
and `SocialDestinationsController` provide profile setup/detail and multi-Page selection with
permission checks, using existing daisyUI components. Request and system specs cover OAuth secret
handling, Page token redaction, and permission errors.

### Đăng video và lịch

`PublicationsController` and `SchedulesController` call resource-scoped Services; the queued
`Publications::PublishJob` resolves Facebook Page/Reels, Instagram Reels, TikTok Direct Post, and
YouTube resumable upload through separate publisher Services. Meta, TikTok, YouTube and Google
settings are read from their provider YAML through `Rails.application.config_for`. Durable workflow
leases, outbound attempts and provider checkpoints support status polling and reconciliation.
TikTok configuration currently records Content Posting API audit as false; its publisher permits
only `SELF_ONLY` and requires the creator account to be private. Local readiness and passing RSpec
do not prove Meta App Review, TikTok audit, YouTube quota compliance, or a successful provider-side
publication. See the publisher Porting Note and OpenSpec tasks 13.3, 13.6, and 13.8.

### Drive, Sheets, Telegram và comment

Google account setup and the Drive Picker live in `GoogleConnectionsController`; Drive export and
Sheets sync are independent resource flows backed by their own Services and Solid Queue jobs.
`Google::Client` reads `config/google.yml`, and the Picker uses the pinned
`@googleworkspace/drive-picker-element` package. The Picker browser smoke is recorded separately
from Drive upload and Sheets write runtime verification in
`docs/reference-analysis/google-drive-sheets.md`.

`Telegram::PollingService` runs the allowlisted bot commands and queues operational alerts through
the gem-backed client; its runtime settings are in `config/telegram.yml` and its token stays in
Rails credentials. Meta comment webhooks pass through `MetaCommentWebhooksController` and
`AutoResponder` Services, with `AutoReplyRule`, `AutoReplyEvent`, and `AutomationControl`
recording configuration and outcomes.

### AI generation và TTS fallback

`AiGeneration` và `AiGenerationScene` lưu lần tạo cùng narration/voice/quote/consent đã duyệt. Các
Service tại `app/services/ai_generations/` xử lý script, scene prompts, submit, polling và output
MPT; estimate được tổng hợp trong `AiGenerationEstimates::CreateService`. Submit lưu scene TTS trước
khi gọi MPT. `AiGenerations::PollJob` poll task đã lưu qua Solid Queue;
`AiGenerations::PollService` kiểm tra task/output, tải artifact qua MPT Client vào Active Storage rồi
tạo `SourceAsset` để inspection job mở nguồn trong editor. Adapter xác nhận artifact thuộc đúng task
và chuẩn hóa prefix `tasks/` của MPT trước khi gọi download endpoint.
`POST /internal/mpt/tts_fallback` đi qua `Internal::Mpt::TtsFallbacksController` và
`AiGenerations::TtsFallbackCallbackService`, xác minh callback rồi mới tạo outbound attempt và gọi
`AzureSpeech::Client`; `Vieneu::Client` xử lý endpoint VieNeu. Specs dùng WebMock đã pass, và hai patch
MPT đã được áp/biên dịch trên source pinned; Docker image build và startup smoke với Redis `/ping`
đều pass. Production Active Job dùng Solid Queue với database queue riêng; Puma chạy supervisor khi
`SOLID_QUEUE_IN_PUMA=true`, hoặc deployment có thể dùng worker riêng. Callback Rails/Azure thật,
VieNeu live smoke, assembly WAV và resume/reconcile tác vụ đang chạy sau restart MPT/Redis vẫn chưa
được xác minh; xem
`docs/reference-analysis/ai-video-mpt-vieneu.md` và OpenSpec task 4.4–4.7.

### AI provider account connections

`AiProviderConnectionsController` and `AiProviderCallbacksController` route account setup through
`AiProviderConnections::*Service` and `AiProviderCallbacks::ShowService`. `AiProviderConnection`
stores provider identity, encrypted OAuth credentials, selected model, and verification state;
provider settings and workflow statuses come from `config/ai_providers.yml` through
`Rails.application.config_for(:ai_providers)`. `Codex::Client` supports the separately observed
auth-only callback/token flow and leaves the connection `pending_verification`; it does not list
models or perform inference. `OpenAi::Client` implements the separate SIWC contract, while
`Gemini::Client` implements the Gemini API OAuth boundary. SIWC entitlement/inference and Gemini
runtime permission/quota remain gated until their provider-specific smoke checks are complete.
Account and model screens live in `app/views/ai_provider_connections/`; provider authentication
references and smoke evidence are recorded in `docs/reference-analysis/ai-account-login.md`.

## Product requirements and references

| Path | Purpose |
|---|---|
| docs/PROJECT_SPEC.md | Product scope, workflows, integrations, security requirements, and implementation phases |
| ../../openspec/changes/affihub-mvp-video-workflow/ | Active proposal, behavior specs, architecture decisions, and tasks |
| docs/reference-analysis/ | Source/API Porting Notes and the boundary between documented contracts, local tests, and live verification |
| ../CLAUDE.md | AffiHub stack and coding rules; update only after the source architecture is agreed |

## Retained Rails scaffold

| Path | Purpose |
|---|---|
| app/controllers/application_controller.rb, main_controller.rb, api_controller.rb, internal/mpt/tts_fallbacks_controller.rb | Rails controller base classes and authenticated internal MPT TTS callback |
| app/controllers/dashboard_controller.rb, video_projects_controller.rb, source_discoveries_controller.rb, source_assets_controller.rb, render_versions_controller.rb, preflight_reports_controller.rb, publications_controller.rb, schedules_controller.rb, social_connections_controller.rb, social_destinations_controller.rb, connection_callbacks_controller.rb, google_connections_controller.rb, drive_exports_controller.rb, sheet_syncs_controller.rb, auto_reply_rules_controller.rb, auto_reply_logs_controller.rb, meta_comment_webhooks_controller.rb, ai_generations_controller.rb, ai_provider_connections_controller.rb, ai_provider_callbacks_controller.rb | Dashboard, project/source/discovery/editor/render/preflight/publishing/scheduling/social/Google/automation/AI HTML resources and callbacks |
| app/controllers/concerns/ | Shared HTML/JSON response concerns |
| app/forms/main_form.rb, app/operations/main_operation.rb, app/serializers/ | Generated HMVC scaffold |
| app/models/ | Video projects, source/discovery assets, immutable renders, preflight, publications/schedules, Google sync, social connections, AI generation/provider accounts, auto-reply, and durable workflow records |
| app/jobs/ | Source inspection/download, rendering, AI polling, publishing/scheduling, Google sync, Telegram alerts, and auto-reply processing |
| app/services/video_projects/, app/services/source_discoveries/, app/services/source_assets/, app/services/render_versions/, app/services/preflight_reports/, app/services/publications/, app/services/schedules/, app/services/social_connections/, app/services/social_destinations/, app/services/google_connections/, app/services/drive_exports/, app/services/sheet_syncs/, app/services/telegram/, app/services/auto_responder/, app/services/auto_reply_rules/, app/services/auto_reply_logs/, app/services/ai_generations/, app/services/ai_generation_estimates/, app/services/ai_provider_connections/, app/services/ai_provider_callbacks/, app/services/workflow_runs/, app/services/outbound_attempts/, app/services/meta/ | Product orchestration, provider APIs, OAuth, media work, external sync, and durable workflow recovery |
| app/services/ai_provider_connections/access_token_service.rb | AI inference gate; rejects connections without provider-specific verification |
| app/clients/azure_speech/, app/clients/vieneu/, app/clients/codex/, app/clients/gemini/, docker/mpt/ | Speech and AI provider clients, plus pinned MoneyPrinterTurbo image patches |
| app/helpers/, app/views/video_projects/, app/views/source_discoveries/, app/views/source_assets/, app/views/render_versions/, app/views/preflight_reports/, app/views/publications/, app/views/schedules/, app/views/social_connections/, app/views/social_destinations/, app/views/google_connections/, app/views/drive_exports/, app/views/sheet_syncs/, app/views/auto_reply_rules/, app/views/auto_reply_logs/, app/views/ai_generations/, app/views/ai_provider_connections/ | Vietnamese presentation helpers and project, publishing, integration, automation, and AI screens |
| app/views/layouts/, app/views/pwa/ | Default Rails layouts and PWA templates |
| app/assets/, app/javascript/ | Tailwind/daisyUI and importmap scaffold |
| config/routes.rb, config/video_workflow.yml, config/meta.yml, config/tiktok.yml, config/youtube.yml, config/google.yml, config/telegram.yml, config/ai_providers.yml, config/azure_speech.yml, config/money_printer_turbo.yml, config/mpt_tts_callback.yml, config/vieneu.yml | Resource/OAuth/internal callback routes and product, provider, workflow, and machine-state configuration |
| config/application.rb, config/database.yml, config/queue.yml, config/recurring.yml, config/rails_hmvc.yml, db/queue_schema.rb, bin/jobs | Rails, PostgreSQL, Solid Queue, and HMVC configuration |
| spec/boot_spec.rb, spec/integration/, spec/models/, spec/requests/, spec/services/, spec/system/, spec/factories/, spec/rails_helper.rb, spec/spec_helper.rb, spec/support/ | RSpec domain, request, service, workflow integration, and stable user-interaction coverage |
| Gemfile, Gemfile.lock, package.json, package-lock.json | Rails, test, and Tailwind dependencies |

The active design maps routes to controller/actions and ERB templates in
`../../openspec/changes/affihub-mvp-video-workflow/design.md`. Use its resource/action and template
mapping when extending the product; do not add placeholder templates ahead of their screen tasks.
