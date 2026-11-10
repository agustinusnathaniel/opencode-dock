# ADR-0009: Granular Per-Tool Permission Config for Headless Mode

## Status

Accepted (revised)

## Context

OpenCode prompts for permission before executing potentially sensitive actions (file edits, shell commands, web requests, etc.). For a remote server where the developer trusts their own agents, these prompts are unnecessary friction.

Two approaches were evaluated:

1. **CLI `--auto` flag** — Presented as a global option in `opencode --help`, but only works with the default TUI mode (`opencode --auto`). It is **not accepted** by `opencode serve` (unknown flag → help displayed, server exits). It also cannot be placed before `serve` (`opencode --auto serve ...`) because the parser then treats `serve` as a positional project path argument.

2. **Config-based permission setting** — The OpenCode config schema (`https://opencode.ai/config.json`) supports a `"permission"` key
   with two forms:
   - Simple string: `"ask"`, `"allow"`, or `"deny"` (global default)
   - Per-tool object: granular control per action type

## Key Finding

The simple `"permission": "allow"` string **only overrides certain tool defaults** — `read`, `edit`, `grep`, `task`, `todowrite` get set to `allow`, but **`bash` (shell commands) remains at `ask`**. This was confirmed in OpenCode's debug logs:

```
message=evaluated permission=bash ... action.action=ask    ← STILL PROMPTING
message=evaluated permission=read ... action.action=allow  ← working
message=evaluated permission=edit ... action.action=allow  ← working
```

The per-tool granular config is required to override `bash`.

## Decision

Use the **per-tool permission object** in the OpenCode config, written by `docker-entrypoint.sh` on every container start:

```jsonc
{
  "permission": {
    "bash": "allow",
    "read": "allow",
    "edit": "allow",
    "glob": "allow",
    "grep": "allow",
    "list": "allow",
    "task": "allow",
    "external_directory": "allow",
    "todowrite": "allow",
    "question": "allow",
    "webfetch": "allow",
    "websearch": "allow",
    "lsp": "allow",
    "doom_loop": "allow",
    "skill": "allow"
  }
}
```

The entrypoint checks if the current config already has this exact object (or the old `"allow"` string) and only writes if missing, avoiding unnecessary writes on every restart.

## Consequences

### Positive

- `bash` (shell commands) is now auto-approved — the most common permission prompt
- Full coverage across all 15 permission types in the schema
- Works with `opencode serve` (no CLI flag dependency)
- Config persists in the Docker volume, surviving restarts
- Per-tool object allows selective tightening later (e.g., deny `bash` but allow `read`)

### Negative

- More verbose config than the simple string approach
- If OpenCode adds new permission types, they'll need to be added here too

## Related Decisions

- ADR-0008: Server mode strategy (use `opencode serve`)

## v2 Amendment (OpenCode 2.x)

v2 replaces the `permission` object with an ordered `permissions` array and
renames actions (`bash`→`shell`, `task`→`subagent`, `write`/`patch`→`edit`).
`doom_loop` and `lsp` are not v2 Core actions, `todowrite` becomes
`experimental.todo`, and `external_directory` is allowed by default. The
entrypoint now writes the native v2 shape and deletes the legacy `permission`
key (v2 normalizes the old shape with warnings). The v1 object above is
retained as the historical record. See ADR-0011.
