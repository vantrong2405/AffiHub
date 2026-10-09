# CLAUDE.md

Workspace-level rules for `pj-affihub` — the root folder holding child projects
(currently `affihub`, the POC Rails monolith). **`.git` lives at the workspace root**, not inside
any child project — the whole workspace (root config + every child project) is one git repo/one
history. "Child repo" below means a child project directory, not a separate `.git`. These rules
apply across all of them; each child project's own `CLAUDE.md` still governs its own code style
and stack.

## 1. Config lives at the root only

- All workspace-level config/rule/skill/spec tooling lives here, at the root: `.claude/` (skills),
  `.agents/` (Codex skill mirror), `openspec/` (change proposals/specs), `CLAUDE.md`/`AGENTS.md`.
  OpenSpec changes target code in child repos (currently `affihub`) but the proposal/spec/tasks
  artifacts themselves are tracked at the root, not duplicated per child repo.
- Don't install tooling or write persistent rules/skills into a child repo's own directory for
  setup/workflow purposes — only for a code change the user actually asked for in that repo. A
  child repo's own `.github/` CI config, `.rubocop.yml`, etc. (things that must physically live
  next to that repo's code/CI) stay in the child repo.
- Unsure whether something counts as "child repo config" vs "workspace rule"? Ask first.
- `AGENTS.md` at the root is a symlink to `CLAUDE.md` (Codex/Claude compatibility).

## 2. Always load the child repo's own CLAUDE.md before coding in it

This root `CLAUDE.md` covers cross-repo rules only. **Before writing/editing code in a child repo
(e.g. `affihub/`), read that repo's own `CLAUDE.md` first** — it has the stack, architecture,
language convention, and TDD rules for that repo specifically. Root rules and child rules both
apply; child rules never override root safety rules (git push, DB safety) but do govern everything
repo-specific (test framework, commands, domain model, coding language). When a second child repo
is added, the same applies to it — load its own `CLAUDE.md`, don't assume `affihub`'s rules carry
over.

## 3. Git push safety

`git push --force` / `-f` / `--force-with-lease` is allowed when the user explicitly asks for it
in the moment — do not use it on your own initiative, and still name what it will overwrite before
running it. Use `develop` as the integration branch for day-to-day development: create it from
`main` when it does not exist, make feature commits there, and push development work to
`origin/develop`. **Never push commits directly to `main`/`master`.** Promote verified work from
`develop` to `main` through a pull request or an explicit merge/release step.

## 4. Commit messages

Don't append `[skip ci]` by default; add it only if the user asks for it in the moment.

### Required commits for major features

- A major feature (a complete capability or vertical slice, usually involving multiple layers/files)
  must be committed once its implementation is complete and its required self-checks pass. For
  `affihub`, run the relevant RSpec specs with the explicit `RAILS_ENV=test` command above and
  perform any required manual verification before committing. Do not leave a verified major
  feature sitting uncommitted while moving on to another feature.
- Implement larger work as stable feature slices. Commit each completed and verified slice before
  starting the next one, with one coherent behavior change per commit instead of accumulating files
  from several features.
- Commit coherent documentation/specification work in its own `docs:` commit before implementing
  the behavior it defines. For OpenSpec work, include the related proposal, design, specs, tasks, and
  reference notes in that documentation slice when they belong together.
- Before committing in a dirty worktree, inspect the exact staged paths and commit only files for
  the current slice. Keep unrelated staged and unstaged changes out of the commit.
- Report the passing verification and the commit hash to the user. If verification fails, fix the
  feature and rerun the relevant checks before committing.
- Small unrelated edits can still be grouped by judgment. Preserve the `[skip ci]` choice rule above
  for every commit in the task.

## 5. Database setup (affihub)

`affihub` uses three local Postgres databases, all local/disposable for this POC (not shared team DBs):

```bash
cd affihub
rtk bin/rails db:create    # creates affihub_development, affihub_development_queue, and affihub_test if missing
rtk bin/rails db:prepare   # create + migrate primary/queue databases + seed, idempotent
```

## 6. Running RSpec (affihub)

**Always run with `RAILS_ENV=test` explicit — never bare `rspec`/`bundle exec rspec`.** By default
run one spec file; for a user-requested, explicitly bounded scope, one command may list multiple
spec files. Never run spec files in parallel (they share the local test DB).

```bash
cd affihub
RAILS_ENV=test rtk bundle exec rspec spec/path/to/file_spec.rb
# bounded scope example:
RAILS_ENV=test rtk bundle exec rspec spec/path/a_spec.rb spec/path/b_spec.rb
```

Don't run the whole suite (no path) unless the user asks for it.

## 7. Token-efficient shell usage (rtk)

**Always run shell commands through `rtk <command>`** — it's the token-optimized proxy, put `rtk`
in front of the real command (`rtk git status`, `rtk bin/rails ...`, `rtk bundle exec rspec ...`).
The Claude Code hook rewrites plain commands to their `rtk` form automatically, but write it
explicitly when authoring commands by hand (scripts, docs, this file) rather than relying on the
hook. Meta commands (`rtk gain`, `rtk discover`, `rtk proxy <cmd>`) are always called directly —
they have no non-`rtk` form. See the global `~/.claude/RTK.md` for the full command reference.

## 8. Future child repos

When a new child repo is added under this root, give it its own `CLAUDE.md` for its own stack/code
style. Only promote a rule here if it's genuinely cross-repo (git safety, DB safety, commit
convention, shared skills/tooling) — don't duplicate a single repo's stack details into this file.
