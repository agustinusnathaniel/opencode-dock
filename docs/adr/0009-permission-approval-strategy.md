# ADR-0009: Config-Based Permission Approval Over CLI `--auto` Flag

## Status

Accepted

## Context

OpenCode prompts for permission before executing potentially sensitive actions (file edits, shell commands, web requests, etc.). For a remote server where the developer trusts their own agents, these prompts are unnecessary friction.

Two approaches were considered for auto-approving permissions:

1. **CLI `--auto` flag** — The global `--auto` flag on the `opencode` binary claims to "auto-approve permissions that are not explicitly denied (dangerous!)"
2. **Config-based permission setting** — The OpenCode configuration schema supports a top-level `"permission"` field set to `"allow"`, `"ask"`, or `"deny"`, with granular per-action overrides

The `--auto` flag was initially attempted by modifying the Dockerfile CMD:

```dockerfile
CMD ["opencode", "web", "--auto", "--hostname", "0.0.0.0", "--port", "4096"]
```

This caused the container to immediately crash-loop because `--auto` is **not a valid flag** for the `web` or `serve` subcommands — it only applies to the default TUI mode. The CLI parser rejects unknown flags and exits with the help screen.

## Decision Drivers

- **Must work with `opencode serve`** — The chosen server mode
- **Persistent across restarts** — Setting should survive container restarts
- **Simple and auditable** — Easy to understand what's configured
- **No container crash risk** — Unlike invalid CLI flags

## Considered Options

### Option 1: CLI `--auto` flag (rejected)

- **Pros**: Simple to add to Dockerfile CMD
- **Cons**: **Does not work** with `opencode web` or `opencode serve` — only valid for TUI mode; caused container crash-loop; no way to verify without deploying

### Option 2: Config-based `"permission": "allow"` (chosen)

- **Pros**: Supported by the OpenCode config schema (`PermissionConfig`); persists in config file across restarts; supports granular per-action overrides (`bash`, `read`, `edit`, `websearch`, etc.); no risk of crash-loop
- **Cons**: Requires modifying `opencode.jsonc` config file; config file lives in the persistent Docker volume

### Option 3: Entrypoint auto-set (chosen approach)

Write the `"permission": "allow"` setting on every container start via the `docker-entrypoint.sh` script. This combines the reliability of config-based approach with automatic setup.

```javascript
const configFile = process.env.HOME + "/.config/opencode/opencode.jsonc";
let config = {};
try { config = JSON.parse(fs.readFileSync(configFile, "utf8")); } catch (e) {}
if (config.permission !== "allow") {
    config.permission = "allow";
    fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
}
```

## Decision

Add a startup block in `docker-entrypoint.sh` that ensures `"permission": "allow"` is set in the OpenCode config. This runs on every container start and only writes if not already set, preserving any manual changes.

The config schema supports both a simple string value or a per-action object:

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

## Consequences

### Positive

- Permissions are auto-approved from the first start
- Works with both `opencode serve` and `opencode web`
- No risk of crash-loop from invalid CLI flags
- Granular control available if needed later
- Config file persists in volume, surviving restarts

### Negative

- Adds a small Node.js execution to every container startup
- Permission setting stored in config file can be manually overridden

## Related Decisions

- ADR-0008: Server mode strategy (use `opencode serve`)
