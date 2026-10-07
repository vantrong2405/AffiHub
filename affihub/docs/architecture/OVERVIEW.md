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
because this local environment has no Meta app or Page test credentials. Connection/Page-selection
screens and the remaining external integrations are still in progress.

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
| app/controllers/application_controller.rb, main_controller.rb, api_controller.rb | Rails controller base classes |
| app/controllers/dashboard_controller.rb, video_projects_controller.rb, source_assets_controller.rb, render_versions_controller.rb, social_connections_controller.rb, connection_callbacks_controller.rb | Dashboard redirect and local project/source/editor/render/OAuth callback HTTP actions |
| app/controllers/concerns/ | Shared HTML/JSON response concerns |
| app/forms/main_form.rb, app/operations/main_operation.rb, app/serializers/ | Generated HMVC scaffold |
| app/models/application_record.rb, video_project.rb, source_asset.rb, render_version.rb | Active Record base and initial video domain |
| app/jobs/application_job.rb | Active Job base class |
| app/services/video_projects/, app/services/source_assets/, app/services/render_versions/, app/services/meta/, app/services/social_connections/, app/services/connection_callbacks/ | Project workflows, local import/source inspection, render editing, frame comparison/export, Meta API calls, and OAuth callback handling |
| app/helpers/workflow_status_helper.rb, app/views/video_projects/, app/views/source_assets/, app/views/render_versions/ | Vietnamese status labels and project/source/editor/render pages |
| app/views/layouts/, app/views/pwa/ | Default Rails layouts and PWA templates |
| app/assets/, app/javascript/ | Tailwind/daisyUI and importmap scaffold |
| config/routes.rb | Rails health check, dashboard root, and resource routes from the active change |
| config/application.rb, config/database.yml, config/rails_hmvc.yml | Rails, PostgreSQL, Solid Queue, and HMVC configuration |
| spec/boot_spec.rb, spec/models/, spec/requests/, spec/services/, spec/system/, spec/factories/, spec/rails_helper.rb, spec/spec_helper.rb, spec/support/ | RSpec domain, request, service, and stable editor-interaction coverage |
| Gemfile, Gemfile.lock, package.json, package-lock.json | Rails, test, and Tailwind dependencies |

The active design maps routes to controller/actions and ERB templates in
`../../openspec/changes/affihub-mvp-video-workflow/design.md`. Product controllers, Service
namespaces, models, and matching spec paths are created with their sequential implementation tasks;
do not add placeholder templates ahead of their screen tasks.
