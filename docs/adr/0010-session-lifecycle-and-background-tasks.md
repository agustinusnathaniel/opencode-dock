# ADR-0010: Session Lifecycle and Background Task Execution

## Status

Accepted

## Context

> v2 amendment: all `opencode run --attach <url>` examples in this ADR read as
> `opencode run --server <url>` on OpenCode 2.x (`--attach` removed;
> `--auto` and the lifecycle behavior are unchanged). See ADR-0011.

OpenCode v1.17.13 (commercial build from opencode.ai) has a specific session lifecycle model that affects how agents can be used on a remote server.

### Session Lifecycle

1. **Web UI session** — Created via the browser at `opencode.sznm.cloud`. Agent execution streams output to the browser via WebSocket.
2. **CLI session** — Created via `opencode run` (local or with `--attach`). Agent execution streams output to the terminal.

### Key Finding: WebSocket Dependency

When a browser tab is closed while an agent is actively processing, the server logs show:

```
message=cancel session.id=ses_...
message=process ... error=Aborted
```

The in-progress agent execution is **cancelled**. This is by design — OpenCode's agent execution is interactive:

- It streams output token-by-token to the connected client
- It waits for permission approvals (even if auto-approved)
- It may pause for user input (questions, clarifications)

Without a connected WebSocket client, there's no consumer for the output stream and no one to respond to prompts.

### What Persists

- **Session records** survive in SQLite (`opencode.db`) — they appear in `opencode session list`
- **Completed sessions** are fully reviewable in the web UI
- **Cancelled sessions** show partial results up to the cancellation point

## Decision Drivers

- **Fire-and-forget capability** — Run long tasks without keeping a browser tab open
- **Session review** — See results of completed background tasks in the web UI
- **Single server** — All sessions live on the same server, share tools and workspace

## Decision: Use `opencode run --attach` for Background Tasks

OpenCode provides `opencode run --attach` which connects a CLI session to a running server:

```bash
# From the container itself:
opencode run "refactor the auth module" \
  --attach http://localhost:4096 \
  --auto

# From a local machine (if server is exposed):
opencode run "refactor the auth module" \
  --attach https://opencode.sznm.cloud \
  --auto \
  -p "$OPENCODE_SERVER_PASSWORD"
```

Key flags:

| Flag | Purpose |
|------|---------|
| `--attach <url>` | Connect to running server instead of starting a local one |
| `--auto` | Auto-approve permissions (works with `run`, unlike `serve`) |
| `-p <password>` | Server password for auth |
| `-s <session>` | Continue an existing session |
| `-c` | Continue the last session |

### Workflow Pattern

```
┌─────────────────────────────────────────────────────┐
│                  Interactive Work                     │
│  Browser → opencode.sznm.cloud → Web UI              │
│  • Real-time streaming                               │
│  • Manual permission approval if needed               │
│  • Tab must stay open while agent works               │
└─────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                  Background Tasks                     │
│  Terminal → opencode run --attach                     │
│  • Fire-and-forget                                    │
│  • Session persists after completion                  │
│  • Review results in Web UI later                     │
└─────────────────────────────────────────────────────┘
```

### Example Workflows

**Long-running refactor (background):**
```bash
ssh my-vps
docker exec -it $(docker ps --filter name=opencode -q) \
  opencode run "Refactor the entire auth layer to use HTTP-only cookies" \
  --attach http://localhost:4096 --auto
# Ctrl+C or close terminal — agent keeps running
# Later: open web UI → session completed, review diff
```

**Quick task from local machine:**
```bash
opencode run "Add input validation to the signup form" \
  --attach https://opencode.sznm.cloud \
  --auto -p "$PASSWORD"
```

**Continue a cancelled/interrupted session:**
```bash
opencode run --continue \
  --attach https://opencode.sznm.cloud \
  --auto -p "$PASSWORD"
```

### Use Case: Remote Agent Executor for Another AI System

This deployment can act as a **remote execution backend** for another AI agent (e.g., Hermes, Claude Code, Codex). Instead of the primary AI running tools directly (which may have resource constraints), it delegates code-intensive tasks to the OpenCode server.

```
┌─────────────────┐     plan + prompt     ┌──────────────────────┐
│  Primary AI     │ ────────────────────→  │  OpenCode Server      │
│  (Hermes, etc.) │                        │  (VPS, 16GB, 6 cores) │
│                 │ ←──────────────────── │                       │
│                 │   session ID / result  │  • Runs tools (bash,  │
│                 │                        │    edit, git, etc.)   │
│                 │                        │  • Has SSH keys,      │
│                 │                        │    workspace access   │
│                 │                        │  • Full toolchain     │
└─────────────────┘                        └──────────────────────┘
```

The primary AI invokes OpenCode via:

```bash
opencode run "<task description>" \
  --attach http://opencode:4096 \   # or localhost if same host
  --auto \
  -p "$OPENCODE_SERVER_PASSWORD"
```

**Why this works:**

| Requirement | How it's met |
|---|---|
| Auto-approved permissions | `--auto` flag (valid for `run`) |
| Fire-and-forget execution | `opencode run` doesn't need persistent WebSocket |
| Result retrieval | Session ID returned; poll or open web UI to review |
| Same network | Both containers on same Coolify host → low latency |
| Resource isolation | OpenCode has its own 4GB/4core limit, doesn't compete with primary AI |

## Consequences

### Positive

- Background tasks are possible via `opencode run --attach`
- Sessions are fully reviewable in the web UI regardless of how they were created
- `--auto` works with `run` (unlike `serve`)
- No additional infrastructure needed — uses the same running server

### Negative

- Background execution requires CLI access (SSH into container or local `opencode` binary)
- No web UI streaming for background tasks — results only visible after completion
- `opencode run` sessions use the server's working directory and tools, not the local environment

## Related Decisions

- ADR-0008: Server mode strategy (`opencode serve`)
- ADR-0009: Permission approval strategy (per-tool `"allow"` config)
