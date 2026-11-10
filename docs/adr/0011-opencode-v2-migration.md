# ADR-0011: Migrate to OpenCode v2

## Status

Accepted

## Context

OpenCode v2 is the current release (verified against `2.2.7`, 2026-11-10; see
https://opencode.ai/docs/migrate-v1/). v2 has three intentional breaking changes:

1. New plugin API (V1 plugin implementations do not run in V2).
2. Revised server API and clients.
3. Terminal client config moves from layered `tui.json(c)` to one global `cli.json`
   (auto-migrated; not relevant to this headless server).

Probed against the real `2.2.7` binary, this deployment is affected by (2) plus
several compatibility renames. Existing supported server config fields keep working
(V2 normalizes them with warnings), but the following were verified broken or
renamed and need explicit changes.

## Decision Drivers

- **Pinned, reproducible builds** — the image pins `OPENCODE_VERSION`; the pin must
  actually take effect.
- **Zero-touch Coolify redeploys** — existing deployments set
  `OPENCODE_SERVER_PASSWORD`; they should keep working while new deployments use
  the canonical name.
- **Headless auto-approve must not regress** — the entrypoint writes the permission
  config on every start; a v1-shaped config logs warnings on v2.
- **Healthcheck must signal correctly** — Coolify/compose restarts depend on it.

## Verified v2 Behavior (probed on `ghcr.io/anomalyco/opencode:2.2.7`)

| Check | Result |
|-------|--------|
| Install script | Moved to `https://opencode.ai/v2/install`; takes `--version X` (or `VERSION` env). A bare positional arg is ignored with an "Unknown option" warning, so the old `bash -s -- ${VERSION}` form would silently install latest instead of the pin |
| `GET /api/health` (authed) | `404` — endpoint removed in v2 |
| `GET /api/info` (authed) | `200` with `{"version":"2.2.7",...}` — suitable healthcheck target |
| `GET /api/*` (no/wrong credentials) | `401`, including wrong username — username is always `opencode`, `OPENCODE_SERVER_USERNAME` is no longer supported |
| `OPENCODE_SERVER_PASSWORD` (legacy) | Still honored — authenticated requests succeed |
| `opencode run` flags | `--server` / `--standalone` exist; `--attach` is gone |
| `opencode serve --hostname/--port` | Still valid |
| `opencode plugin` subcommands | `list/add/check/update/remove` — no `-g` flag (`mcp add` has `--global`; plugin installs are global by default) |
| Permission actions | `bash`→`shell`, `task`→`subagent`, `write`/`patch`→`edit`; `doom_loop` and `lsp` are not v2 Core actions; `todowrite` is `experimental.todo`; `external_directory` is allowed by default in v2 |

## Decision

1. **Pin**: `OPENCODE_VERSION` selects the base-image tag
   (`FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}`); pin `2.2.7`.
   Single version source: compose build arg `${OPENCODE_VERSION:-2.2.7}`,
   documented in `.env.example` (fixes the Dockerfile/compose pin drift).
   No install script is involved, so the fragile v1 positional-arg form
   (which would silently install latest instead of the pin) is gone entirely.
   The v2 install script's `--version` flag (probe table) is historical context
   for why the tag approach was preferred, not the adopted mechanism.
2. **Auth env**: canonical `OPENCODE_PASSWORD`; entrypoint adopts legacy
   `OPENCODE_SERVER_PASSWORD` as fallback and fails fast when neither is set.
   Drop `OPENCODE_SERVER_USERNAME` (unsupported; always `opencode`). Both the
   Dockerfile `HEALTHCHECK` and the compose healthcheck use the effective
   password.
3. **Healthcheck target**: `/api/info` expecting `200` (replaces `/api/health`).
4. **Permissions**: entrypoint writes the native v2 `permissions` array
   (allow-all for headless, incl. `external_directory` made explicit) plus
   `experimental: { todo: true }`, and deletes the legacy `permission` key.
5. **CLI examples**: `run --attach <url>` → `run --server <url>`; Desktop
   `opencode --hostname/--port` → `opencode --server <url>`.
6. **Base image**: extend the official `ghcr.io/anomalyco/opencode` image instead
   of maintaining a Debian+fnm base (adopted after challenge review — the
   musl/Alpine risks are verified by build + probe, not assumed).
   The server `CMD` uses the absolute image path `/usr/local/bin/opencode`
   (not bare `opencode`): an upgraded `opencode-home` volume may still contain
   a previous `~/.opencode/bin/opencode` that shadows `PATH` and cannot
   execute on the new base — deploying v2 onto a v1 volume failed exactly
   this way (reproduced locally), fixed by the absolute path plus a
   zero-loss host-side removal of the stale binary (see README).

## Base-Image Decision (revised: extend official image)

The official image `ghcr.io/anomalyco/opencode:2.2.7` was inspected: Alpine
3.24.4 minimal, only `opencode`/`opencode2` in `/usr/local/bin`, no
`node`/`npm`/`git`/`gh`/`ssh`/`bash`/`curl`, root user, `ENTRYPOINT opencode`,
no healthcheck.

The first draft of this ADR rejected `FROM ghcr.io/...` as too much
unverifiable change. On challenge, that was reversed: the toolchain gaps are
finite and locally verifiable (build + `serve`/auth/tool probes), while the
Debian base permanently duplicates upstream's binary layer plus an `install |
bash` pin mechanism already proven fragile (the v1 positional-arg form would
silently install latest instead of the pin).

- **Adopted**: `FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}` plus an
  Alpine toolchain layer (`apk`: bash, node/npm, git, gh, ssh, curl, procps),
  non-root `opencode` user, Corepack pnpm/yarn, and the existing npm-global
  dev tools. Version pin = image tag; no install script involved.
- **Accepted tradeoff**: Node now floats with Alpine (v24.22.1 at the time of
  probing — matching the previously pinned Node 24 lineage) instead of an
  fnm pin. Node here runs JS tooling (npm globals, MCP servers, entrypoint
  scripts), not the server binary. Verified working in the build probe; revisit
  if any tool requires a newer/pinned Node.
- **Revisit if**: upstream publishes a server image variant with the toolchain,
  or a tool needs glibc/fnm-pinned Node — the pin stays a single
  `OPENCODE_VERSION` and only the base line changes back.

## Consequences

### Positive

- Pinned v2 installs actually install the pinned version (the `--version` flag
  fix).
- Existing Coolify envs (`OPENCODE_SERVER_PASSWORD`) keep working; new setups
  use `OPENCODE_PASSWORD`.
- No config-migration warnings in server logs; headless auto-approve preserved.
- Healthcheck reflects v2 reality (`/api/info` → 200).

### Negative / Follow-ups

- Third-party wiring is verified compatible pre-deploy; remaining check is
  deploy smoke, not porting: `rtk` 1.2.0 ships a dual v1/v2 OpenCode plugin
  (confirmed in the built image); `opencode-wakatime` upstream supports v1+v2
  (dual entrypoints targeting `@opencode/plugin` 2.0.18); `codegraph` wires
  via MCP server config (version-agnostic); `tokscale` is a standalone CLI.
  On the deployed container, confirm with `opencode auth list`, a clean plugin
  load (no warnings in server logs), and a headless `run --server --auto`.
- `auth.json` injection (`opencode-go`/`opencode` keys) is unchanged; v2 imports
  legacy `auth.json` on fresh installs, but credential shape must be confirmed
  with `opencode auth list --format json` on the deployed v2 container.

## Related Decisions

- ADR-0007: Health Check Strategy (v2 amendment appended there)
- ADR-0009: Permission Approval Strategy (v2 amendment appended there)
- ADR-0010: Session Lifecycle and Background Tasks (v2 `--server` amendment)
- ADR-0008: Server Mode Strategy (`serve` CMD unchanged and still valid in v2)
