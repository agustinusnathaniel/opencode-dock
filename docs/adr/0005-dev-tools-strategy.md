# ADR-0005: Dev Tools Inclusion Strategy

## Status

Accepted

## Context

The OpenCode server runs an agent that can execute shell commands, run scripts, and interact with code. The Docker image needs to include developer tools that enable common agent workflows. The community project `ort` by grikomsn served as inspiration for the tool set.

We need to decide which tools to include in the image and which to leave out.

## Decision Drivers

- **Agent capability** — Agents should be able to clone repos, install dependencies, run scripts, and create PRs
- **Image size** — Keep the image reasonably small for faster deployments
- **Maintenance burden** — Avoid tools that require frequent updates or complex build logic
- **Use case relevance** — Only include tools agents are likely to use

## Included Tools

| Tool | Purpose | Size | Source |
|------|---------|------|--------|
| **git** | Clone repos, commit, push | ~10 MB | apt |
| **openssh-client** | SSH key-based git auth | ~5 MB | apt |
| **curl, ca-certificates** | HTTP requests, API calls | ~5 MB | apt |
| **gh CLI** | GitHub PRs, issues, releases | ~30 MB | apt (GitHub CLI repo) |
| **Node.js 22** | Run JS/TS, npm scripts | ~60 MB | fnm |
| **pnpm 11.9.0** | Disk-efficient package management | ~0 MB | Corepack |
| **yarn 4.17.0** | Alternative package manager | ~0 MB | Corepack |
| **Bun** | Fast JS runtime, test runner, bundler | ~50 MB | bun.sh install script |
| **build-essential** | Compile native npm addons (node-gyp) | ~60 MB | apt |

## Considered but Excluded

| Tool | Reason Excluded |
|------|----------------|
| **Flutter / FVM** | ~1.2 GB+ for the SDK. Unlikely agents need to compile Flutter. Can be added later per-project. |
| **Android SDK / JDK** | ~3-5 GB. Only needed for Android builds. Massive image increase for rare use. |
| **Python / pip** | Not commonly needed for web dev workflows. Can be added by agents with apt. |
| **Docker CLI** | Would allow container-in-container workflows. Security risk and complexity. Agents can use Coolify for deployments. |
| **Rust / Go** | Language-specific compilers. Agents can install if needed via apt/curl. |
| **FFmpeg** | Not relevant for web development. |

## Decision

Include the tool set listed above. This covers the 95% case: clone repo → install deps → run scripts → create PR. Exclude heavy SDKs and platform-specific tools that agents can install on-demand.

The `build-essential` package is intentionally included despite its ~60MB size. It prevents confusing failures when `npm install` encounters a package with native bindings (node-gyp). The cost is a one-time build-time increase; the benefit is silent, correct behavior for thousands of npm packages.

## Consequences

### Positive

- Image is self-sufficient for the vast majority of web dev workflows
- No confusing failures from missing system dependencies
- PR workflow works out of the box (git + gh + SSH key)
- Corepack tools add zero image weight

### Negative

- `build-essential` adds ~60MB (trade-off for reliability)
- Bun adds ~50MB (trade-off for an alternative fast runtime)
- Total image ~250-300MB — larger than a minimal Node image

### Risks

- Tool versions need periodic updates (Dockerfile maintains the source of truth)
- If a project needs Flutter/Android/Rust, the image won't support it (mitigation: agents can install via curl/apt; or the Dockerfile can be extended per-project)

## Related Decisions

- ADR-0002: fnm for Node.js (provides Node 22)
- ADR-0003: Corepack for pnpm/yarn (package managers)

## v2 Note (OpenCode 2.x, ADR-0011)

The tool *set* above is unchanged, but provisioning moved with the
official-image base: `apt` → `apk` (`github-cli` instead of the `gh` package
name), fnm → Alpine Node (v24.x at last probe), and the current image carries
neither Bun nor build-essential. Source column above is the v1 historical
record.
- ADR-0004: Container security (build-essential includes compilers — no security concern, they're used at runtime)

## v2.1 Note (2026-11-10: binaries out of `$HOME`, ADR-0006 amendment)

npm-global tools moved from `~/.npm-global` (home volume, shadowed on rebuild)
to the system prefix `/opt/npm-global`; `rtk` moved from `~/.local/bin` to
`/usr/local/bin`. MCP/plugin *wiring* stays home-volume state, ensured by the
entrypoint. `~/.npm-global/bin` and `~/.local/bin` remain on `PATH` after the
system entries for backward compatibility only. (Later cleanup dropped the
`~/.npm-global/bin` entry once no volume needed it; `~/.opencode/bin` and
`~/.local/bin` remain.)
CodeGraph's npm launcher is replaced at build with a system-Node wrapper (its
vendored glibc Node cannot execute on musl); a build-time smoke test runs
every toolchain binary so a broken tool fails the build.
