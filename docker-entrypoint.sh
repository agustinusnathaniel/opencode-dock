#!/bin/bash
# This file must live outside $HOME (not shadowed by opencode-home volume)
set -e

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
    mkdir -p "$HOME/.wakatime"
    cat > "$HOME/.wakatime.cfg" << EOF
[settings]
api_key = ${WAKATIME_API_KEY}
EOF
fi

# --- Source fnm and bun for interactive shells ---
# Create .bashrc with proper PATH for interactive use
cat > "$HOME/.bashrc" << 'BASHRCEOF'
export PATH="$HOME/.opencode/bin:/opt/fnm/aliases/default/bin:$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
BASHRCEOF

# --- Ensure workspace directory exists ---
mkdir -p "$HOME/workspace"

# --- Execute the main command ---
exec "$@"
