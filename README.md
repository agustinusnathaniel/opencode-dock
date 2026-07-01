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
```

Traffic flows from your device through Cloudflare's proxy (which hides your VPS IP), then to Coolify's reverse proxy (which handles SSL termination), then to the OpenCode container.

The container runs with a 4GB memory / 2 CPU limit. Adjust in Coolify's UI if needed.

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

- **Runtime:** Node.js 22 (via fnm), Bun
- **Package managers:** npm, pnpm, yarn (via Corepack)
- **Version control:** git, openssh-client, gh CLI
- **Code intelligence:** CodeGraph (`codegraph`), Rust Token Killer (`rtk`)
- **Build tools:** build-essential (gcc, g++, make, procps)

## Environment Variables

See `.env.example` for the full list with descriptions. The ones you need to care about:

| Variable | Required | Purpose |
| --- | --- | --- |
| `OPENCODE_SERVER_PASSWORD` | Yes | Password for the web UI and API. Set a strong one. |
| `OPENCODE_GO_API_KEY` | Yes | API key for the model provider agents will use. |
| `SSH_PRIVATE_KEY` | No | Private key for agents to push/pull code. |
| `GIT_USER_NAME` | No | Git author name for agent commits. |
| `GIT_USER_EMAIL` | No | Git author email for agent commits. |
| `OPENCODE_SERVER_USERNAME` | No | HTTP basic auth username (default: `opencode`). |
| `PNPM_VERSION` | No | pnpm version (default: 10.10.0). |
| `YARN_VERSION` | No | Yarn version (default: 4.9.1). |

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
3. Add the **private key** as an environment variable in Coolify. Paste the full key verbatim (with newlines) into the `SSH_PRIVATE_KEY` field:
   ```bash
   cat ~/.ssh/opencode_deploy_key
   # Copy the entire multi-line output into Coolify
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

## Credits

- [OpenCode](https://opencode.ai/) -- the agentic coding tool this whole thing runs
- [ort](https://github.com/grikomsn/ort) by grikomsn -- community OpenCode deployment project that inspired the dev tools setup
- [Coolify](https://coolify.io/) -- the self-hosted PaaS that makes deployment straightforward
- [Cloudflare](https://cloudflare.com/) -- DNS, DDoS protection, and access auth
