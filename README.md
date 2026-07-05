# my-remote-opencode

Deploy an OpenCode server on your own VPS. Uses Coolify for hosting and Cloudflare for DNS and optional auth. This setup gives you a remote agent workspace you can connect to from the OpenCode desktop client or browser, without leaving your infrastructure.

## Prerequisites

- A VPS with [Coolify](https://coolify.io/) installed and running
- A domain managed by Cloudflare (DNS proxied through Cloudflare -- orange cloud enabled)
- Basic familiarity with Coolify deployments (adding resources, setting domains, configuring env vars)

## Architecture

```
Your Device (Browser or OpenCode Desktop)
  |
  | HTTPS
  v
Cloudflare (DNS proxy + optional Access auth)
  |
  | HTTPS
  v
Coolify Proxy (Caddy/Traefik + Let's Encrypt SSL)
  |
  | HTTP (internal)
  v
OpenCode Server (port 4096, inside Docker)
  |
  | Entrypoint: /usr/local/bin/docker-entrypoint.sh
  |  • Injects SSH key from SSH_PRIVATE_KEY env var
  |  • Writes provider keys to auth.json (OPENCODE_GO_API_KEY / ZEN_API_KEY)
  |  • Configures git identity (GIT_USER_NAME / GIT_USER_EMAIL)
  |  • Sets up WakaTime config (WAKATIME_API_KEY)
  |  • Formats single-line SSH keys into proper multi-line format
```

Traffic flows from your device through Cloudflare's proxy (which hides your VPS IP), then to Coolify's reverse proxy (which handles SSL termination), then to the OpenCode container.

The container runs with a 4GB memory / 2 CPU limit and explicit DNS (1.1.1.1, 8.8.8.8).
Adjust in Coolify's UI if needed.

## Deploying in Coolify

1. Fork or clone this repo to your GitHub account.
2. In Coolify, go to "New Resource" and pick "Docker Compose".
3. Connect the git repository you forked/cloned.
4. Set the domain (e.g., `opencode.yourdomain.com`) and point it to port `4096`.
5. Add the environment variables listed in `.env.example` (at minimum `OPENCODE_SERVER_PASSWORD` and `OPENCODE_GO_API_KEY`).
6. Deploy.

Coolify will pull the repo, build the Docker image, and start the container. The first build downloads the OpenCode binary and may take a minute.

## Included Tools

The Docker image ships with these tools pre-installed:

- **Runtime:** Node.js 24 (via fnm at `/opt/fnm`)
- **Package managers:** npm, pnpm 11.9.0, yarn 4.17.0 (via Corepack)
- **Version control:** git, openssh-client, gh CLI
- **Code intelligence:** CodeGraph (`codegraph`), Rust Token Killer (`rtk`)
- **AI coding tools:** Tokscale (`tokscale`), WakaTime plugin (`opencode-wakatime`)
- **System tools:** procps, xdg-utils

## Persistent Volumes

Runtime data persists across restarts through four named volumes:

| Volume | Mount | Covers |
|--------|-------|-------|
| `opencode-home` | `/home/opencode` | Everything: config, data, cache, agents, auth tokens |
| `opencode-workspace` | `/home/opencode/workspace` | Projects (survives home volume wipes) |

Tool binaries live at `/opt/fnm/` (Node.js) and `/usr/local/bin/` (entrypoint) —
outside the home volume so they never get shadowed.

On tool version upgrades, delete `opencode-home` before redeploying to get
fresh binaries. The workspace volume is unaffected.

## Environment Variables

See `.env.example` for the full list with descriptions. The ones you need to care about:

| Variable | Required | Purpose |
| --- | --- | --- |
| `OPENCODE_SERVER_PASSWORD` | Yes | Password for the web UI and API. Set a strong one. |
| `OPENCODE_GO_API_KEY` | Yes | API key for the OpenCode Go provider. |
| `OPENCODE_ZEN_API_KEY` | No | Falls back to `OPENCODE_GO_API_KEY` if not set. Same key works for both. |
| `SSH_PRIVATE_KEY` | No | Private key for agents to push/pull code. Supports single-line and multi-line formats. |
| `GIT_USER_NAME` | No | Git author name for agent commits. |
| `GIT_USER_EMAIL` | No | Git author email for agent commits. |
| `GITHUB_TOKEN` | No | GitHub personal access token for `gh` CLI auth. |
| `WAKATIME_API_KEY` | No | WakaTime API key for coding activity tracking. |
| `OPENCODE_SERVER_USERNAME` | No | HTTP basic auth username (default: `opencode`). |

## Updating OpenCode

1. Open `docker-compose.yml`
2. Change the `OPENCODE_VERSION` build arg to the new version
3. Rebuild: Coolify will pick up the change on the next deployment

To check the current installed version, run `opencode --version` in a session.

## Cloudflare Access (Optional Auth Layer)

If you want SSO log in before anyone reaches your OpenCode server, add Cloudflare Access:

1. Open Cloudflare Zero Trust and go to Access > Applications.
2. Add a self-hosted application.
3. Set the domain to the same one you configured in Coolify (e.g., `opencode.yourdomain.com`).
4. Choose a policy. For example: "Allow everyone with your Google Workspace domain" or "Allow your GitHub account".
5. Save.

This puts an authentication gate in front of your server. No one reaches the OpenCode login screen without passing Cloudflare Access first.

## Usage Patterns

OpenCode v1.17.13 has two distinct usage modes with different session lifecycle behaviors.

### Web UI (Interactive)

Open `https://opencode.sznm.cloud` in your browser. Agent execution streams in real-time. **Keep the tab open** — closing it while an agent is running cancels the in-progress execution.

```
Best for: quick tasks, interactive debugging, reviewing results
Limitation: session is cancelled if tab closes mid-execution
```

### CLI Background Tasks (Fire-and-Forget)

Use `opencode run --attach` to run tasks headlessly against the running server. The task completes even if you close your terminal.

```bash
# From your local machine:
opencode run "Refactor the auth module" \
  --attach https://opencode.sznm.cloud \
  --auto \
  -p "$OPENCODE_SERVER_PASSWORD"

# Continue the last session:
opencode run --continue \
  --attach https://opencode.sznm.cloud \
  --auto -p "$PASSWORD"

# From inside the container (via SSH):
docker exec -it $(docker ps --filter name=opencode -q) \
  opencode run "Add input validation" \
  --attach http://localhost:4096 --auto
```

After completion, open the web UI to review the session in the session list.

```
Best for: long-running tasks, batch operations, scheduled jobs
Result: session persists in DB, reviewable in web UI later
```

See [ADR-0010](docs/adr/0010-session-lifecycle-and-background-tasks.md) for the full technical rationale.

### Remote Agent Executor

This deployment is designed to act as a **remote execution backend** for AI agents. Instead of the primary AI (Hermes, Claude Code, Codex, etc.) running tools directly on a resource-constrained instance, it delegates code tasks to OpenCode:

```bash
# Invoked by the primary AI:
opencode run "Implement the user profile page" \
  --attach http://opencode:4096 \
  --auto \
  -p "$OPENCODE_SERVER_PASSWORD"
```

**Benefits:**
- **Resource isolation** — OpenCode has dedicated 4GB/4core limits, doesn't compete with the primary AI
- **Persistent workspace** — SSH keys, git config, and tools are pre-configured in the OpenCode container
- **Audit trail** — Every delegated task creates a session in the SQLite DB, reviewable in the web UI
- **Same network** — If the primary AI runs on the same Coolify host, `opencode:4096` resolves via Docker DNS

## Connecting OpenCode Desktop

From your local machine:

```bash
opencode --hostname opencode.yourdomain.com --port 443
```

You will be prompted for the `OPENCODE_SERVER_PASSWORD`. Enter it and you are connected.

## SSH Key Setup (Optional)

If you want agents to push code to or pull code from GitHub or GitLab, they need an SSH deploy key.

1. Generate a deploy key on your local machine:
   ```bash
   ssh-keygen -t ed25519 -C "opencode@server" -f ~/.ssh/opencode_deploy_key
   ```
2. Add the **public key** to your GitHub account:
   ```bash
   cat ~/.ssh/opencode_deploy_key.pub
   # Copy the output, then go to GitHub → Settings → SSH and GPG keys → New SSH key
   ```
3. Add the **private key** as an environment variable in Coolify. You can paste the key
   either as a single line or multi-line — the entrypoint handles both formats:
   ```bash
   cat ~/.ssh/opencode_deploy_key
   # Copy the entire output into Coolify's SSH_PRIVATE_KEY field
   ```
4. Set `GIT_USER_NAME` and `GIT_USER_EMAIL` so agent commits are attributed to someone identifiable.

The entrypoint handles both multi-line and `\n`-escaped formats, so paste it as-is.

## GitHub CLI Token (Optional)

If you want agents to use the `gh` CLI (create PRs, manage issues, trigger workflows), add a GitHub personal access token:

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Generate a token with the permissions your agents need (repo, issues, pull requests)
3. Add it as the `GITHUB_TOKEN` environment variable in Coolify

The `gh` CLI autodetects this variable and authenticates automatically.

## Post-Deployment Tools

These tools are not baked into the Docker image but can be installed in your first session. Since the config volume persists across restarts, you only need to do this once.

| Tool | Purpose | Install command |
|------|---------|----------------|
| [Maestria](https://maestria.sznm.dev/) | Agent workflow patterns (8 specialists, pipeline orchestration) | `opencode plugin @maestria/opencode@latest -g` |
| [opencode-wakatime](https://github.com/angristan/opencode-wakatime) | Track AI coding activity in your WakaTime dashboard | `npm i -g opencode-wakatime` then add `"plugin": ["opencode-wakatime"]` to `~/.config/opencode/opencode.json` and create `~/.wakatime.cfg` with your API key |
| [Tokscale](https://github.com/junhoyeo/tokscale) | Token usage and cost dashboard for AI coding tools | `npm i -g tokscale` or use `npx tokscale@latest` |

## Security Notes

- The container runs as a non-root user with a read-only filesystem.
- Cloudflare's DNS proxy hides your VPS IP address from direct attacks.
- Cloudflare Access adds an SSO auth layer before traffic reaches your server (recommended).
- No container ports are exposed beyond what Coolify's reverse proxy handles.
- SSH keys are injected at runtime via environment variables, never baked into the Docker image.
- Persistent volumes only store user config and data, never tool binaries.
  Tool binaries come fresh from the image on every build.

## Credits

- [OpenCode](https://opencode.ai/) -- the agentic coding tool this whole thing runs
- [ort](https://github.com/grikomsn/ort) by grikomsn -- community OpenCode deployment project that inspired the dev tools setup
- [Coolify](https://coolify.io/) -- the self-hosted PaaS that makes deployment straightforward
- [Cloudflare](https://cloudflare.com/) -- DNS, DDoS protection, and access auth
