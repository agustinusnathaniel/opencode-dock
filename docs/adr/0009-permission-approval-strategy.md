# ADR-0009: Auto-Approve Permissions via CLI `--auto` Flag (with Config Fallback)

## Status

Accepted (revised)

## Context

OpenCode prompts for permission before executing potentially sensitive actions (file edits, shell commands, web requests, etc.). For a remote server where the developer trusts their own agents, these prompts are unnecessary friction.

Two approaches are available for auto-approving permissions:

1. **CLI `--auto` flag** — A **global** flag (works on ALL subcommands: `serve`, `web`, `run`, TUI) that tells OpenCode to "auto-approve permissions that are not explicitly denied"
2. **Config-based permission setting** — The OpenCode configuration schema supports a top-level `"permission"` field set to `"allow"`, `"ask"`, or `"deny"`, with granular per-action overrides

## Decision Drivers

- **Must work with `opencode serve`** — The chosen server mode
- **Persistent across restarts** — Setting should survive container restarts
- **Simple and auditable** — Easy to understand what's configured

## The Fix: CLI `--auto` Flag

The `--auto` flag is a **global flag** parsed by the root `opencode` command, not a subcommand-specific flag. It works with ALL modes:

```bash
opencode serve --auto --hostname 0.0.0.0 --port 4096   # ✓ works
opencode web --auto --hostname 0.0.0.0 --port 4096     # ✓ works
opencode run "refactor this" --auto                     # ✓ works
opencode --auto                                         # ✓ works (TUI)
```

It does NOT appear in `opencode serve --help` because subcommand help only lists subcommand-specific flags. Global root flags (`--auto`, `--model`, `--agent`, `--print-logs`, etc.) are inherited by all subcommands transparently.

### Dockerfile CMD

```dockerfile
CMD ["opencode", "serve", "--auto", "--hostname", "0.0.0.0", "--port", "4096"]
```

## Belt-and-Suspenders: Config File

The OpenCode config schema (`https://opencode.ai/config.json`) supports `"permission"` as a valid top-level key with values `"allow"`, `"ask"`, or `"deny"`:

```jsonc
// Global auto-approve all:
{ "permission": "allow" }

// Per-action granular control:
{
  "permission": {
    "bash": "allow",
    "read": "allow",
    "edit": "allow",
    "webfetch": "allow",
    "websearch": "allow",
    "question": "allow"
  }
}
```

The `docker-entrypoint.sh` script writes `"permission": "allow"` to the config file on every start if not already set. This provides:

- A persistent fallback if `--auto` were ever removed/changed
- Granular per-action control available if needed later
- Works independently of CLI flags

## Decision

**Use both approaches together:**
1. `--auto` flag in the Dockerfile CMD (primary mechanism)
2. `"permission": "allow"` in config via entrypoint script (secondary/fallback)

## Consequences

### Positive

- Permissions are auto-approved reliably via two independent mechanisms
- `--auto` is a runtime flag — no config file dependency
- Config provides persistent fallback across restarts
- Granular per-action control available if needed later

### Negative

- `--auto` is described as "dangerous" in the help text — acceptable in a single-user VPS
- Config file approach adds a small Node.js execution to container startup

## Related Decisions

- ADR-0008: Server mode strategy (use `opencode serve`)
