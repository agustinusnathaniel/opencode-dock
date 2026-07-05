# ADR-0008: Use `opencode serve` Over `opencode web` for Remote Deployment

## Status

Accepted

## Context

OpenCode can be started in two server modes:

1. **`opencode web`** — starts the server and attempts to open a browser window locally (designed for local interactive use)
2. **`opencode serve`** — starts the server without opening a browser (designed for remote/headless deployment)

Both modes serve the **same web UI** (HTML, JS, API) on the configured port. The term "headless" in `serve` refers to **no terminal TUI**, not the absence of a web interface.

The original deployment used `opencode web` because it was assumed `opencode serve` would not serve the web UI.

## Decision Drivers

- **Remote-first design** — The server runs on a VPS, accessed via Coolify proxy, not a local machine
- **Web UI access** — Must still be accessible from any browser via `https://opencode.sznm.cloud`

## Considered Options

### Option 1: `opencode web` (original)

- **Pros**: Explicitly named for web access
- **Cons**: Attempts to open browser locally — fails or spams logs in headless container

### Option 2: `opencode serve` (chosen)

- **Pros**: Designed for remote/headless deployment; serves identical web UI; used by reference projects like [ort](https://github.com/grikomsn/ort)
- **Cons**: None (functionally identical for our use case)

### Session Lifecycle Note

Neither mode supports keeping an agent running after the browser tab is closed. The in-progress agent execution is tied to the WebSocket connection. When the tab closes, the session is cancelled (`error=Aborted`). For background execution, use `opencode run --attach` (see ADR-0010).

## Decision

Use `opencode serve` for the server CMD. Both modes serve the same web UI on the same port, but `serve` is designed for persistent remote operation where browser connections may come and go.

```dockerfile
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
```

## Consequences

### Positive

- Server doesn't attempt to open browser (no errors in headless container)
- Web UI remains fully accessible via Coolify proxy

### Negative

- In-progress sessions are cancelled when browser tab closes (see ADR-0010 for workaround)

## Related Decisions

- ADR-0009: Permission approval strategy (per-tool config in entrypoint)
