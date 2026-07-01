# ADR-0004: Container Security Posture

## Status

Accepted

## Context

The OpenCode server runs as a container on a VPS and is accessible from the internet through Cloudflare and Coolify. We need to establish a security baseline that protects the host system from container breakout, limits blast radius, and follows container security best practices.

## Decision Drivers

- **Defense in depth** — Multiple layers of security, no single point of failure
- **Principle of least privilege** — Container should only have what it needs
- **Operational practicality** — Must not prevent the entrypoint from functioning
- **OpenCode requirements** — Need SSH, git, and shell access for agent operations

## Considered Options

### Runtime security measures

| Measure | Purpose | Tradeoff |
|---------|---------|----------|
| Non-root user | Prevents container escape via UID 0 | Must configure file permissions appropriately |
| `cap_drop: ALL` | Removes all kernel capabilities | Container can't perform privileged operations (not needed) |
| `no-new-privileges:true` | Prevents privilege escalation via setuid binaries | None for this use case |
| Read-only root filesystem | Prevents malware writing to disk | **Conflicts with entrypoint** (needs to write ~/.ssh, ~/.gitconfig, ~/.bashrc) |
| tmpfs for /tmp | Prevents /tmp from persisting across restarts, reduces disk writes | Temporary data lost on restart (acceptable) |

### Read-only filesystem conflict

The entrypoint script writes to the home directory:
- `~/.ssh/id_ed25519` — SSH deploy key
- `~/.ssh/known_hosts` — Host key verification
- `~/.ssh/config` — SSH configuration
- `~/.gitconfig` — Git identity
- `~/.bashrc` — Interactive shell PATH

Making the root filesystem read-only (`read_only: true`) would prevent the container from starting. Workarounds (mounting home directory as a volume, tmpfs for home subpaths) add complexity and risk shadowing baked-in binaries.

## Decision

Apply all applicable hardening measures, **except read-only root filesystem**:

| Measure | Applied |
|---------|---------|
| Non-root `opencode` user | ✅ Dockerfile, `USER opencode` |
| `cap_drop: ALL` | ✅ docker-compose.yml |
| `no-new-privileges:true` | ✅ docker-compose.yml |
| Read-only filesystem | ❌ Removed — conflicts with entrypoint |
| tmpfs for /tmp | ✅ docker-compose.yml |

The non-root user + `cap_drop: ALL` + `no-new-privileges:true` combination already covers the most critical container breakout vectors. Read-only filesystem would be a meaningful addition but is incompatible with the entrypoint's writes.

## Consequences

### Positive

- Container cannot escalate privileges (`no-new-privileges`)
- Container has zero kernel capabilities (`cap_drop: ALL`)
- Container runs without root privileges (non-root user)
- `/tmp` is ephemeral and doesn't persist across restarts
- Entrypoint can write SSH keys and git config at runtime

### Negative

- Without `read_only`, a compromised container could write to the writable layers (mitigated by non-root + no-new-privileges — blast radius is limited)

### Risks

- If the container is compromised, the attacker gains a non-root shell with no capabilities — minimal host impact
- Secrets (SSH key) are in a Docker volume and environment variable — not in the image

## Related Decisions

- ADR-0001: Ingress strategy (Cloudflare hides the VPS IP)
- ADR-0003: Corepack strategy (writable filesystem needed for shims)
