# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo is a child repo under workspace root `~/Documents/pj-affihub/`. Read `../CLAUDE.md` first — it governs cross-repo rules (git push safety, DB safety, RSpec invocation, commit convention). This file covers affihub-specific stack/architecture only.

## What this repo is

POC "AI Affiliate & Facebook Automation Platform" — Ruby on Rails. Goal: one real end-to-end vertical slice (ACCESSTRADE product → Codex-generated content → human approval → real Facebook Page post), not a full clone of any reference platform.

**Read `docs/architecture/OVERVIEW.md` before writing or editing any code in this repo.** It is the
file/folder map and domain-model index (which model/controller/operation/client/publisher exists,
which OpenSpec change creates it) — orient there first, in under 5 minutes, before opening
individual OpenSpec changes. It is navigation only, not the source of truth: `docs/PROJECT_SPEC.md`
and the relevant `openspec/changes/0X-*/` artifacts win on any conflict — update the overview to
match them, never the other way around.

**Read `docs/PROJECT_SPEC.md` before any non-trivial change.** It contains the full scope, domain model, reference-repo map, and phase order. Key rules from it that override default instincts:

- **Reference-first development.** Before building a subsystem (social publishing, AI auth, affiliate pipeline, Facebook Page integration), find and read the mapped reference repo's actual source first — do not invent architecture from scratch. Reference map: social core = `gitroomhq/postiz-app`, Facebook Page detail = `thenavidm/facebook-mcp` + current Meta API docs, AI auth = `decolua/9router`, affiliate pipeline = `tunguyendg/aff-pipeline` (fallback `Duke0503/shopee-aff`, then `bcat95/shopee-aff`).
- Write a Porting Note to `docs/reference-analysis/<subsystem>.md` before implementing a subsystem covered by a reference repo.
- Scope is locked to ONE affiliate provider (ACCESSTRADE), ONE AI provider (Codex), ONE social provider/destination (Facebook Page). Do not add other providers, TikTok/Instagram/etc, or an AI agent layer — extension points only, no implementation.
- AI never invents product facts, prices, or affiliate URLs — those always come from the affiliate provider / app, AI only generates copy from given facts.
- No fake/mocked "done": a Publication is only `Published` after a real Meta Graph API success response is parsed and `provider_post_id`/`published_at` stored.
- Human review is mandatory between AI content generation and publishing — no auto-publish.

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
  a real scenario instead (e.g. to prove a refresh happens before a Codex call, make the stored
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

Credentials: `config/master.key` (not committed) decrypts `config/credentials.yml.enc` — use `bin/rails credentials:edit` to change secrets. External provider credentials (Codex, Facebook, ACCESSTRADE) must be encrypted at rest per the project spec — never logged or exposed to the frontend.

## HMVC layers (rails_hmvc)

This app uses [`rails_hmvc`](https://github.com/TOMOSIA-VIETNAM/rails_hmvc) (vendored at
`vendor/bundle/ruby/3.3.0/gems/rails_hmvc-0.1.2` — read the generator templates there directly
when in doubt, don't guess the convention) — initialized with `--type=api` (`config/rails_hmvc.yml`).
Controllers stay thin; business logic and I/O go through the generated layers:

| Layer | Responsibility | Lives in |
|---|---|---|
| Controller | HTTP only — receive request, return response | `app/controllers/` |
| Form | Validate/transform input params | `app/forms/` |
| Operation | Business logic | `app/operations/` |
| Serializer | Format JSON output | `app/serializers/` |
| Error | Standardized error handling | `lib/errors/`, `app/controllers/concerns/errorable.rb` |
| Decorator | View-only formatting/display logic (not HMVC-generated; see below) | `app/decorators/` |

There is no Query/Service layer — the gem does not define one. Filtering/scoping data lives in a
model scope or inside the relevant Operation, not in a new `app/queries/*`/`app/services/*`
directory. Do not introduce one of your own; it's not part of this project's HMVC contract.

### Operation convention — `call` + `step_*`, generated, not hand-rolled

Generate a new resource's full HMVC stack rather than hand-rolling a fat controller:

Prefer Rails-provided generators (`bin/rails generate` / `bin/rails g`) for files and components
Rails or the installed project generators support, including models, migrations, controllers,
Operations, and their layers. Inspect and adapt generated files to the project conventions; create
files manually only when no suitable generator exists.

```bash
rtk bin/rails g hmvc:controller v1/<resource> --type=api
rtk bin/rails g hmvc:operation <Namespace>::<Name> step_a step_b step_c
```

The Operation generator wires up a `#call` method that runs the `step_*` private methods you name,
in order, as stubs — you fill in the bodies. **Name each `step_*` after the concrete business
action it performs** (`step_validate_generate_params`, `step_load_product`,
`step_build_codex_prompt`, `step_create_content!`) — never a vague verb alone (`step_build`,
`step_process`, `step_handle`, `step_persist`). A reviewer should know what broke from the step
name alone, without opening the method body.

Every Operation inherits from `MainOperation`, which already provides:

- `self.call(*args)` — builds an instance and calls `#call` on it, returns the instance.
- `attr_reader :params, :current_user, :form, :errors`.
- `success?` / `error?` (based on `errors.empty?`).
- `errors` (delegates to `@form.errors` unless the Operation sets its own).

A controller action calls `operator = XxxOperation.call(params:)`, then renders based on
`operator.success?`/`operator.errors` — it never inspects or mutates a model directly.

Every Controller action calling an Operation MUST merge `current_user:` into the params hash
passed to it (`ApplicationController#current_user`, added in change `01-poc-foundation-domain-model`,
reads `User.find_by(id: session[:user_id])`, memoized):

```ruby
operator = SomeOperation.call(params: params.to_unsafe_h.merge(current_user:))
```

`MainOperation#initialize` already reads `params[:current_user]` into `attr_reader :current_user`
— every Operation from change `02` onward can rely on `current_user` being present without
re-deriving it from session.

### Controller: `Renderable`/`Errorable` are JSON-only — HTML controllers must know this

`app/controllers/concerns/renderable.rb` and `errorable.rb` (generated by `rails_hmvc`, already in
this repo) always call `render json: ...` — that is correct for `ApiController < MainController`
(JSON API, `request.format` forced to `:json`), but this vertical slice's user-facing screens
(login, dashboard, product library, content review, social connections, publications — everything
in the minimal UI) are server-rendered HTML pages, not a JSON API consumed by a frontend. For an
HTML controller (inherits `MainController` directly, **not** `ApiController`):

- Still call `operator = XxxOperation.call(params:)` — keep the controller thin, same as the API
  convention. Command/form actions use the shared response helper below. Read-only actions
  (`index`, `show`, `status`, dashboard) render the Operation's view data directly on success;
  they must not query or mutate models in the Controller.
- Turn command/form `operator.success?`/`operator.errors` into a response through the shared
  `OperationRenderable` concern (`app/controllers/concerns/operation_renderable.rb`, created in
  change `01-poc-foundation-domain-model`, included in `MainController` so every HTML controller
  has it) — **do not** hand-roll `if operator.success? ... else ... end` + `render`/`redirect_to`
  per command action; call `render_operation operator, success: <path or options>, notice: "...", failure:
  <optional explicit action>`. This keeps the success/failure shape (flash key, HTTP status on
  failure, default failure action per verb) identical across every command controller action instead of each one
  inventing its own. Signature:

  ```ruby
  # success: redirect_to success, flash[:notice] = notice
  # failure: flash.now[:alert] = alert || operator.errors.full_messages.to_sentence
  #          render (failure || default action for action_name — :new for create, :edit for update,
  #          action_name.to_sym otherwise), status: :unprocessable_entity
  render_operation(operator, success:, failure: nil, notice: nil, alert: nil)
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

```ruby
# Good — greppable/searchable (incl. GitHub code search), one declaration per file
class Sessions::AuthenticateOperation < MainOperation
end
```

Not the nested-block form:

```ruby
# Bad — harder to grep/search for "Sessions::AuthenticateOperation" as a literal string
module Sessions
  class AuthenticateOperation < MainOperation
  end
end
```

Reason: the compact form keeps the full namespaced class name as one literal string in the source,
which is what GitHub/grep/ripgrep search on — the nested form splits it across two lines and is
harder for humans and code search to find. Applies to all namespaced classes/modules in this repo
(Operations, Forms, Serializers, Decorators, etc.), not just Operations.

## Doc comments: YARD style on every Helper/Decorator/Controller/Service method

Every method defined in `app/helpers/*`, `app/decorators/*`, `app/controllers/*`, or any
service-like object (Operation, Form, etc.) gets a short YARD-style doc comment above its
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

Any PORO client wrapping a third-party API (`app/clients/*`, e.g. `CodexClient`,
`AccesstradeClient`):

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
repo's real files (`gh api repos/<owner>/<repo>/contents/<path>`, or `gh repo clone` if easier)
before writing the Porting Note or any code — not writing a Porting Note from general/remembered
knowledge of how a provider's API "usually" works. Verify concrete details (exact param names,
header names, constant values like a client_id or a version string, less-obvious params) against
the actual file content. If a later read of the real source turns up a value that was guessed
instead of verified, fix the guessed value and correct the Porting Note — don't leave a
plausible-sounding but unverified detail standing once the real one is known.

## Architecture notes

App is currently close to a stock `rails new` skeleton plus the HMVC scaffold above (no domain models yet). As the vertical slice gets built, expect the domain to follow `docs/PROJECT_SPEC.md`'s model: `User`, `AIConnection`, affiliate `Product`/connection, `SocialConnection` (Facebook), `SocialDestination` (a specific Facebook Page — distinct from the connection), `Content`, `Publication`. Each gets its own Form/Operation/Serializer per the HMVC convention above. Publishing flows through a `PublisherResolver` → provider-specific publisher (e.g. `MetaGraphPublisher`) → external API, always via a background job (Solid Queue), never synchronously in a request.

Follow the phase order in the spec (reference analysis → Rails foundation → Codex auth → affiliate pipeline → AI content → Facebook Page → publication → end-to-end verification) rather than building features out of order.
