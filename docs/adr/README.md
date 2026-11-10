# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the my-remote-opencode project — a deployment configuration for running a remote OpenCode server on a VPS with Coolify and Cloudflare.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-ingress-strategy.md) | Choose Coolify Proxy + Cloudflare DNS over Cloudflare Tunnel | Accepted |
| [0002](0002-node-version-manager.md) | Choose fnm over nvm/Volta for Node.js Version Management | Superseded by 0011 |
| [0003](0003-package-manager-strategy.md) | Use Corepack for pnpm and yarn | Accepted |
| [0004](0004-container-security-posture.md) | Container Security Posture | Accepted |
| [0005](0005-dev-tools-strategy.md) | Dev Tools Inclusion Strategy | Accepted |
| [0006](0006-volume-strategy.md) | Container Volume Strategy | Accepted |
| [0007](0007-health-check-strategy.md) | Health Check Strategy | Accepted |
| [0008](0008-server-mode-strategy.md) | Use `opencode serve` Over `opencode web` for Remote Deployment | Accepted |
| [0009](0009-permission-approval-strategy.md) | Granular Per-Tool Permission Config for Headless Mode | Accepted (revised) |
| [0010](0010-session-lifecycle-and-background-tasks.md) | Session Lifecycle and Background Task Execution | Accepted |
| [0011](0011-opencode-v2-migration.md) | Migrate to OpenCode v2 (install, auth, permissions, healthcheck; base-image evaluation) | Accepted |

## Status Meanings

- **Accepted** — decision made, implemented
- **Proposed** — under discussion
- **Deprecated** — no longer relevant
- **Superseded** — replaced by another ADR
