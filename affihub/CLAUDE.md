# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo is a child repo under workspace root `~/Documents/pj-affihub/`. Read `../CLAUDE.md` first — it governs cross-repo rules (git push safety, DB safety, RSpec invocation, commit convention). This file covers affihub-specific stack/architecture only.

## What this repo is

POC "AI Affiliate & Facebook Automation Platform" — Ruby on Rails. Goal: one real end-to-end vertical slice (ACCESSTRADE product → Codex-generated content → human approval → real Facebook Page post), not a full clone of any reference platform.

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
rtk bundle config set --local path 'vendor/bundle'   # once per checkout (.bundle/ is gitignored)
rtk bundle install
```

Always run `bundle`/`bin/rails`/`bin/rspec` etc. from the repo root so bundler picks up the local `vendor/bundle` path.

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

This app uses [`rails_hmvc`](https://github.com/TOMOSIA-VIETNAM/rails_hmvc) — initialized with
`--type=api` (`config/rails_hmvc.yml`). Controllers stay thin; business logic and I/O go through
the generated layers:

| Layer | Responsibility | Lives in |
|---|---|---|
| Controller | HTTP only — receive request, return response | `app/controllers/` |
| Form | Validate/transform input params | `app/forms/` |
| Operation | Business logic | `app/operations/` |
| Serializer | Format JSON output | `app/serializers/` |
| Error | Standardized error handling | `lib/errors/`, `app/controllers/concerns/errorable.rb` |

Generate a new resource's full HMVC stack rather than hand-rolling a fat controller:

```bash
rtk bin/rails g hmvc:controller v1/<resource> --type=api
```

A controller action must not query/mutate the model directly or build the JSON response inline —
route validation through a Form, business logic through an Operation, and output through a
Serializer. This applies to every resource in the vertical slice (products, content, connections,
publications).

## Architecture notes

App is currently close to a stock `rails new` skeleton plus the HMVC scaffold above (no domain models yet). As the vertical slice gets built, expect the domain to follow `docs/PROJECT_SPEC.md`'s model: `User`, `AIConnection`, affiliate `Product`/connection, `SocialConnection` (Facebook), `SocialDestination` (a specific Facebook Page — distinct from the connection), `Content`, `Publication`. Each gets its own Form/Operation/Serializer per the HMVC convention above. Publishing flows through a `PublisherResolver` → provider-specific publisher (e.g. `MetaGraphPublisher`) → external API, always via a background job (Solid Queue), never synchronously in a request.

Follow the phase order in the spec (reference analysis → Rails foundation → Codex auth → affiliate pipeline → AI content → Facebook Page → publication → end-to-end verification) rather than building features out of order.
