# ADR-0001: Choose Coolify Proxy + Cloudflare DNS over Cloudflare Tunnel

## Status

Accepted

## Context

We need to expose an OpenCode server (HTTP on port 4096) from a VPS running Coolify. The VPS has Coolify installed for container management and a domain managed by Cloudflare (DNS proxied through Cloudflare — orange cloud enabled).

Two options were considered:

1. **Cloudflare Tunnel** — Run a `cloudflared` sidecar container that creates an outbound-only tunnel to Cloudflare's edge. Zero open ports on the VPS.
2. **Coolify Proxy** — Use Coolify's built-in reverse proxy (Caddy/Traefik) with Let's Encrypt SSL. The domain is already behind Cloudflare DNS proxy (orange cloud), so Cloudflare still sits in front.

Originally the setup used Option 1 with a `cloudflared` sidecar in docker-compose.yml.

## Decision Drivers

- **Security** — Minimize open ports on the VPS
- **Simplicity** — Fewer containers, fewer moving parts
- **Existing infrastructure** — Domain already behind Cloudflare DNS proxy
- **Auth** — Want ability to add SSO auth via Cloudflare Access
- **Day-2 operations** — Easy to manage, restart, update

## Considered Options

### Option 1: Cloudflare Tunnel (cloudflared sidecar)

- **Pros**: Zero open ports, Cloudflare Access for SSO, tunnel survives Coolify restart
- **Cons**: Extra container (~30MB), extra dashboard to manage, redundant when DNS is already proxied through Cloudflare

### Option 2: Coolify Proxy + Cloudflare DNS (Chosen)

- **Pros**: One less container, simpler stack, Cloudflare DNS proxy already provides DDoS protection and IP hiding, can still enable Cloudflare Access for SSO, Coolify handles SSL auto-renewal
- **Cons**: Port is exposed on Coolify's internal network (not public internet), slightly tighter coupling to Coolify

## Decision

Use **Coolify's built-in proxy** as the ingress. Remove the `cloudflared` sidecar. The domain is already behind Cloudflare DNS proxy (orange cloud), so traffic still flows through Cloudflare's edge.

Cloudflare Access can still be enabled at the DNS level for SSO authentication before traffic reaches Coolify.

## Consequences

### Positive

- One less container to manage and update
- Simpler docker-compose.yml
- Still protected by Cloudflare DNS proxy (IP hidden, DDoS protection)
- Cloudflare Access remains available for SSO auth
- Coolify handles SSL certificates automatically

### Negative

- Port exposed on Coolify's internal network (acceptable risk — not public)
- Ingress depends on Coolify's proxy being operational

### Risks

- If Coolify proxy is down, the server is unreachable (mitigation: Coolify is self-hosted and we control uptime)
- Cloudflare Access requires Cloudflare proxied DNS, which we already have

## Related Decisions

- ADR-0004: Container security posture (no open ports beyond Coolify's proxy)
