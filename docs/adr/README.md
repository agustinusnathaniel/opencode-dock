# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the my-remote-opencode project — a deployment configuration for running a remote OpenCode server on a VPS with Coolify and Cloudflare.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-ingress-strategy.md) | Choose Coolify Proxy + Cloudflare DNS over Cloudflare Tunnel | Accepted |
| [0002](0002-node-version-manager.md) | Choose fnm over nvm/Volta for Node.js Version Management | Accepted |
| [0003](0003-package-manager-strategy.md) | Use Corepack for pnpm and yarn | Accepted |
| [0004](0004-container-security-posture.md) | Container Security Posture | Accepted |
| [0005](0005-dev-tools-strategy.md) | Dev Tools Inclusion Strategy | Accepted |

## Status Meanings

- **Accepted** — decision made, implemented
- **Proposed** — under discussion
- **Deprecated** — no longer relevant
- **Superseded** — replaced by another ADR
