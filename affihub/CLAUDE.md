# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo is a child repo under workspace root `~/Documents/pj-affihub/`. Read `../CLAUDE.md` first — it governs cross-repo rules (git push safety, DB safety, RSpec invocation, commit convention). This file covers affihub-specific stack/architecture only.

## What this repo is

Local-first Vietnamese video application — Ruby on Rails. Goal: one real end-to-end vertical slice (import or AI-generate a video → edit/render → human approval → real Facebook Page Reel), with optional Google Drive/Sheets sync. `docs/PROJECT_SPEC.md` is the product scope.

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
- A pasted social URL is source metadata only. Do not use `yt-dlp`, Playwright, or a downloader fork to fetch platform media. Import a local file or a file the user obtained through the platform's owner download/export flow. Add a platform API connector only after its official API, access level, and media-file route are proven for the target account.
- Paid AI video generation requires an estimate for all scene requests and explicit user confirmation before submitting jobs. On ambiguous timeout, reconcile with the provider before retrying.
- No fake/mocked "done": a Publication is only `Published` after the Meta workflow reaches a confirmed final state and the Page/video ID, permalink, and publication time are stored.
- Human review is mandatory before publishing. One connected Facebook profile may manage multiple Pages; no multiple-profile automation or promise to avoid duplicate-content/account-linkage checks.
- Google synchronization is a background side flow. The Rails database remains authoritative; Drive/Sheets errors must not trigger a render or Facebook publish retry.

This workspace also uses **OpenSpec** for spec-driven change proposals, tracked at the workspace root (`../openspec/`, not inside this repo) — check `../openspec/changes/` and `../openspec/specs/` for active/archived change proposals before starting work that affects specced behavior. OpenSpec artifacts (proposal/design/specs/tasks) are configured to generate in **Vietnamese** (see `../openspec/config.yaml` → `context`/`rules`) — do not override that per-change.

## Language convention

- **Specs, proposals, design docs, tasks, commit/PR descriptions, chat/explanations to the user:** Vietnamese. Keep technical terms (class/model/method names, file paths, repo names, API field names) in English inside Vietnamese text.
- **Code: Ruby, RSpec, views, config, comments in code:** English, always.

## TDD — RSpec-first (mandatory)

Minitest has been removed; **RSpec** (`spec/`) is the only test framework. For every feature/bugfix implementation task:

1. Write the RSpec spec describing the desired behavior first. Run it — it must fail (red).
2. Write the minimum code to make it pass (green).
3. Refactor with the spec green.

Do not write feature implementation code before its spec exists. This applies both to ad-hoc work and to OpenSpec `tasks.md` items (each feature task must be split into a "write spec" step before the "write code" step — `../openspec/config.yaml` enforces this in artifact rules).

RSpec is the behavioral backbone of this app: keep domain, operation, client, controller, request,
and routing contracts covered at their appropriate layers. **Do not write RSpec for views/templates
or assert rendered HTML, copy, CSS classes, or DOM attributes in request specs.** Those presentation
details change frequently; verify visual, accessibility, and browser interaction behavior manually
or with browser tooling. Request specs should cover HTTP outcomes such as status, redirects, session
and flash changes, and persisted effects—not the view markup. Keep examples focused on observable
behavior, not the current implementation structure.

### RSpec assertion/double style

- Prefer `eq` (exact value match) over `include`/`match` wherever the exact expected value is
  knowable — don't under-specify an assertion with a loose matcher when a precise one is just as
  easy to write. Reserve `include`/`match` for genuinely open-ended content (free-text error
  messages, collections whose full contents aren't the point of the example).
- Don't stub or mock this app's own objects (models, Operations, Clients) with
  `allow(...).to receive(...)` / `expect(...).to receive(...)`. Exercise the real object through
  a real scenario instead (e.g. to prove a refresh happens before an AI provider call, make the stored
  token actually expired and assert the real new token appears in the outgoing request — don't
  mock `ensure_fresh_token!` to observe call order). The one allowed exception is stubbing HTTP at
  a true third-party API boundary (WebMock `stub_request`/`a_request` against an external host)
  — that's faking the network, not faking our own code.
- Prefer FactoryBot-built real records and real collaborator objects over doubles/instance
  doubles for anything defined in this app.
- Phrase `it` descriptions as the observable outcome in third person present tense — lead with
  `"returns ..."` when the example is about a method's return value (`"returns true for valid?
  with a user and required attributes"`, `"returns the decrypted access_token through the
  model"`), or another outcome verb (`"raises ..."`, `"creates ..."`, `"redirects to ..."`) when
  there's no meaningful return value to describe. Don't phrase examples as vague actions
  (`"works correctly"`, `"handles the case"`) or restate the method name without the outcome.

## Stack

- Ruby 3.3.10, Rails ~> 8.1.3
- PostgreSQL (databases: `affihub_development` / `affihub_test`; also separate `solid_queue`/`solid_cache`/`solid_cable` DBs)
- Hotwire (Turbo + Stimulus), Tailwind CSS, Propshaft asset pipeline, importmap (no JS bundler/npm)
- Solid Queue for background jobs, Solid Cache for caching, Solid Cable for Action Cable
- RSpec + FactoryBot + Capybara/Selenium for system tests (`spec/`)
- Deploy: Kamal (`config/deploy.yml`) + Docker

No `bcrypt`/`has_secure_password` added yet — add explicitly when auth is implemented.

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

RAILS_ENV=test rtk bundle exec rspec                              # full test suite (ask first, see below)
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
application behavior goes through explicit Service classes called by the controller:

| Layer | Responsibility | Lives in |
|---|---|---|
| Controller | HTTP only — receive request, return response | `app/controllers/` |
| Form | Validate/transform input params | `app/forms/` |
| Service | One named application action and its I/O | `app/services/` |
| Serializer | Format JSON output | `app/serializers/` |
| Error | Standardized error handling | `lib/errors/`, `app/controllers/concerns/errorable.rb` |
| Decorator | View-only formatting/display logic (not HMVC-generated; see below) | `app/decorators/` |

Local import, preview, and export are real AffiHub MVP features, not a separate demo mode. Do not add
a `Demo` namespace or `demo_*` code filenames; name code after the product resource or action, such
as `VideoProjectsController`, `VideoImportService`, and `RenderVersionExportService`.

### Service convention — clear action names, called by controllers

Keep controllers responsible for HTTP input and response only. Put domain work in a focused service
under `app/services/`; use a form under `app/forms/` for input validation when needed. Name the file
after its top-level class in snake case, for example `app/services/video_import_service.rb` defines
`VideoImportService`.

Services expose `#call` and receive only the values they need. A service that handles a command may
expose `success?` and `errors` so the controller can use the shared `ServiceRenderable` response
helper. Read services expose their loaded data to the controller for rendering. Do not put model
queries, file persistence, or business decisions in a controller action.

```bash
rtk bin/rails g controller VideoProjects index create show
```

For example, an HTML command controller calls a service and delegates its response shape to the
shared helper:

```ruby
service = VideoImportService.new(file: params[:file])
service.call
render_service(service, success: -> { video_project_path(service.video_project) }, failure: :index)
```

Pass `current_user:` explicitly only to services whose behavior is scoped to the signed-in user.
The generated `MainOperation` remains scaffold support for existing generated code; do not create
new product Operations in `app/operations/`.

### Controller: `Renderable`/`Errorable` are JSON-only — HTML controllers must know this

`app/controllers/concerns/renderable.rb` and `errorable.rb` (generated by `rails_hmvc`, already in
this repo) always call `render json: ...` — that is correct for `ApiController < MainController`
(JSON API, `request.format` forced to `:json`), but this vertical slice's user-facing screens
(login, dashboard, product library, content review, social connections, publications — everything
in the minimal UI) are server-rendered HTML pages, not a JSON API consumed by a frontend. For an
HTML controller (inherits `MainController` directly, **not** `ApiController`):

- Call a focused Service from the controller and keep model access inside that Service. Command/form
  actions use the shared response helper below. Read-only actions (`index`, `show`, `status`, dashboard)
  render the Service's view data directly on success;
  they must not query or mutate models in the Controller.
- Turn command/form `service.success?`/`service.errors` into a response through the shared
  `ServiceRenderable` concern (`app/controllers/concerns/service_renderable.rb`, created in
  change `01-poc-foundation-domain-model`, included in `MainController` so every HTML controller
  has it) — **do not** hand-roll `if service.success? ... else ... end` + `render`/`redirect_to`
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
- An unexpected exception in an HTML action still falls through to `Errorable`'s
  `rescue_from` handlers, which currently all `render json:` — accepted as-is for this POC stage
  (an unhandled 500 shows a JSON body instead of a styled HTML error page). Do not build a second,
  format-aware error-handling path for this on your own initiative; it's a deliberate scope call,
  not an oversight — raise it with the user first if it needs to change.

### Views are ERB, not Slim

`Gemfile.lock` has no `slim` gem. Views are `.html.erb` (Rails default, paired with Hotwire/Turbo +
Tailwind per the Stack section below) — never introduce `.html.slim` without first adding and
agreeing on the gem.

### UI work goes through the `ui-ux` skill (evondevkit)

Before implementing any view/partial/component — wireframe, layout, color tokens — invoke the
`ui-ux` skill first and build from what it produces. Do not freehand CSS/layout decisions outside
it. This applies to every screen in the minimal UI (login, dashboard, product library, content
review, social connections, publications). Enforced in `../openspec/config.yaml` rules for the
`tasks`/`apply` artifacts too — don't bypass it when writing OpenSpec tasks either.

### UI components: daisyUI

- Use daisyUI 5.7.47 with the app's Tailwind CSS 4 build for standard controls and containers.
  Install it as an npm dev dependency in `package.json` and load it with `@plugin "daisyui"` in
  `app/assets/tailwind/application.css`; commit the lockfile so the Tailwind build resolves the
  same plugin version on every machine.
- In ERB, use daisyUI classes such as `btn`, `card`, `file-input`, `alert`, and `badge` whenever a
  matching component exists. Tailwind utilities may handle page layout, spacing, and responsive
  behavior; do not recreate daisyUI component styling with custom CSS.
- Prefer browser-native form behavior and daisyUI components. Add Stimulus or other browser logic
  only for a user interaction that native HTML, Rails, Turbo, and daisyUI do not provide.
- daisyUI handles component appearance. Rails Services and models still own upload validation,
  persistence, preview, and local export behavior.
- Write Vietnamese labels as direct actions and state the supported file type, next step, and local
  storage/posting outcome. Do not label a shipped AffiHub MVP workflow as a demo.

## View logic: Decorator/Helper, not RSpec view specs

Don't write RSpec specs that test view/template logic (conditional rendering, formatting, display
strings) directly. Move that logic out of the `.html.erb` into a Decorator (Draper) or plain
`app/helpers/*` method first, then unit-test the Decorator/Helper with RSpec — plain Ruby object,
no view context needed. A template should call `product.decorate.price_label` or
`helpers.price_label(product)`, not inline conditionals/formatting. This keeps view logic testable
without `render_views`/Capybara and keeps templates thin.

## Serialization: use a gem, don't hand-roll JSON shaping

For the `Serializer` HMVC layer (`app/serializers/`), use `active_model_serializers` — already a
transitive dependency of `rails_hmvc` (`MainSerializer < ActiveModel::Serializer` is the generated
base class, see `app/serializers/main_serializer.rb`) — rather than hand-building hashes/`to_json`
per serializer. Don't add a second serializer gem (e.g. `alba`); one library per layer.

## Class/module naming: compact `Namespace::Class`, not nested `module`/`class` blocks

Always define namespaced classes with the compact form:

Use a top-level class name that states the resource or action when a feature belongs to one area of
the app (`VideoImportService`, `VideoProjectsController`). Add a namespace only when multiple
subdomains need a real boundary; do not create a namespace just to label a flow "demo" or "MVP".

## Doc comments: YARD style on every Helper/Decorator/Controller/Service method

Every method defined in `app/helpers/*`, `app/decorators/*`, `app/controllers/*`, or any
service-like object (Service, Form, etc.) gets a short YARD-style doc comment above its
definition, so another dev can tell what it does without reading the body:

```ruby
# Formats a product's price for display, including currency symbol.
#
# @param product [Product] the product to format
# @return [String] formatted price, e.g. "$19.99"
def price_label(product)
  ...
end
```

Each YARD method comment MUST include `@return [Type]` describing the actual return value (use
`[void]` for methods whose result is intentionally unused). Include `@param` for each argument;
do not omit return documentation from newly added or edited public methods.

Same rule for JS (Stimulus controllers, importmap modules): a short JSDoc block above each
function/method.

```js
/**
 * Toggles the mobile nav open/closed state.
 * @param {Event} event - the click event that triggered the toggle
 */
toggle(event) {
  ...
}
```

Keep it to the method's purpose, params, and return value — not a line-by-line narration of the
body. Trivial one-liners (simple attribute delegation, `def foo = bar.foo`) don't need one.

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

## Architecture notes

The video domain follows `docs/PROJECT_SPEC.md`: video project, source asset, immutable render version, managed Facebook Page, per-Page publication, and Drive/Sheets sync state. Each layer follows the HMVC conventions above. File import, AI generation, FFmpeg work, Google sync, and Meta publishing run through background jobs (Solid Queue), not synchronously in a request.

Follow the phase order in `docs/PROJECT_SPEC.md`: read reference sources → prove Meta Page publishing and MPT provider behavior → local import/edit/render → AI worker → Meta publisher → optional Drive/Sheets sync → end-to-end verification. Do not implement from OpenSpec artifacts if their scope conflicts with `docs/PROJECT_SPEC.md`; active change `07-poc-dashboard-e2e-verification` is on hold. Create a separate implementation change after the owner reviews the video flow.
