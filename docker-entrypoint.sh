#!/bin/bash
set -e

# --- SSH key setup ---
if [ -n "$SSH_PRIVATE_KEY" ]; then
    mkdir -p "$HOME/.ssh"
    printf '%s\n' "$SSH_PRIVATE_KEY" | sed 's/\\n/\n/g' > "$HOME/.ssh/id_ed25519"
    chmod 600 "$HOME/.ssh/id_ed25519"

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

    # Ensure .ssh directory has correct permissions
    chmod 700 "$HOME/.ssh"
fi

# --- Git config ---
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi
git config --global core.editor "vim"

# --- Source fnm and bun for interactive shells ---
# Create .bashrc with proper PATH for interactive use
cat > "$HOME/.bashrc" << 'BASHRCEOF'
export PATH="$HOME/.opencode/bin:$HOME/.local/share/fnm/aliases/default/bin:$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
BASHRCEOF

# --- Execute the main command ---
exec "$@"
