# DWE × Magento — demonstration project

A reference project showing how to run a **Magento 2** store's local development
environment with **DWE** (Dev Workspace Engine). On first deploy it installs the
**Magento community sample** (sample data included), and everything around it —
services, ports, hosts, the generated `.env`, lifecycle, and a catalogue of
everyday `bin/magento` commands — is declared in YAML and orchestrated by DWE.

It is the Magento sibling of the `dwe-laravel` reference: a showcase, not a
production app.

## What is DWE?

DWE is a host-installed CLI (a Go core + a Docker Compose runtime) that **augments**
a project's `docker-compose.yml` rather than replacing it. On top of plain Compose it adds:

- **Layered configuration** — `workspace.yml` → `workspace/defaults.yml` → `workspace/local.yml`, merged deterministically.
- **A generated `.env`** — rendered from an explicit export spec; never hand-edited.
- **Lifecycle management** — `dwe deploy` / `run` / `stop` / `restart` / `reset`, with state tracking and locking (so you never call `docker compose` directly).
- **Validation** — `dwe validate` checks config, templates, commands, and the environment.
- **Declarative commands** — project-specific tasks (setup, indexer, cache, sample data, db dumps…) defined in YAML and runnable via `dwe cmd`.
- **Editor & agent config generation** — `.devcontainer`, `.vscode`, and `AGENTS.md`/`CLAUDE.md` rendered into each service hub.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) (Desktop or Engine) with Compose v2
- The `dwe` CLI on your `PATH` (run `dwe --version` to confirm)
- Magento Marketplace (repo.magento.com) access keys. They are **not** committed —
  set `vars.magento.marketplace.username` / `password` in `workspace/local.yml`
  (copy `workspace/local.example.yml`). Deploy generates `auth.json` from them.
- The hostnames below resolve to `127.0.0.1`. `*.localhost` resolves automatically
  on most systems; otherwise add them to `/etc/hosts`.

## Quick start

On a fresh checkout, run `dwe deploy` (no subcommand) — the **setup wizard** prompts
for your Marketplace credentials and the store locale, writes them to `workspace/local.yml`,
and proceeds. (Or skip the wizard: `cp workspace/local.example.yml workspace/local.yml`
and fill in `vars.magento.marketplace.{username,password}` by hand.)

```bash
dwe deploy         # interactive: setup wizard (creds + locale) → deploy
# …or, once local.yml is set:
dwe deploy run     # first-time setup: install Magento sample, db, search, setup:install, sample data, reindex
dwe run            # bring the stack up
dwe status         # see what's running
dwe info           # project dashboard (URLs, services)
```

Then open **http://magento.localhost** (admin at **http://magento.localhost/admin**, default `admin` / `admin123`).

The first deploy is slow — `composer create-project` and `sampledata:deploy`
pull a large amount from `repo.magento.com`.

```bash
dwe stop           # stop the stack
dwe restart        # stop + run
dwe reset run      # destructive cleanup (removes volumes & generated dirs)
```

## Services

| | Service | Type | URL | Enabled by default |
|---|---------|------|-----|:---:|
| 🛒 | `magento` — Magento store (nginx + PHP-FPM) | app | http://magento.localhost | ✅ (required) |
| 🐞 | `magento-debug` — Xdebug-enabled variant of `magento` | app | — | ✅ |
| 📬 | `mailpit` — SMTP capture for local email testing | tool | http://mail.localhost | ✅ |
| 💾 | `dbgate` — multi-database GUI | tool | http://dbgate.localhost | ❌ |
| 📊 | `opensearch-dashboards` — OpenSearch indices UI | tool | http://opensearch.localhost | ❌ |
| 🔎 | `elasticvue` — OpenSearch GUI | tool | http://elasticvue.localhost | ❌ |
| 🧰 | `redis-insight` — Redis-protocol GUI (Valkey cache/session pre-seeded) | tool | http://redis.localhost | ❌ |
| 🧱 | `varnish` — full-page cache in front of nginx | infra | (`:81` listener) | ❌ |

Plus always-on base infrastructure from `docker-compose.yml`: an **nginx** reverse proxy,
a **MariaDB** database, **Valkey** (Redis-protocol cache + sessions), and **OpenSearch** (catalog search).
Toggle optional services without touching defaults:

```bash
dwe services enable dbgate --apply
dwe services enable opensearch-dashboards --apply
dwe services enable varnish --apply
```

> **Search engine:** OpenSearch only. The legacy Elasticsearch/OpenSearch choice
> (and Kibana) was removed during the migration to DWE.

## Everyday commands

Run any command with `dwe cmd <id>`; pass parameters with `--set key=value`. A few highlights:

```bash
# Setup / build
dwe cmd services.magento.setup.upgrade
dwe cmd services.magento.setup.di-compile
dwe cmd services.magento.mode.set --set mode=production

# Cache & indexers
dwe cmd services.magento.cache.flush
dwe cmd services.magento.cache.status
dwe cmd services.magento.indexer.reindex
dwe cmd services.magento.indexer.reindex --set index=catalogsearch_fulltext

# Sample data
dwe cmd services.magento.sample.deploy
dwe cmd services.magento.sample.remove

# Admin / modules
dwe cmd services.magento.admin.user-create --set user=dev --set password=dev12345
dwe cmd services.magento.module.2fa-disable

# Store config / Varnish
dwe cmd services.magento.config.search          # re-point catalog search at OpenSearch
dwe cmd services.magento.varnish.enable         # after `dwe services enable varnish --apply`

# Dev tooling
dwe cmd services.magento.sys.info               # system overview (n98-magerun2)
dwe cmd services.magento.dev.console            # interactive PHP REPL with Magento bootstrapped
dwe cmd services.magento.dev.template-hints --set action=enable
dwe cmd services.magento.maintenance.enable     # maintenance mode on/off/status
dwe cmd services.magento.catalog.images-resize  # after sample data / imports
dwe cmd services.magento.admin.unlock           # unlock a locked-out admin

# Database & Valkey
dwe cmd db.cli
dwe cmd db.dump-create
dwe cmd db.dump-deploy
dwe cmd valkey.flush
```

Browse the full catalogue with `dwe cmd` (interactive) or `dwe cmd list`.

## Layout & docs

- **`AGENTS.md`** (and the `CLAUDE.md` symlink) — the working guide for this repo's structure.
- **`workspace/`** — all DWE configuration: `defaults.yml`, `services/<name>/service.yml`,
  `commands/`, `templates/`.
- **`dwe docs`** — the authoritative, versioned reference.

> This is a demonstration environment intended for local development only — not hardened for production.
