# ADR-0008: Use `opencode serve` Over `opencode web` for Remote Deployment

## Status

Accepted

## Context

OpenCode can be started in two server modes:

1. **`opencode web`** — starts the server and attempts to open a browser window locally (designed for local interactive use)
2. **`opencode serve`** — starts the server without opening a browser (designed for remote/headless deployment)

Both modes serve the **same web UI** (HTML, JS, API) on the configured port. The term "headless" in `serve` refers to **no terminal TUI**, not the absence of a web interface.

The original deployment used `opencode web` because it was assumed `opencode serve` would not serve the web UI. This caused two issues:

- **Browser tab lifecycle**: `opencode web` may tie session lifetime to browser WebSocket connections, causing sessions to be cleaned up when the browser tab is closed
- **Misleading documentation**: The `--help` output for `serve` says "headless opencode server" which was misinterpreted as API-only

## Decision Drivers

- **Session persistence** — Sessions should survive browser tab closure
- **Remote-first design** — The server runs on a VPS, accessed via Coolify proxy, not a local machine
- **Web UI access** — Must still be accessible from any browser via `https://opencode.sznm.cloud`

## Considered Options

### Option 1: `opencode web` (original)

- **Pros**: Explicitly named for web access
- **Cons**: May tie session lifecycle to browser connection; designed for local use where opening a browser tab is expected

### Option 2: `opencode serve` (chosen)

- **Pros**: Designed for remote/headless deployment; serves identical web UI; sessions are independent of browser connections; used by reference projects like [ort](https://github.com/grikomsn/ort)
- **Cons**: None (functionally identical for our use case)

## Decision

Use `opencode serve` for the server CMD. Both modes serve the same web UI on the same port, but `serve` is designed for persistent remote operation where browser connections may come and go.

```dockerfile
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
```

## Consequences

### Positive

- Sessions persist across browser tab open/close cycles
- Server behavior matches upstream expectations for remote deployment
- Web UI remains fully accessible via Coolify proxy

### Negative

- None identified — functionally identical to `opencode web` for remote access

## Related Decisions

- ADR-0009: Permission approval strategy (config-based auto-approve)
