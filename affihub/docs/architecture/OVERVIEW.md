# Architecture Overview

This file is a navigation index, not the source of product requirements. Product scope lives in
docs/PROJECT_SPEC.md; behavior contracts and implementation tasks live in the active OpenSpec
change at the workspace root.

## Current state

AffiHub retains its Rails 8.1.4/Ruby 3.3.10 application scaffold, HMVC base classes, PostgreSQL
configuration, Solid Queue configuration, Tailwind/daisyUI setup, and RSpec support. HMVC is
configured for web controllers/forms/operations. The root dashboard route and resourceful product
routes follow the active design; controllers, Services, models, migrations, and screen templates
are added by their implementation tasks.

Product controllers, Services, UI templates, and external integrations are still being implemented.
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
and removing timeline/overlay/delogo rows. `Meta::Client` loads provider settings from
`config/meta.yml`, uses one private request method, and covers OAuth token exchange, Page listing,
Page video source probing, and Facebook Reels upload/status calls. Request specs stub the HTTP
boundary and cover secret redaction; live Meta permission and publish smoke tests remain unverified
because this local environment has no Meta app or Page test credentials. `SocialConnectionsController`
and `SocialDestinationsController` provide profile setup/detail and multi-Page selection with
permission checks, using existing daisyUI components. Request and system specs cover OAuth secret
handling, Page token redaction, and permission errors. The remaining external integrations are
still in progress.

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
| docs/reference-analysis/ | Source/API research notes; these are references, not runtime code |
| ../CLAUDE.md | AffiHub stack and coding rules; update only after the source architecture is agreed |

## Retained Rails scaffold

| Path | Purpose |
|---|---|
| app/controllers/application_controller.rb, main_controller.rb, api_controller.rb, internal/mpt/tts_fallbacks_controller.rb | Rails controller base classes and authenticated internal MPT TTS callback |
| app/controllers/dashboard_controller.rb, video_projects_controller.rb, source_assets_controller.rb, render_versions_controller.rb, social_connections_controller.rb, social_destinations_controller.rb, connection_callbacks_controller.rb, ai_provider_connections_controller.rb, ai_provider_callbacks_controller.rb | Dashboard redirect and local project/source/editor/render/social/AI provider account and OAuth callback HTTP actions |
| app/controllers/concerns/ | Shared HTML/JSON response concerns |
| app/forms/main_form.rb, app/operations/main_operation.rb, app/serializers/ | Generated HMVC scaffold |
| app/models/application_record.rb, video_project.rb, source_asset.rb, render_version.rb, ai_generation.rb, ai_generation_scene.rb, ai_provider_connection.rb, workflow_run.rb, outbound_attempt.rb, workflow_audit_event.rb | Active Record base, video/AI generation and provider account domain, and durable workflow attempts |
| app/jobs/application_job.rb, app/jobs/ai_generations/poll_job.rb | Active Job base and saved MPT generation polling |
| app/services/video_projects/, app/services/source_assets/, app/services/render_versions/, app/services/ai_generations/, app/services/ai_generation_estimates/, app/services/ai_provider_connections/, app/services/ai_provider_callbacks/, app/services/workflow_runs/, app/services/outbound_attempts/, app/services/meta/, app/services/social_connections/, app/services/connection_callbacks/ | Project workflows, local import/render, AI generation and account authentication, TTS callback, estimate validation, durable workflow recovery, Meta API calls, and OAuth callback handling |
| app/services/ai_provider_connections/access_token_service.rb | AI inference gate; rejects connections without provider-specific verification |
| app/clients/azure_speech/, app/clients/vieneu/, app/clients/codex/, app/clients/gemini/, docker/mpt/ | Speech and AI provider clients, plus pinned MoneyPrinterTurbo image patches |
| app/helpers/workflow_status_helper.rb, app/views/video_projects/, app/views/source_assets/, app/views/render_versions/, app/views/social_connections/, app/views/social_destinations/, app/views/ai_provider_connections/ | Vietnamese status labels and project/source/editor/render/social/AI account pages |
| app/views/layouts/, app/views/pwa/ | Default Rails layouts and PWA templates |
| app/assets/, app/javascript/ | Tailwind/daisyUI and importmap scaffold |
| config/routes.rb, config/ai_providers.yml, config/azure_speech.yml, config/money_printer_turbo.yml, config/mpt_tts_callback.yml, config/vieneu.yml | Product/OAuth/internal callback routes and AI account, AI generation, and speech provider configuration |
| config/application.rb, config/database.yml, config/queue.yml, config/recurring.yml, config/rails_hmvc.yml, db/queue_schema.rb, bin/jobs | Rails, PostgreSQL, Solid Queue, and HMVC configuration |
| spec/boot_spec.rb, spec/models/, spec/requests/, spec/services/, spec/system/, spec/factories/, spec/rails_helper.rb, spec/spec_helper.rb, spec/support/ | RSpec domain, request, service, and stable editor-interaction coverage |
| Gemfile, Gemfile.lock, package.json, package-lock.json | Rails, test, and Tailwind dependencies |

The active design maps routes to controller/actions and ERB templates in
`../../openspec/changes/affihub-mvp-video-workflow/design.md`. Product controllers, Service
namespaces, models, and matching spec paths are created with their sequential implementation tasks;
do not add placeholder templates ahead of their screen tasks.
