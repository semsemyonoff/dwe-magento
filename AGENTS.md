# DWE — Magento

A **demonstration project** for [DWE](#dwe-is-an-external-tool) (Dev Workspace Engine): a containerized local dev environment for a **Magento 2** store, driven entirely by declarative YAML. By default it installs the Magento **community sample** on first deploy. `README.md` is the human-facing overview; this file is the working guide for agents editing the repo.

DWE augments the project's Docker Compose setup with configuration layering, lifecycle management, validation, and declarative tooling — it does **not** replace compose. Edit `docker-compose.yml` freely; DWE runs on top of it.

> This repo was migrated from a legacy Make-based "devbox" onto the DWE schema, mirroring the sibling `dwe-laravel` reference. It is intentionally a faithful port of the legacy magento devbox with two deliberate simplifications: the **search-engine choice was removed** (OpenSearch is the only engine — no Elasticsearch/Kibana), and the nginx backend routing + DB GUI were aligned with the DWE reference (single `$backend` map; **DbGate** instead of Adminer). Further actualization is a later stage.

## DWE is an external tool

`dwe` is installed on the host (e.g. Homebrew at `/opt/homebrew/bin/dwe`). This repo contains only the project configuration it consumes — **do not** try to modify CLI behavior from here; only edit the YAML configs, compose files, and templates.

### Using the CLI

The CLI ships its own authoritative, versioned docs. Read them through the binary, always with `--lang en`:

```bash
dwe docs llms-txt --lang en             # project-aware overview / index — start here
dwe docs list --lang en                 # list every topic
dwe docs search <term> --lang en        # search docs
dwe docs show <topic> --lang en         # read one topic, e.g. reference/config/services/fields
```

**Rule — agents read status/data output as JSON.** When running `dwe validate`, `dwe status`, `dwe services`, or any other data-emitting status command, always pass `--output json` (alias `-o json`): the JSON is stable and parseable, while the default table output is formatted for humans. **Exception — documentation:** the `dwe docs` commands (`show` / `list` / `search` / `llms-txt`) are not status commands — read them in their default form and never pass `-o json`. `docs show` / `docs llms-txt` emit markdown and treat `--output` as a *file path*.

**Read commands are safe to run:** `dwe status`, `dwe validate`, `dwe logs`, `dwe docs show/search/list/llms-txt`.

**Mutating commands change state — prepare the edit, then run deliberately (or ask the user):** `dwe deploy run`, `dwe run` / `stop` / `restart`, `dwe reset run`, `dwe services enable|disable`, `dwe docs generate`. **Never** call `docker compose` directly — DWE tracks state and holds locks.

After editing a `service.yml`, configs, or the service `deploy.yml` → `dwe deploy run`. After editing `docker-compose.yml` → `dwe run`. After toggling a service → `dwe services enable|disable <name> --apply`. After changing a `service.yml` icon/host → `dwe validate` to confirm.

## How this repo is configured

- **3-layer config merge**, strict order, later wins, maps merge recursively:
  `workspace.yml` (project identity only — `project.name`, `project.prefix`) → `workspace/defaults.yml` (versioned defaults: service toggles, runtime, search, admin, magento settings, exports, db) → `workspace/local.yml` (gitignored per-developer overrides; `local.example.yml` is the tracked template).
- **Services** are declared one-per-folder in `workspace/services/<name>/service.yml`, loaded separately and injected into the merged map. A `type:` discriminator (`app` / `tool` / `infra`) selects allowed fields. `required: true` services are always on (`magento`); optional ones toggle via `services.<name>.enabled`. Per-service `ports:` / `hosts:` deep-merge by entry name.
- **`.env` is a generated artifact** (`dwe render env --out .env`), never edited by hand. Every variable is declared explicitly in `defaults.yml` under `exports.env` (`name` + `from` dot-path + optional `format` / `when` / `default`). No magic name mapping.
- **Docker/Compose policy** lives in `workspace/docker.yml` (loaded separately, not part of the 3-layer merge). This project keeps it minimal — only the shared `composer_cache` volume; everything else uses DWE defaults (project name `dwe-magento`, etc.).
- **Declarative commands** live in `workspace/commands/` — one file per group, subdirectories nest groups. Command IDs derive from path + filename + key (`workspace/commands/services/magento/cache.yml` → `services.magento.cache.*`).
- **Service hub model:** on deploy, each service gets a hub under `services/<name>/` (gitignored): `src/` (the Magento code), `configs/` (the deployed `env.php`), `home/` (composer home, incl. `auth.json`), `runtime/`, plus generated `.devcontainer/` / `.vscode/` / `AGENTS.md`.

### Always-on infrastructure vs optional services

Unlike the laravel pilot, Magento needs a richer base stack. `docker-compose.yml` always starts:

- **nginx** — reverse proxy / web entry point. Registered as a `type: infra` service (`workspace/services/nginx`) owning the published `:80` (APP_PORT), so `dwe info` auto-detects it as the `port_via` proxy and renders each service's real hostname (`http://magento.localhost`, `http://dbgate.localhost`, …) instead of bare `localhost:<port>`. The `magento` app declares only its host (`magento.localhost`), no port — it's reachable only through nginx.
- **db** — MariaDB
- **valkey** — Redis-protocol cache (db 0 / 1) and sessions (db 2); wired in the pre-seeded `env.php`
- **opensearch** — the catalog search engine (single supported engine)
- **app-magento** — PHP-FPM running Magento (the `magento` service)

Optional, toggled via `services.<name>.enabled`:

| Service | Type | Overlay | Default |
|---------|------|---------|:------:|
| `magento-debug` | app | `compose/services/magento/debug.yml` | ✅ |
| `mailpit` | tool | `compose/tools/mailpit.yml` | ✅ |
| `dbgate` | tool | `compose/tools/dbgate.yml` | ❌ |
| `opensearch-dashboards` | tool | `compose/tools/opensearch-dashboards.yml` | ❌ |
| `elasticvue` | tool | `compose/tools/elasticvue.yml` | ❌ |
| `redis-insight` | tool | `compose/tools/redis-insight.yml` | ❌ |
| `varnish` | infra | `compose/services/varnish.yml` | ❌ |

### Pipeline files — what exists here

This project defines two pipeline files:
- **`workspace/services/magento/deploy.yml`** — the per-service deploy pipeline.
- **`workspace/lifecycle.yml`** — a `run:`-only lifecycle that mirrors the default (`docker up --wait`, show info) and adds a post-up `tools-init` phase. That phase runs `services.redis-insight.init` (when the tool is enabled) to accept the RedisInsight EULA and register the Magento cache/session Valkey DBs via its API — replacing the old one-shot init container. `dwe stop` still uses the built-in default.

It also defines **`workspace/setup.yml`** — the interactive deploy **wizard**. On a fresh checkout (no/empty `local.yml`), `dwe deploy` prompts for the required Marketplace credentials and the store locale/currency/timezone, then writes them into `local.yml` and proceeds. (`magento.marketplace.*`, `magento.locale.*`, `magento.currency.base`.)

It has no orchestrator `deploy.yml`, no `reset.yml`, no `info.yml` — so `dwe deploy run`, `dwe reset run`, and `dwe info` use DWE's built-in defaults. (`dwe validate` reports these as informational ⓘ, not errors.)

## Lifecycle

- `dwe deploy run` — full deploy: ensure hub dirs, generate `auth.json` (from `magento.marketplace.*`), install Magento via `composer create-project` (community sample edition), copy `env.php`, chown src, bring the stack up & wait healthy (db/valkey/opensearch/app), create database, `setup:install` (against OpenSearch), apply store config, disable 2FA, deploy sample data, `di:compile`, reindex, render IDE/AI configs (and optionally the IDE URN catalog when `magento.ide.urn` is set). Run on first setup or after changing a service's config/deploy.
- `dwe run` / `dwe stop` / `dwe restart` — bring the stack up / down / cycle it.
- `dwe docker up|down|logs|exec|ps` — raw Docker Compose passthroughs (state-tracked).
- `dwe reset run` — destructive cleanup.

The deploy pipeline is **re-runnable**: each step is gated on filesystem / install truth (`dir-empty src`, the `'install'` key in `env.php`, the `var/.dwe-sampledata` marker), so a mid-pipeline failure is resumed by re-running `dwe deploy run` rather than a full reset.

There is **no Make facade for lifecycle.** The `Makefile` exists for image work only — building/pushing the multi-arch base PHP 8.5 image (`make build-php-base-image`, published to `ghcr.io/semsemyonoff/dwe-magento-php`) or pulling it (`make pull-base-image`). The `app-magento` service image (`images/services/magento/Dockerfile`) builds FROM that base; `dwe deploy run` builds the service layer on first setup. Day-to-day work goes through `dwe`.

## Project layout

```
workspace.yml                            # project identity (name/prefix)
workspace/defaults.yml                   # versioned defaults: toggles, runtime, search, admin, magento, exports, db
workspace/local.yml                      # local overrides (gitignored)
workspace/local.example.yml              # tracked template for local overrides
workspace/docker.yml                     # docker/compose execution policy (shared composer_cache volume)
workspace/styles.yml                     # UI: ASCII header, Magento-orange palette, separator
workspace/services/<name>/service.yml    # per-service declaration (type, container, icon, ports, hosts, dirs, cli, configs)
workspace/services/magento/deploy.yml       # per-service deploy pipeline
workspace/lifecycle.yml                  # run pipeline: docker up --wait + post-up tools-init (redis-insight seeding)
workspace/setup.yml                      # interactive deploy wizard (Marketplace creds + locale) → writes local.yml
workspace/commands/                      # declarative commands (see "Commands" below)
workspace/scripts/db/*.sh                # scripts referenced by type:script commands (dump-create, dump-deploy)
workspace/scripts/redis-insight/init.sh  # RedisInsight API seeding (run in a throwaway curl container)
workspace/templates/{ai,git,ide}/        # render packs consumed by `dwe render`
docker-compose.yml                       # base compose: nginx, db, valkey, opensearch, app-magento (always on)
compose/services/magento/debug.yml          # app-magento-debug container (Xdebug)
compose/services/varnish.yml             # Varnish full-page cache (optional infra)
compose/tools/{dbgate,mailpit,opensearch-dashboards,elasticvue,redis-insight}.yml  # optional tool overlays
configs/services/magento/env.php            # pre-seeded Magento deployment config (copied into the hub on deploy)
configs/nginx/…                          # nginx server + backend-map templates
configs/opensearch/opensearch.yml        # OpenSearch node config
configs/varnish/default.vcl              # Varnish VCL
images/services/magento/                     # app-magento service image (entrypoint, php-fpm/xdebug/spx config)
images/services/magento/base/                # base PHP 8.5 image → ghcr.io/semsemyonoff/dwe-magento-php (Dockerfile + build.sh)
services/                                 # service hubs (gitignored, created by deploy)
backups/                                  # local DB / media dumps (gitignored except .gitkeep)
.dwe/                                     # DWE runtime artifacts (gitignored): logs, state, snapshots, locks
legacy/                                   # old repos (gitignored, reference only — do not modify)
```

### Compose naming convention

- `docker-compose.yml` at root — mandatory infrastructure (nginx, db, valkey, opensearch, app-magento), always started (`compose.base`).
- `compose/tools/<name>.yml` — optional tool services (dbgate, mailpit, opensearch-dashboards, elasticvue, redis-insight).
- `compose/services/<service>/<name>.yml` — optional service variants (the debug container).
- `compose/services/varnish.yml` — optional infra overlay.
- No `docker-compose.` prefix on overlay filenames.

DWE assembles the `-f` list deterministically: base first, then enabled **tool** → **infra** → **app** overlays (alphabetical within each group).

## Commands

| ID group | File | Commands |
|----------|------|----------|
| `app.*` | `commands/app.yml` | `auth-json` (generate Marketplace auth.json), `install` (composer create-project, sample edition) — both **private**, run from the deploy pipeline |
| `db.*` | `commands/db.yml` | `create`, `drop`, `cli`, `dump-create`, `dump-deploy` (+ private `up`/`wait`/`start`) |
| `valkey.*` | `commands/valkey.yml` | `flush`, `cli`, `monitor` |
| `services.redis-insight.*` | `commands/services/redis-insight.yml` | `init` (private; EULA + DB seeding, run from lifecycle) |
| `services.magento` | `commands/services/magento.yml` | `composer-install`, `bootstrap` (+ private `chown-src`) |
| `services.magento.db.*` | `.../magento/db.yml` | `create` (private) |
| `services.magento.setup.*` | `.../magento/setup.yml` | `install`, `upgrade`, `schema-upgrade`, `data-upgrade`, `di-compile`, `static-content-deploy`, `db-status` |
| `services.magento.cache.*` | `.../magento/cache.yml` | `flush`, `clean`, `status`, `enable`, `disable` |
| `services.magento.indexer.*` | `.../magento/indexer.yml` | `reindex`, `status`, `info`, `reset` |
| `services.magento.mode.*` | `.../magento/mode.yml` | `show`, `set` |
| `services.magento.module.*` | `.../magento/module.yml` | `enable`, `disable`, `status`, `2fa-disable`, `2fa-enable` |
| `services.magento.sample.*` | `.../magento/sample.yml` | `deploy`, `remove` |
| `services.magento.config.*` | `.../magento/config.yml` | `prepare`, `search`, `set`, `show` |
| `services.magento.dev.*` | `.../magento/dev.yml` | `urn-generate`, `console` (REPL), `template-hints`, `query-log`, `di-info` |
| `services.magento.maintenance.*` | `.../magento/maintenance.yml` | `enable`, `disable`, `status` |
| `services.magento.cron.*` | `.../magento/cron.yml` | `run`, `install`, `remove` |
| `services.magento.queue.*` | `.../magento/queue.yml` | `list`, `start` (message-queue consumers) |
| `services.magento.catalog.*` | `.../magento/catalog.yml` | `images-resize` |
| `services.magento.sys.*` | `.../magento/sys.yml` | `info`, `check` (via n98-magerun2) |
| `services.magento.admin.*` | `.../magento/admin.yml` | `user-create`, `unlock`, `list` |
| `services.magento.varnish.*` | `.../magento/varnish.yml` | `enable`, `disable` |
| `services.magento.log.*` | `.../magento/log.yml` | `list`, `tail`, `clean` |

Run a command with `dwe cmd <id>`; pass params with `--set key=value` (e.g. `dwe cmd services.magento.indexer.reindex --set index=catalogsearch_fulltext`). Each command declares a `type:` (`shell` / `dwe` / `script` / `service_exec` / `service_run` / `workflow` / `builtin`) — see `dwe docs show reference/config/commands/types --lang en`.

### The `magento` deploy pipeline (`workspace/services/magento/deploy.yml`)

Typed steps: each has a `type:` (`shell` / `dwe` / `command` / `builtin`) and `cmd:`, plus optional `when:` / `check:` / `continue_on_error`. `.env` generation is implicitly inserted before phase 1. Full schema: `dwe docs show reference/config/deploy/index --lang en`.

## Conventions

- Cross-platform: must work on macOS and Linux (including WSL).
- **Secrets:** Magento Marketplace (repo.magento.com) credentials are **not** committed. They live in `magento.marketplace.{username,password}` — blank in `defaults.yml`, set per-developer in the gitignored `workspace/local.yml`. On deploy the `app.auth-json` command renders them into `services/magento/home/.composer/auth.json` (also gitignored). `dwe deploy run` fails fast if they are unset. `.env` is generated and gitignored.
- `legacy/` is gitignored, reference-only — do not modify it.
- Before editing any YAML under `workspace/`, confirm the schema with `dwe docs show reference/config/<area> --lang en` rather than guessing field shapes.
