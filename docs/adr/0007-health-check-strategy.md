# ADR-0007: Health Check Strategy

## Status

Accepted

## Context

The OpenCode container runs behind Coolify's Traefik proxy, which uses health
checks to decide whether to route traffic to a container. Docker also uses
health checks for container lifecycle management (restart policies, rolling
updates). Both Beszel and Coolify surface container health status to the
operator.

Early attempts guessed the health endpoint path, resulting in false
"unhealthy" status even when the server was running properly.

## The Problem

Two issues caused health checks to fail:

1. **Wrong endpoint** — the initial health check targeted
   `/global/health`, which doesn't exist in OpenCode's HTTP API.

2. **Missing authentication** — when `OPENCODE_SERVER_PASSWORD` is set
   (required for remote deployments), every endpoint requires Basic auth,
   including the health endpoint. The health check curl command sent no
   credentials and received a 401, which `curl -f` treats as failure.

## Discovery

OpenCode's HTTP API is defined in
`packages/protocol/src/groups/health.ts` in the upstream repo:

```typescript
export const HealthGroup = HttpApiGroup.make("server.health").add(
  HttpApiEndpoint.get("health.get", "/api/health", {
    success: Schema.Struct({ healthy: Schema.Literal(true) }),
  }),
)
```

The actual health endpoint is `/api/health`, returning `{"healthy":true}`.

The global authorization middleware in
`packages/server/src/middleware/authorization.ts` applies to all groups.
There is no bypass for the health route.

## Decision

Use two fixes in the health check configuration:

1. **Correct the path** to `http://localhost:4096/api/health`.

2. **Pass Basic auth credentials** via `curl -u`. The username and
   password are pulled from the same env vars the server uses:
   `OPENCODE_SERVER_USERNAME` (default `opencode`) and
   `OPENCODE_SERVER_PASSWORD`.

### Dockerfile

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f -u "${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD}" http://localhost:4096/api/health
```

The `CMD` form runs through `/bin/sh -c`, so shell variable expansion works.
When `OPENCODE_SERVER_PASSWORD` is unset, `-u opencode:` sends an empty
password, which the server ignores (auth middleware short-circuits when no
password is configured).

### Docker Compose

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f -u \"${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD}\" http://localhost:4096/api/health"]
```

The JSON array `["CMD", "curl", ...]` form doesn't invoke a shell, so env
vars aren't expanded. Switched to `CMD-SHELL` to get expansion.

## Consequences

### Positive

- Container correctly reports healthy within the `start_period` (15s)
- Works with both authenticated and unauthenticated server modes
- Beszel and Coolify show accurate health status
- Rolling updates and restart policies work correctly

### Negative

- `start_period: 15s` may be too short on slow VPSes or with cold
  caches (first start after wiping the home volume). Increase to 30s
  if the container has enough time to start but still appears unhealthy.
- Password with shell-special characters (`$`, `\`, `` ` ``) would need
  escaping. In practice, auto-generated passwords from password managers
  use alphanumeric characters and are safe.

## Related Decisions

- ADR-0001: Ingress strategy (Coolify proxy + Cloudflare DNS)

## v2 Amendment (OpenCode 2.x)

Probed on `2.2.7`: `/api/health` returns `404` (endpoint removed in the
revised v2 server API). The replacement healthcheck target is `GET /api/info`,
which returns `200` with `{"version":...}` when authenticated and `401`
otherwise. `OPENCODE_SERVER_USERNAME` is no longer supported (username is
always `opencode`); `OPENCODE_PASSWORD` is canonical and
`OPENCODE_SERVER_PASSWORD` still works as fallback. See ADR-0011. The `CMD`
snippets above are retained as the v1 historical record.

2026-11 note: the legacy password fallback was removed from this deployment
(entrypoint, compose env, and healthcheck now use `OPENCODE_PASSWORD` only),
and the redundant Dockerfile `HEALTHCHECK` was deleted — the compose
healthcheck is the single definition (compose overrides the image value, so
two definitions could never both apply).
