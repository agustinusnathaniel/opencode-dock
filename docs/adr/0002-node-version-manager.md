# ADR-0002: Choose fnm over nvm/Volta for Node.js Version Management

## Status

Accepted

## Context

The OpenCode Docker image needs Node.js available for agent workflows (running scripts, installing dependencies, building projects). We need to decide how to install and manage the Node.js version in the container.

Four options were considered: fnm, nvm, Volta, and direct Node.js installation.

## Decision Drivers

- **Docker compatibility** — Must work in non-interactive environments (Docker RUN and ENTRYPOINT)
- **Startup time** — Near-zero overhead per container start
- **Build time** — Fast, reliable install in Dockerfile layers
- **Version switching** — Support for `.nvmrc` and `.node-version` files (agents may clone projects with pinned versions)
- **Active maintenance** — Must be actively maintained

## Considered Options

### Option 1: fnm (Fast Node Manager) — Rust-based

- **Pros**: Single ~7MB static binary, no shell sourcing needed, sub-ms startup, supports `.nvmrc` and `.node-version`, actively maintained, widely used in CI/Docker
- **Cons**: Additional tool to install in the image (~7MB)

### Option 2: nvm — Shell-based

- **Pros**: Most widely known, large community, supports `.nvmrc`
- **Cons**: Must source shell functions in every RUN layer (~200-500ms overhead per invocation), requires git clone of full repo, only works in POSIX shells

### Option 3: Volta — Rust-based

- **Pros**: Fast, binary-based, auto-switching via shims
- **Cons**: **Unmaintained** — maintainers recommend migrating off. Does not support `.nvmrc` or `.node-version`.

### Option 4: Direct Node.js installation (no version manager)

- **Pros**: Simplest, smallest image
- **Cons**: No version switching, manual updates, no `.nvmrc` support

## Decision

Use **fnm** as the Node.js version manager. Install Node 22 via `fnm install 22 && fnm default 22`.

## Consequences

### Positive

- Sub-millisecond startup time
- Works in Docker without shell sourcing boilerplate
- Supports `.nvmrc` and `.node-version` for project-level version pinning
- Single binary, easy to install in Dockerfile
- Actively maintained by a large open-source community

### Negative

- Adds ~7MB to the image (negligible)
- Another tool in the stack alongside the tech it manages

## Related Decisions

- ADR-0003: Corepack for pnpm/yarn (complements Node.js runtime)
- ADR-0005: Dev tools strategy (Node.js is a core tool)
