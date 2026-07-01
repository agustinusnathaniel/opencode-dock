FROM debian:bookworm-slim

# Install system packages and GitHub CLI (stable, rarely changes)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git openssh-client \
    unzip xz-utils build-essential procps xdg-utils \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash opencode

# Copy entrypoint to system path (outside home volume)
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Switch to opencode user for all subsequent commands
USER opencode
ENV HOME=/home/opencode

# Install Node.js via FNM (system-wide, outside home volume)
ENV FNM_DIR=/opt/fnm
RUN mkdir -p ${FNM_DIR} \
    && curl -fsSL https://github.com/Schniz/fnm/releases/download/v1.38.1/fnm-linux.zip -o /tmp/fnm-linux.zip \
    && unzip /tmp/fnm-linux.zip -d ${FNM_DIR} \
    && rm /tmp/fnm-linux.zip \
    && ${FNM_DIR}/fnm install 24 \
    && ${FNM_DIR}/fnm default 24
ENV PATH=/opt/fnm/aliases/default/bin:$PATH

# Enable Corepack for pnpm and yarn
RUN corepack enable \
    && corepack prepare pnpm@11.9.0 --activate \
    && corepack prepare yarn@4.17.0 --activate

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH=/home/opencode/.bun/bin:$PATH

# Install OpenCode (version bumps only bust cache from here)
ARG OPENCODE_VERSION=1.17.13
RUN curl -fsSL https://opencode.ai/install | bash -s -- ${OPENCODE_VERSION}
ENV PATH=/home/opencode/.opencode/bin:$PATH

# Install RTK (Rust Token Killer)
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && ~/.local/bin/rtk init -g --opencode 2>/dev/null || true
ENV PATH=/home/opencode/.local/bin:$PATH

# Install CodeGraph, Tokscale, and opencode-wakatime
RUN --mount=type=cache,target=/home/opencode/.npm,uid=1000,gid=1000,sharing=locked \
    npm install -g @colbymchenry/codegraph tokscale opencode-wakatime

# Create config/data directories
RUN mkdir -p ~/.config/opencode ~/.local/share/opencode

WORKDIR /home/opencode

EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:4096/global/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
