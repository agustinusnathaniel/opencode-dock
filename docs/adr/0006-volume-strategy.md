# ADR-0006: Container Volume Strategy

> **Current state (2026-11):** tool binaries live in the image (`/opt`,
> `/usr/local/bin`) and refresh on every rebuild — deleting `opencode-home`
> is no longer needed for tool updates. The wipe-to-refresh tradeoff
> discussed below is historical context; the nested-volume layout itself is
> unchanged. See the amendment at the bottom.

## Status

Accepted

## Context

The OpenCode container needs to persist data across restarts while keeping tool binaries
fresh from the image on rebuild. Early attempts tried selective volumes per data directory,
then a single home directory volume, before settling on the current approach.

## The Problem

Three competing concerns:

1. **Persistence** — user data (sessions, config, workspace projects, plugin caches,
   auth tokens, WakaTime data, Tokscale credentials) must survive container restarts.
2. **Fresh tools** — tool binaries (Node, Bun, OpenCode, CodeGraph, etc.) should come
   from the image on every rebuild, never shadowed by a volume.
3. **Maintainability** — adding a new volume every time a tool stores data somewhere
   new is not scalable.

## Exploration History

### Attempt 1: Selective volumes per data directory (5+ volumes)

Each data directory got its own named volume:

- `opencode-data` → `~/.local/share/opencode/`
- `opencode-config` → `~/.config/opencode/`
- `opencode-wakatime` → `~/.wakatime/`
- `opencode-agents` → `~/.agents/`
- `opencode-ssh` → `~/.ssh/`
- `opencode-cache` → `~/.cache/opencode/`
- `opencode-workspace` → `~/workspace/`

**Problems:**
- Every new tool or cache path required adding another volume entry
- Easy to miss a path (Tokscale credentials, WakaTime heartbeats,
  OpenCode plugin cache, npm global installs)
- docker-compose.yaml grew verbose for what should be a simple setup
- No guarantee of completeness — trial and error to find missed paths

### Attempt 2: Single home directory volume

A single `opencode-home` volume mounted at `/home/opencode`:

```yaml
volumes:
  - opencode-home:/home/opencode
```

**Problems:**
- Docker named volumes shadow the image content at the mount point.
  On rebuild with updated tools, the OLD binaries from the volume
  persisted, not the NEW ones from the image.
- The `docker-entrypoint.sh` at `/home/opencode/docker-entrypoint.sh`
  was also shadowed — code fixes in the entrypoint had no effect
  because the old version from the volume ran instead.

### Attempt 3: System paths for tools + home volume

> v2 note: with the official-image base (ADR-0011), Node.js lives in the image
> (`/usr` via apk) and the entrypoint stays at `/usr/local/bin/`. npm-global
> tools moved to `~/.npm-global` (inside the home volume, seeded from the
> image on first start) — managed tools, not pinned binaries, so volume
> persistence is acceptable there.

Moved tool installations outside the home directory so the home volume
couldn't shadow them:

- Entrypoint moved from `/home/opencode/docker-entrypoint.sh` to
  `/usr/local/bin/docker-entrypoint.sh`
- FNM (Node.js) moved from `~/.local/share/fnm/` to `/opt/fnm/`
- npm global installs (CodeGraph, Tokscale) installed to npm's system
  prefix under `/opt/fnm/`
- RTK installed to `~/.local/bin/` which was still in the home volume,
  but the binary is re-installed on every build

This solved the shadowing problem but still had the "keep adding
volumes" maintenance burden.

## Decision

Use **two volumes — a home volume and a nested workspace volume**.

```yaml
volumes:
  - opencode-home:/home/opencode
  - opencode-workspace:/home/opencode/workspace
```

### Why this works

- **Home volume** (`opencode-home`) covers everything: config, cache,
  local state, agent skills, auth tokens. Adding a new tool is free —
  it stores data somewhere under `~/.config/`, `~/.local/share/`,
  `~/.cache/`, or `~/.agents/`, all inside the volume.
- **Workspace volume** (`opencode-workspace`) sits at a subdirectory
  of home. Docker supports nested volumes — the inner (workspace)
  takes precedence. When you delete the outer (home) to refresh tools,
  the workspace survives.

### The trade-off

When refreshing tool versions (Node, OpenCode, etc.), you delete the
home volume. This also wipes:
- OpenCode sessions (ephemeral — regenerated)
- Plugin caches (re-downloaded by `opencode plugin ... -g`)
- Tokscale credentials (re-login with `tokscale login`)
- WakaTime data (regenerated)
- pnpm store (re-downloaded on next install)

These are one-time costs per version bump (a few times a year).
The maintenance savings from not managing 5+ volumes outweighs this.

## Key Technical Insights

### Docker named volumes shadow image content

When a named volume is mounted at a path, it replaces whatever was in
the image at that path. The image content is only copied into the
volume on **first creation** (when the volume is empty). Subsequent
rebuilds with updated images use the old volume content.

This means:
- Tools installed in `$HOME` get shadowed (bad)
- Tools installed in `/usr/local/`, `/opt/`, `/etc/` don't (good)
- Configuration files in `$HOME` that are recreated by the entrypoint
  from env vars (SSH keys, WakaTime config, auth.json) survive
  because the entrypoint writes them fresh every start

### Docker supports nested volumes

You can mount two volumes where one is a subdirectory of the other:

```yaml
volumes:
  - outer:/home/opencode
  - inner:/home/opencode/workspace
```

The inner volume takes precedence. Deleting `outer` leaves `inner`
intact. This is useful for separating user data that should never
be deleted from ephemeral cache/config data that can be regenerated.

### Entrypoint must live outside home

If the entrypoint script is at `/home/opencode/docker-entrypoint.sh`,
it gets shadowed by a home volume mount. Moving it to a system path
(`/usr/local/bin/docker-entrypoint.sh`) ensures it always runs the
version from the current image.

## Consequences

### Positive

- No more adding volumes per tool — everything under `~/.config/`,
  `~/.local/share/`, `~/.cache/`, `~/.agents/` is automatically
  persisted
- docker-compose.yaml is clean and stable (2 volumes vs 5+)
- Workspace projects always survive tool version bumps
- Entrypoint is immune to volume shadowing
- Tool binaries at `/opt/fnm/` are immune to volume shadowing

### Negative

- Deleting the home volume loses OpenCode sessions, plugin caches,
  and auth tokens — need to re-run login commands
- Users must understand the nested volume concept to know why
  workspace survives home wipes

### Risks

- If a tool stores data outside `$HOME` (e.g., in `/etc/`, `/var/`),
  it won't be persisted
- If the home volume grows large (4GB+ SQLite DB + caches),
  deleting it on version bumps means losing that data

## Amendment 2026-11-10: toolchain moved out of `$HOME` (no more wipe-to-refresh)

The v2 image initially installed npm-global tools (`~/.npm-global`) and
`~/.local/bin/rtk` as the `opencode` user, i.e. back inside the home volume —
reintroducing the Attempt-2 shadowing bug for exactly those binaries
(`pnpm`/`corepack`, `codegraph`, `tokscale`, `wakatime`, `rtk` missing after a
rebuild onto an existing volume; reproduced 2026-11-10).

Fix (proper, not a reinstall script): binaries now live in the image outside
both volumes — npm globals in `/opt/npm-global` (`NPM_CONFIG_PREFIX`),
Corepack activations in `/opt/corepack` (`COREPACK_HOME`), shims in
`/usr/local/bin` (`corepack enable --install-directory`), `rtk` relocated to
`/usr/local/bin`. `PATH` orders system entries before the retained
`~/.npm-global/bin` / `~/.local/bin` compat entries. (Later cleanup removed
the `~/.npm-global/bin` entry; `~/.opencode/bin` and `~/.local/bin` remain.) MCP/plugin *wiring*
(`codegraph install`, `rtk init`) is home-volume state and is ensured
idempotently by the entrypoint on every start instead of baked at build time.

Consequence change: refreshing tool versions no longer requires deleting
`opencode-home`. The nested-volume layout above is unchanged.

## Related Decisions

- ADR-0001: Ingress strategy (Coolify proxy + Cloudflare DNS)
- ADR-0004: Container security posture (non-root user, cap_drop, etc.)
- ADR-0005: Dev tools strategy (which tools are included)
