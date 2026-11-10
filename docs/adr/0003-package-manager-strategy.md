# ADR-0003: Use Corepack for pnpm and yarn

## Status

Accepted

## Context

The OpenCode Docker image needs JavaScript package managers available for agent workflows. npm ships with Node.js by default, but agents may need pnpm (for monorepos, disk-efficient installs) and yarn (for projects that use it).

Options: install pnpm and yarn directly via npm, use Corepack, or install stand-alone binaries.

## Decision Drivers

- **Minimal image size** — Avoid adding unnecessary binaries
- **Official support** — Use the Node.js-endorsed method
- **Version pinning** — Must be able to pin specific versions
- **Zero extra dependencies** — Should not require additional system packages

## Considered Options

### Option 1: Corepack (Chosen)

- **Pros**: Ships with Node.js 22 (no extra download), `corepack enable` activates it, `corepack prepare <pkg>@<version> --activate` pins exact versions, official Node.js project tool
- **Cons**: Not enabled by default (must run `corepack enable`), requires writable filesystem for shims

### Option 2: Direct npm install

- `npm install -g pnpm yarn`
- **Pros**: Works everywhere, well-known
- **Cons**: Depends on npm being healthy, longer install, duplicates download

### Option 3: Standalone install scripts

- `curl -fsSL https://get.pnpm.io/install.sh | bash -`
- **Pros**: Official method for each tool
- **Cons**: Multiple install scripts, larger image, no unified version management

## Decision

Use **Corepack** to enable pnpm (11.9.0) and yarn (4.17.0). This runs in the Dockerfile toolchain layer.

Versions are pinned explicitly in the Dockerfile to prevent surprise breakage from upstream releases.

## Amendment 2026-11-10: shims and activations live outside `$HOME`

A bare `corepack enable` targets a `HOME`-adjacent directory, which the
`opencode-home` volume shadows (reproduced: `corepack: command not found`
after rebuild). The image therefore sets `COREPACK_HOME=/opt/corepack` and
runs `corepack enable --install-directory /usr/local/bin`, so shims (`pnpm`,
`yarn`) and activations survive existing volumes. `npm install -g corepack`
itself targets the system prefix (`NPM_CONFIG_PREFIX=/opt/npm-global`), not
`~/.npm-global`.

## Consequences

### Positive

- Zero additional image size (Corepack ships with Node.js)
- Pinned versions prevent surprise breakage
- One unified tool for all package managers
- Follows Node.js project best practices

### Negative

- Versions must be manually updated in Dockerfile
- Run `corepack enable` requires writable filesystem at build time (handled by writable Docker layers)

## Related Decisions

- ADR-0002: fnm for Node.js (Corepack ships with Node)
- ADR-0005: Dev tools strategy (package managers are dev tools)
