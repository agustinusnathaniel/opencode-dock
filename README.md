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
2. Add the public key to your GitHub account (Settings > SSH and GPG keys > New SSH key).
3. Copy the private key contents and set them as the `SSH_PRIVATE_KEY` environment variable in Coolify. Replace actual newlines with `\n` so the key fits in a single env var value.
4. Set `GIT_USER_NAME` and `GIT_USER_EMAIL` so agent commits are attributed to someone identifiable.

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
