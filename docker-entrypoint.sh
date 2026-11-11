#!/bin/bash
# This file must live outside $HOME (not shadowed by opencode-home volume)
set -e

# --- Server password (OpenCode v2) ---
# Canonical and only: OPENCODE_PASSWORD. v2 has no OPENCODE_SERVER_USERNAME;
# the username is always `opencode`.
if [ -z "${OPENCODE_PASSWORD:-}" ]; then
    echo "ERROR: Set OPENCODE_PASSWORD before starting." >&2
    exit 1
fi

# --- OpenCode provider auth ---
if [ -n "$OPENCODE_GO_API_KEY" ] || [ -n "$OPENCODE_ZEN_API_KEY" ]; then
    ZEN_KEY="${OPENCODE_ZEN_API_KEY:-$OPENCODE_GO_API_KEY}"
    AUTH_FILE="$HOME/.local/share/opencode/auth.json"
    mkdir -p "$(dirname "$AUTH_FILE")"
    node -e '
        const fs = require("fs");
        const authFile = process.env.HOME + "/.local/share/opencode/auth.json";
        let auth = {};
        try { auth = JSON.parse(fs.readFileSync(authFile, "utf8")); } catch (e) {}
        auth["opencode-go"] = { type: "api", key: process.env.OPENCODE_GO_API_KEY };
        auth["opencode"] = { type: "api", key: process.env.ZEN_KEY };
        fs.writeFileSync(authFile, JSON.stringify(auth, null, 2) + "\n");
    '
fi

# --- SSH key setup ---
if [ -n "$SSH_PRIVATE_KEY" ]; then
    mkdir -p "$HOME/.ssh" 2>/dev/null || true
    if ! printf '%s\n' "$SSH_PRIVATE_KEY" | sed 's/\\n/\n/g' > "$HOME/.ssh/id_ed25519" 2>/dev/null; then
        echo "WARNING: Cannot write to ~/.ssh/. Check volume permissions."
        echo "        SSH key not injected."
    else
        chmod 600 "$HOME/.ssh/id_ed25519"

        # Fix single-line SSH key format (header + body + footer on one line)
        if grep -q -e '-----BEGIN.*-----.*-----END.*-----' "$HOME/.ssh/id_ed25519"; then
            KEY_CONTENT=$(cat "$HOME/.ssh/id_ed25519")
            HEADER=$(echo "$KEY_CONTENT" | sed 's/^\(-----BEGIN[^ ]* KEY-----\).*$/\1/')
            FOOTER=$(echo "$KEY_CONTENT" | sed 's/^.*\(-----END[^ ]* KEY-----\).*$/\1/')
            BODY=$(echo "$KEY_CONTENT" | sed 's/^.*-----BEGIN[^ ]* KEY----- *//' | sed 's/ *-----END[^ ]* KEY-----.*$//' | tr -d '[:space:]')
            {
                echo "$HEADER"
                echo "$BODY" | fold -w 64
                echo "$FOOTER"
            } > "$HOME/.ssh/id_ed25519"
            chmod 600 "$HOME/.ssh/id_ed25519"
        fi

        # Pre-accept host keys for common git hosts
        ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
        ssh-keyscan gitlab.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
        ssh-keyscan bitbucket.org >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

        # SSH config for strict host key checking
        cat > "$HOME/.ssh/config" << 'CONFIGEOF'
Host github.com gitlab.com bitbucket.org
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
CONFIGEOF
        chmod 600 "$HOME/.ssh/config"
        chmod 700 "$HOME/.ssh"
    fi
fi

# --- Git config ---
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi
git config --global core.editor "vim"

# --- WakaTime config ---
if [ -n "$WAKATIME_API_KEY" ]; then
    WAKATIME_HOME="${WAKATIME_HOME:-$HOME/.wakatime}"
    mkdir -p "$WAKATIME_HOME"
    # Only write config if it doesn't exist (preserves WakaTime internal state)
    if [ ! -f "$HOME/.wakatime.cfg" ]; then
        cat > "$HOME/.wakatime.cfg" << EOF
[settings]
api_key = ${WAKATIME_API_KEY}
EOF
    fi
fi

# --- Auto-approve permissions for headless mode (OpenCode v2 shape) ---
# v2 uses a `permissions` array (not the v1 `permission` object) with renamed
# actions: bash->shell, task->subagent, write/patch->edit. doom_loop and lsp
# are not v2 Core actions; todowrite is the experimental.todo flag.
# external_directory is allowed by default in v2; listing it keeps headless
# runs non-interactive even if defaults change.
CONFIG_FILE="$HOME/.config/opencode/opencode.jsonc"
mkdir -p "$(dirname "$CONFIG_FILE")"
node -e '
    const fs = require("fs");
    const configFile = process.env.HOME + "/.config/opencode/opencode.jsonc";
    let config = {};
    try { config = JSON.parse(fs.readFileSync(configFile, "utf8")); } catch (e) {}
    const allowAll = [
        "read", "edit", "glob", "grep", "shell", "subagent",
        "skill", "question", "webfetch", "websearch",
        "external_directory", "experimental_image_generate"
    ].map((action) => ({ action, resource: "*", effect: "allow" }));
    const before = JSON.stringify(config);
    delete config.permission;
    config.permissions = allowAll;
    config.experimental = Object.assign({}, config.experimental, { todo: true });
    if (JSON.stringify(config) !== before) {
        fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
        console.log("Wrote v2 permissions (allow) + experimental.todo to opencode config");
    }
'

# --- Ensure agent-tool wiring in the home volume (idempotent, fail-open) ---
# Binaries live in the image; their *config* lives in the home volume and must
# be (re)created per volume, not baked into the image (a baked copy only seeds
# fresh volumes and is shadowed on existing ones). Each step checks before it
# writes and never blocks server start.
if command -v codegraph >/dev/null 2>&1; then
    if ! grep -q "codegraph" "$CONFIG_FILE" 2>/dev/null; then
        echo "Wiring codegraph MCP server into opencode config..."
        codegraph install --yes --target=opencode \
            || echo "WARNING: codegraph MCP wiring failed (run 'codegraph install --yes --target=opencode' manually)."
    fi
else
    echo "WARNING: codegraph binary missing (expected in /opt/npm-global/bin; image layer incomplete?)." >&2
fi
if command -v rtk >/dev/null 2>&1; then
    rtk init -g --opencode >/dev/null 2>&1 \
        || echo "WARNING: 'rtk init -g --opencode' failed (run manually)."
else
    echo "WARNING: rtk binary missing (expected in /usr/local/bin; image layer incomplete?)." >&2
fi
for _cmd in pnpm yarn tokscale; do
    command -v "$_cmd" >/dev/null 2>&1 \
        || echo "WARNING: $_cmd binary missing (image layer incomplete?)." >&2
done
if [ ! -d "/opt/npm-global/lib/node_modules/opencode-wakatime" ]; then
    echo "WARNING: opencode-wakatime package missing in /opt/npm-global (image layer incomplete?)." >&2
fi
unset _cmd

# --- Interactive-shell PATH: system toolchain first, then user dirs ---
# Binaries live in the image (/opt/npm-global/bin, /usr/local/bin) so home
# volumes can never shadow them (ADR-0006). ~/.opencode/bin (opencode
# self-updates) and ~/.local/bin (XDG user dir) stay on PATH after the system
# entries. The server process itself inherits PATH from the Dockerfile ENV;
# this block is only for interactive shells.
# Migration guard keys on the system path: volumes created before the /opt
# move already carry an equivalent block, which is left untouched (inert).
PROFILE_FILE="$HOME/.bashrc"
if ! grep -q "/opt/npm-global/bin" "$PROFILE_FILE" 2>/dev/null; then
    cat >> "$PROFILE_FILE" << 'BASHRCEOF'

# OpenCode system toolchain (opencode_env_v2 marker: do not remove)
export PATH="/opt/npm-global/bin:/usr/local/bin:$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
BASHRCEOF
fi

# --- Ensure workspace directory exists and is writable ---
mkdir -p "$HOME/workspace" 2>/dev/null || true
if ! touch "$HOME/workspace/.write-test" 2>/dev/null; then
    # Workspace volume has wrong owner (root). Fix if possible.
    chmod 777 "$HOME/workspace" 2>/dev/null || true
    if ! touch "$HOME/workspace/.write-test" 2>/dev/null; then
        echo "WARNING: ~/workspace/ is not writable (volume permission issue)."
        echo "        Run this on your VPS to fix:"
        echo "        docker exec -u 0 <container> chown opencode:opencode /home/opencode/workspace"
    fi
else
    rm -f "$HOME/workspace/.write-test"
fi

# --- Execute the main command ---
exec "$@"
