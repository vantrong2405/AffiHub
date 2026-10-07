# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo is a child repo under workspace root `~/Documents/pj-affihub/`. Read `../CLAUDE.md` first — it governs cross-repo rules (git push safety, DB safety, RSpec invocation, commit convention). This file covers affihub-specific stack/architecture only.

## What this repo is

Local-first Vietnamese video application — Ruby on Rails. Goal: one real end-to-end vertical slice (source from import/link-download/crawl or AI-generate a video → edit/render → manual review or scheduled auto-publish → real post on Facebook/TikTok/Instagram/YouTube), with optional Google Drive/Sheets sync and optional keyword-based auto-reply. `docs/PROJECT_SPEC.md` is the product scope.

**Read `docs/architecture/OVERVIEW.md` before writing or editing any code in this repo.** It is the
file/folder map and domain-model index (which model/controller/operation/client/publisher exists,
which OpenSpec change creates it) — orient there first, in under 5 minutes, before opening
individual OpenSpec changes. It is navigation only, not the source of truth: `docs/PROJECT_SPEC.md`
and the relevant `openspec/changes/0X-*/` artifacts win on any conflict — update the overview to
match them, never the other way around.

**Read `docs/PROJECT_SPEC.md` before any non-trivial change.** It contains the current product scope, workflow, technical boundaries, reference repos, and implementation order. Key rules:

- **Reference-first development.** Before implementing a subsystem, read the pinned/reference source listed in `docs/PROJECT_SPEC.md` and its current official API documentation. Primary references are MoneyPrinterTurbo for AI video stages, FFmpeg for media transforms, Meta's Graph API for Page publishing, and Google's Drive/Sheets APIs.
- Write a Porting Note to `docs/reference-analysis/<subsystem>.md` before implementing a subsystem covered by a reference repo.
- Scope is defined by `docs/PROJECT_SPEC.md`; do not introduce product flows outside that spec.
- A pasted social URL triggers a best-effort `yt-dlp` download in its own background job (not inline in the request); on failure, fall back to manual import (a local file, or a file the user obtained through the platform's owner download/export flow). Never use Playwright or a scraping/browser-automation fork — `yt-dlp` only. No retry storm on rate-limit/block from the source platform; surface the failure instead. ToS/copyright risk for a pasted URL is the user's to carry — the UI must show that warning before the feature is used, not this code. Add a platform API connector only after its official API, access level, and media-file route are proven for the target account.
- Paid AI video generation requires an estimate for all scene requests and explicit user confirmation before submitting jobs. On ambiguous timeout, reconcile with the provider before retrying.
- No fake/mocked "done": a Publication is only `Published` after the destination platform's workflow reaches a confirmed final state and the post/video ID, permalink, and publication time are stored — this applies to every platform (Facebook, TikTok, Instagram, YouTube), not just Facebook.
- Manual review is the default before publishing; auto-publish (Scheduler-driven, no per-post human confirmation) is also in scope when explicitly enabled per project/schedule — both paths still require preflight to pass. Multiple profiles per platform and multi-platform publishing are in scope. No evasion mechanism for duplicate-content/account-linkage/spam detection — automation-related account/Page/channel bans are an accepted risk, not something to engineer around.
- Auto-reply to comments/DMs defaults to one fixed message per destination applied to every new comment (optionally overridden by static keyword-match rules) — never route this through an LLM/free-form generator.
- Google synchronization is a background side flow. The Rails database remains authoritative; Drive/Sheets errors must not trigger a render or publish retry on any platform.

This workspace also uses **OpenSpec** for spec-driven change proposals, tracked at the workspace root (`../openspec/`, not inside this repo) — check `../openspec/changes/` and `../openspec/specs/` for active/archived change proposals before starting work that affects specced behavior. OpenSpec artifacts (proposal/design/specs/tasks) are configured to generate in **Vietnamese** (see `../openspec/config.yaml` → `context`/`rules`) — do not override that per-change.

## Language convention

- **Specs, proposals, design docs, tasks, commit/PR descriptions, chat/explanations to the user:** Vietnamese. Keep technical terms (class/model/method names, file paths, repo names, API field names) in English inside Vietnamese text.
- **Code: Ruby, RSpec, views, config, comments in code:** English, always.

## Ruby readability conventions

- Use simple, consistent variable names; use the same name for the same domain object across related code.
- Prefer clear direct code over one-use abstractions that hide the behavior. Move repeated queries into a named model scope and shared behavior into the nearest common layer so a fix does not need to be repeated in many places.
- Do not use Ruby lambda syntax (`->` or `lambda`) in application code or specs. Define Rails scopes with `scope :name, proc { ... }`; use a named method or ordinary block for other behavior.

## TDD — RSpec-first (mandatory)

**RSpec** (`spec/`) is the test framework configured for this application. The `minitest` gem may
still appear as a transitive dependency; do not use it to add a second test suite. For every
behavior-changing feature or bug fix:

1. Write the RSpec spec describing the desired behavior first. Run it — it must fail (red).
2. Write the minimum code to make it pass (green).
3. Refactor with the spec green.

Do not write feature implementation code before its spec exists. This applies both to ad-hoc work and to OpenSpec `tasks.md` items (each feature task must be split into a "write spec" step before the "write code" step — `../openspec/config.yaml` enforces this in artifact rules).

Follow AffiHub's RSpec conventions, using the installed stack:

- For Rails-backed specs, require `rails_helper` and set the correct top-level `type:` on
  `RSpec.describe`. The helper also infers types from paths, but explicit metadata documents intent.
  Keep the boot check in `spec/boot_spec.rb` isolated: it loads `config/environment` directly so the
  example can verify boot without `rails_helper` loading the application first.
- Mirror source paths for class- or file-focused specs. Group request and system specs by the resource
  or user workflow they exercise, rather than forcing them to mirror one implementation file.
- Use FactoryBot (`create`, `build`, `build_stubbed`) for Active Record records. Avoid constructing
  records directly or using YAML fixtures for database state. File fixtures under
  `spec/fixtures/files` are appropriate for upload examples. Do not use `before(:all)` or
  `after(:all)`, and do not leave pending examples in shipped specs.
- Test public behavior through the service/controller entry point; do not test private methods or
  internal query construction. Cover each behavior branch in the code changed, and remove dead setup
  after refactors.

Do not write view specs or RSpec examples solely to assert template markup, copy, CSS classes, colors,
spacing, or layout. Request specs cover HTTP outcomes and persisted effects, not rendered markup.
Verify presentation-only changes in a browser. Use Capybara system specs for important, stable user
interactions that have behavior beyond visual styling.

### RSpec assertion/double style

- A spec file or `describe` may contain multiple examples, but each `it` represents exactly one case:
  one set of preconditions, one action, and one expected behavior/outcome. Put every independent
  input, branch, scenario, or outcome in its own `it`, even when cases share setup or action. Never
  combine independent cases in one `it` to reduce repetition.
- One case may need multiple expectations. Keep those expectations in that case's `it` when they
  jointly verify its result and directly related side effects. Do not create separate `it` examples
  just to assert individual fields or effects of the same case.
- Write an explicit `it` for each case. Do not generate examples with loops or case tables, and do not
  use `shared_examples` to hide distinct cases. Share setup in the nearest `context` with `let` and
  `before`; keep each case, action, and expected outcome visible in its own `it`.
- Keep each example focused and readable; there is no fixed line limit. Keep its setup, action, and
  expectations easy to follow, and extract setup only when that improves clarity.
- Use `describe "#method"`/`describe ".method"` for methods and readable `context "when ..."` blocks
  for scenarios. Write each example description as one clear statement of the expected behavior.
  Start with `returns`, `raises`, `redirects`, `enqueues`, or another accurate verb as appropriate;
  do not force every description to start with `returns`.
- Keep expected values close to the example that asserts them. Compare an exact deterministic result
  with `eq`; use containment or collection matchers when the contract is partial membership, and make
  ordering explicit when order matters. Do not use a partial matcher as a shortcut for an exact result.
- Prefer real application collaborators and FactoryBot records when testing integrated behavior.
  Stubbing an application service at a request/controller boundary is acceptable when the example is
  specifically testing how that boundary handles the service result; cover the service behavior in its
  own spec. Never replace persisted domain records with doubles. Stub third-party HTTP with WebMock and
  do not make real network requests from specs.
- Use `described_class` for the class under test. Keep names simple and consistent for the same domain
  object across related specs (`video_project`, `source_asset`, `render_version`). Use deterministic
  values; use FactoryBot sequences when uniqueness matters and Faker only when varied input helps the
  behavior being tested. Use the local RuboCop quote style and sibling specs as formatting references.
- Name variables after their domain objects; avoid vague names such as `record`, `item`, or `data` when
  a name like `video_project` or `ai_generation` is clearer. Keep setup local to an example unless the
  nearest group genuinely shares it; do not extract one-use helpers just to shorten a spec.
- Use Shoulda-Matchers for standard Rails association and validation contracts when they make the
  example clearer.
- Put shared setup in the nearest `context` using `let`/`before`. In application code, prefer a named
  model scope for a repeated query condition and the nearest common layer for repeated behavior, so a
  later fix is made once. Do not extract one-use helpers or abstractions that make a spec harder to
  understand; keep independent spec cases explicit even when their setup repeats.

### RSpec support gems

- Use FactoryBot to build or create records; avoid Rails fixtures and direct Active Record
  construction for test data.
- Faker is available for realistic or varied test input; prefer fixed values and FactoryBot sequences
  when deterministic values are part of the behavior.
- DatabaseCleaner owns database cleanup. Rails transactional fixtures stay disabled; examples use
  the `:transaction` strategy by default. Use `database_cleaner: :truncation` when code under test
  uses another database connection, such as concurrent workers. System specs default to truncation.
- SimpleCov starts at the top of `spec/spec_helper.rb`, before Rails loads. It reports line and branch
  coverage under `coverage/`; cover changed behavior branches, but do not add a project-wide minimum
  threshold unless CI policy is deliberately changed.
- Shoulda-Matchers is configured for RSpec and Rails in `spec/support/shoulda_matchers.rb`.

## Stack

- Ruby 3.3.10, Rails ~> 8.1.3
- PostgreSQL (databases: `affihub_development` / `affihub_test`; also separate `solid_queue`/`solid_cache`/`solid_cable` DBs)
- Hotwire (Turbo + Stimulus), Tailwind CSS, Propshaft asset pipeline, and importmap. There is no JavaScript
  bundler; npm is used only for Tailwind plugin packages such as daisyUI.
- Solid Queue for background jobs, Solid Cache for caching, Solid Cable for Action Cable
- RSpec + FactoryBot, Faker, DatabaseCleaner, Shoulda-Matchers, SimpleCov, and Capybara/Selenium
  (`spec/`)
- Deploy: Kamal (`config/deploy.yml`) + Docker

No `bcrypt`/`has_secure_password` added yet — add explicitly when auth is implemented.

## UI conventions

- Render product screens with ERB, Tailwind CSS 4, and daisyUI 5.7.47. The pinned npm package and
  `@plugin "daisyui"` declaration are both required for CSS compilation.
- Run `npm ci` from `affihub/` after changing `package.json` or `package-lock.json`. The production
  Docker build installs the locked npm packages before `assets:precompile` and removes
  `node_modules` from the runtime image afterward.
- Use daisyUI components such as `btn`, `card`, `badge`, `alert`, `input`, and `file-input` for
  repeated controls. Check the installed daisyUI component/classes before building a control. Customize
  an existing component with supported daisyUI options, Tailwind utilities, or daisyUI CSS variables;
  do not redefine an equivalent component or its base styles in project CSS. Add custom styling only
  for behavior or presentation that the library does not provide.
- Keep customer-facing copy and status labels in Vietnamese. Review presentation in a browser at
  desktop and mobile sizes; do not add view specs that assert markup or styling.

## Local gem install

Gems install into `vendor/bundle` (project-local, gitignored), not system gems:

```bash
rtk bundle install --path vendor/bundle
```

Install gems with `--path vendor/bundle` so dependencies stay inside this project and do not alter
the shared/system gem installation used by other projects. Always run `bundle`/`bin/rails`/`bin/rspec`
etc. from the repo root.

## Commands

**Always prefix shell commands with `rtk`** (token-optimized proxy, see `../CLAUDE.md` #6).

```bash
rtk bin/setup              # install deps, prepare DB, clear logs/tmp, then starts dev server
rtk bin/setup --skip-server # same, without starting the server
rtk bin/dev                 # start dev server + Tailwind watcher (via Procfile.dev / foreman)

rtk bin/rails db:create     # create affihub_development + affihub_test (local Postgres, see ../CLAUDE.md #4)
rtk bin/rails db:prepare    # create/migrate/seed DB as needed
rtk bin/rails db:reset      # drop+recreate from schema + seed

RAILS_ENV=test rtk bundle exec rspec                              # full suite only when user asks
RAILS_ENV=test rtk bundle exec rspec spec/models/foo_spec.rb       # single file
RAILS_ENV=test rtk bundle exec rspec spec/models/foo_spec.rb:LINE  # single example by line number

rtk bin/rubocop              # lint (Omakase Rails style, see .rubocop.yml)
rtk bin/brakeman              # static security analysis
rtk bin/bundler-audit          # gem vulnerability audit
rtk bin/ci                    # runs the project's full CI pipeline (config/ci.rb)
```

Credentials: `config/master.key` (not committed) decrypts `config/credentials.yml.enc` — use `bin/rails credentials:edit` to change secrets. External credentials (Meta, Google, LLM, MuAPI, optional TTS) must be encrypted at rest per the project spec — never logged or exposed to the frontend.

## Application layers and Service convention

This app uses [`rails_hmvc`](https://github.com/TOMOSIA-VIETNAM/rails_hmvc) (vendored at
`vendor/bundle/ruby/3.3.0/gems/rails_hmvc-0.1.2` — read the generator templates there directly
when in doubt, don't guess the convention) for its generated Rails scaffold. Controllers stay thin;
new product behavior goes through explicit Service classes called by the controller, as directed
for AffiHub. This file defines the conventions for new product actions. The gem's HMVC controller
generator emits Operation calls; that is scaffold behavior, not the convention for new product
actions here. AffiHub's installed stack and the controller-to-Service rule in this file govern any
stack-specific difference.

| Layer | Responsibility | Lives in |
|---|---|---|
| Controller | HTTP only — receive request, return response | `app/controllers/` |
| Form | Validate/normalize input and request parameters | `app/forms/` |
| Service | Orchestrate one named application action and its collaborators | `app/services/` |
| Model | Persist domain data, associations, and model-level invariants | `app/models/` |
| Serializer | Format JSON output | `app/serializers/` |
| Error | Standardized error handling | `lib/errors/`, `app/controllers/concerns/errorable.rb` |

Local import, preview, and export are real AffiHub MVP features, not a separate demo mode. Do not add
a `Demo` namespace or `demo_*` code filenames; name code after the product resource or action, such
as `VideoProjectsController`, `VideoProjects::ImportService`, and `RenderVersions::ExportService`.

### Service convention — clear action names, called by controllers

Keep controllers responsible for HTTP input, calling the relevant Service, and returning the
response. Put application workflow and orchestration in a focused service under `app/services/`;
use a Form under `app/forms/` to validate/normalize input, and keep persistence and domain invariants
with Models. Namespace Services by the resource they operate on and name them for one action; for
example, `app/services/video_projects/import_service.rb` defines `VideoProjects::ImportService`.

Services expose `#call` and receive only the values they need. A service that handles a command may
expose `success?` and `errors` so the controller can use the shared `ServiceRenderable` response
helper. Read services expose their loaded data to the controller for rendering. Do not put model
queries, file persistence, or business decisions in a controller action.

### HMVC service/controller implementation rules

- A controller action only reads or normalizes HTTP input, constructs and calls the relevant
  Service, assigns Service results for the view, and returns the HTTP response. It must not query or
  mutate models, loop over records, validate domain rules, or transform provider data.
- Every Service has one application action and a class/file name that states that action. Group
  related actions by resource namespace when that makes the path clear; for example,
  `SocialConnections::Facebook::Pages::IndexService` lives at
  `app/services/social_connections/facebook/pages/index_service.rb`.
- `#call` is an orchestration entry point only: it calls named private step methods in the required
  order and returns the Service result. Put conditions, validation, queries, persistence, response
  mapping, loops, and error handling in focused private methods, not inline in `#call`.
- Expose values needed by controllers or views through `attr_reader`. Services never render,
  redirect, or return an HTTP response. Do not make controllers call helper methods below `#call`.
- Add one matching RSpec file per Service by mirroring its source path, such as
  `app/services/video_projects/import_service.rb` →
  `spec/services/video_projects/import_service_spec.rb`.

```bash
rtk bin/rails g controller VideoProjects index create show
```

For example, an HTML command controller calls a service and delegates its response shape to the
shared helper:

```ruby
service = VideoProjects::ImportService.new(file: params[:file])
service.call
render_service(service, failure: :index) do
  video_project_path(service.video_project)
end
```

Pass `current_user:` explicitly only to services whose behavior is scoped to the signed-in user.
The generated `MainOperation` remains scaffold support for existing generated code. For new product
actions, use Services called from Controllers; do not generate an HMVC Operation unless the owner
changes this architecture decision.

### Keep JSON rendering on API controllers

`Renderable` and `Errorable` return JSON responses and belong on JSON API paths. User-facing product
screens are server-rendered HTML. HTML controllers inherit `MainController` directly, not
`ApiController`, and return HTML redirects/renders for both expected validation failures and
unexpected errors. If the shared error concern handles an HTML request as JSON, add or use a
format-appropriate HTML error path before relying on it for that route.

- Call a focused Service from the controller and keep model access inside that Service. Command/form
  actions use the shared response helper below. Read-only actions (`index`, `show`, `status`, dashboard)
  render the Service's view data directly on success;
  they must not query or mutate models in the Controller.
- Turn command/form `service.success?`/`service.errors` into a response through the shared
  `ServiceRenderable` concern (`app/controllers/concerns/service_renderable.rb`, included in
  `MainController`) — **do not** hand-roll `if service.success? ... else ... end` + `render`/`redirect_to`
  per command action; call `render_service service, success: <path or options>, notice: "...", failure:
  <optional explicit action>`. This keeps the success/failure shape (flash key, HTTP status on
  failure, default failure action per verb) identical across every command controller action instead of each one
  inventing its own. Signature:

  ```ruby
  # success: redirect_to success, flash[:notice] = notice
  # failure: flash.now[:alert] = alert || service.errors.full_messages.to_sentence
  #          render (failure || default action for action_name — :new for create, :edit for update,
  #          action_name.to_sym otherwise), status: :unprocessable_entity
  render_service(service, success:, failure: nil, notice: nil, alert: nil)
  ```

  Do **not** call `render_resource`/`render_collection` (`Renderable`'s helpers) from an HTML
  controller — they always set a JSON content-type and will misrender an HTML page.

### Views are ERB, not Slim

`Gemfile.lock` has no `slim` gem. Views are `.html.erb` (Rails default, paired with Hotwire/Turbo +
Tailwind per the Stack section below) — never introduce `.html.slim` without first adding and
agreeing on the gem.

### Design user-facing screens with the `ui-ux` skill

Before creating a new screen or materially changing a user flow or layout, invoke `ui-ux` and follow
the approved wireframe, hierarchy, and visual direction. Small fixes and reusable partials should
follow the established screen design without repeating the full design exercise. Record this scope
in OpenSpec tasks; do not invent a competing layout or token set.

### UI components: daisyUI

- Use the installed daisyUI package with the app's Tailwind CSS 4 build for standard controls and
  containers. Keep its version pinned in `package.json` and `package-lock.json`, and load it with
  `@plugin "daisyui"` in `app/assets/tailwind/application.css`. Follow the official installation
  instructions when changing the integration; update this rule only if the integration changes.
- In ERB, use daisyUI classes such as `btn`, `card`, `file-input`, `alert`, and `badge` whenever a
  matching component exists. Tailwind utilities may handle page layout, spacing, and responsive
  behavior; do not recreate daisyUI component styling with custom CSS.
- Prefer browser-native form behavior and daisyUI components. Add Stimulus or other browser logic
  only for a user interaction that native HTML, Rails, Turbo, and daisyUI do not provide.
- daisyUI handles component appearance. Forms validate and normalize upload input, Services
  orchestrate import/preview/export workflows, and Models own persisted state and domain invariants.
- Write Vietnamese labels as direct actions and state the supported file type, next step, and local
  storage/posting outcome. Do not label a shipped AffiHub MVP workflow as a demo.

## Presentation logic and view testing

Keep ordinary presentation decisions in ERB. Extract formatting or presentation behavior into a
Helper when it is reused or makes a template materially harder to understand. Do not call
`product.decorate` unless a Decorator implementation and its dependency have deliberately been
added. Do not write RSpec view specs for templates or examples solely to assert rendered copy,
markup, CSS classes, colors, spacing, or layout. Test Helper/Presenter public input/output contracts
when they contain reusable behavior, comparing deterministic output with the complete expected
value. Avoid parsing generated HTML unless structure itself is the behavior and direct output
comparison is insufficient. Use Capybara system specs for stable user interactions, and browser
evidence for presentation-only changes. Request specs cover HTTP outcomes and persisted effects,
not rendered markup.

## Serialization: use a gem, don't hand-roll JSON shaping

For the `Serializer` HMVC layer (`app/serializers/`), use `active_model_serializers` — already a
transitive dependency of `rails_hmvc` (`MainSerializer < ActiveModel::Serializer` is the generated
base class, see `app/serializers/main_serializer.rb`) — rather than hand-building hashes/`to_json`
per serializer. Don't add a second serializer gem (e.g. `alba`); one library per layer.

## Class names and file paths

Use `snake_case.rb` files and `PascalCase` classes, with a suffix that names the layer (`*Controller`,
`*Service`, `*Form`, `*Job`, `*Serializer`). Models use singular names. Keep namespace and file path
aligned; for example, `VideoProjects::ImportService` in
`app/services/video_projects/import_service.rb`. Declare namespaced classes with the compact form
`class VideoProjects::ImportService`, consistent with this project's naming rules.
Choose names from the product resource/action and domain vocabulary; do not create `Demo` or
`demo_*` names for production MVP features.

## Method documentation

Add a concise YARD comment to every new or edited public method in Controllers, Services, Forms,
and Helpers, except trivial accessors and one-line delegations. Include `@param` for non-trivial
arguments and `@return [Type]` for public methods. Rails controller actions do not need `@param` or
`@return` tags. Comment private methods only when their behavior or constraints are non-obvious;
do not add narration to every method.

```ruby
# Formats a product's price for display, including currency symbol.
#
# @param product [Product] the product to format
# @return [String] formatted price, e.g. "$19.99"
def price_label(product)
  ...
end
```

For JavaScript, document Stimulus actions and `connect`/`disconnect` callbacks with concise JSDoc.
Document internal helpers when their behavior is non-obvious. Include parameter and return tags
when they apply to the function's contract.

```js
/**
 * Toggles the mobile nav open/closed state.
 * @param {Event} event - the click event that triggered the toggle
 */
toggle(event) {
  ...
}
```

Keep comments focused on the method's purpose and any non-obvious contract, not a line-by-line
narration. Trivial accessors and one-line delegations do not need comments.

## External-provider clients: config in YAML, one shared HTTP call, no hardcoded literals

Any PORO client wrapping a third-party API (`app/clients/*`, e.g. `MetaGraphClient`,
`MoneyPrinterTurboClient`, or a Google API client):

- **Endpoints/ids/ports/versions live in `config/<provider>.yml`**, loaded via
  `Rails.application.config_for(:<provider>)` — never inline string/number literals for a URL,
  client_id, port, or version scattered across the class. One YAML file per provider, with
  `default:`/environment overrides for anything that legitimately differs per environment
  (e.g. `app_base_url`).
- **One shared private method for making the actual HTTP call** (e.g. `post_json`), reused by
  every public method on the client — don't duplicate `Net::HTTP.start { |http| http.request(...) }`
  per method. Public methods build the request-specific params/headers and delegate to it.
- Every constant the client needs gets a real `CONFIG.foo` lookup or a named `SOME_CONSTANT`,
  never a bare literal re-typed at each call site.

## Reference-first means actually fetching the source, not recalling it

`docs/PROJECT_SPEC.md`'s reference-first rule means literally reading the mapped reference
repo's real files (`rtk gh api repos/<owner>/<repo>/contents/<path>`, or `rtk gh repo clone` if easier)
before writing the Porting Note or any code — not writing a Porting Note from general/remembered
knowledge of how a provider's API "usually" works. Verify concrete details (exact param names,
header names, constant values like a client_id or a version string, less-obvious params) against
the actual file content. If a later read of the real source turns up a value that was guessed
instead of verified, fix the guessed value and correct the Porting Note — don't leave a
plausible-sounding but unverified detail standing once the real one is known.

## Video workflow statuses and clean migrations

- Put each product domain's status names and model defaults in its domain/provider YAML file and
  load them with `Rails.application.config_for`. Models must build enum maps from that config instead
  of duplicating state lists inline; migrations must not become a second source of state defaults.
- Store the video workflow's configured status maps/defaults in `config/video_workflow.yml` and
  load them with `Rails.application.config_for(:video_workflow)`. Models must not duplicate those
  status maps as inline enum literals. Keep only transitions explicitly required by the specs.
- Treat feature schema/code as a clean first implementation against the documented target schema;
  do not carry accidental POC or local-database state into application code as a compatibility
  requirement.
- Write initial product schema migrations as a clean new schema using the Rails migration DSL
  (`create_table`, references, indexes, constraints, and normal Rails migration methods).
  Do not add raw SQL, `table_exists?`/`column_exists?` guards, conditional table creation, or legacy
  schema conversion to an initial product migration. Do not use those guards to hide an out-of-sync
  local database. Keep one authoritative schema path in the checked-in migrations.
- Handle any required legacy data migration only in a separately specified task with a reviewed
  migration plan and behavior specs. Do not add speculative compatibility code or rescue branches
  for schema states that the product does not support.
- Keep status names and defaults in `config/video_workflow.yml`, loaded through
  `Rails.application.config_for(:video_workflow)`; avoid duplicating status maps/defaults in model
  code or hiding them in migration literals.
- Keep workflow reliability defaults such as lease duration in the same YAML config and read them
  through `Rails.application.config_for(:video_workflow)` instead of scattering operational
  defaults across Services.

## Architecture notes

The video domain follows `docs/PROJECT_SPEC.md`: video project, source asset, immutable render version, managed Facebook Page, per-Page publication, and Drive/Sheets sync state. Each layer follows the HMVC conventions above. File import, AI generation, FFmpeg work, Google sync, and Meta publishing run through background jobs (Solid Queue), not synchronously in a request.

Follow the phase order in `docs/PROJECT_SPEC.md`: read reference sources → prove Meta Page publishing and MPT provider behavior → local import/edit/render → AI worker → Meta publisher → optional Drive/Sheets sync → end-to-end verification. Do not implement from OpenSpec artifacts if their scope conflicts with `docs/PROJECT_SPEC.md`; active change `07-poc-dashboard-e2e-verification` is on hold. Create a separate implementation change after the owner reviews the video flow.
