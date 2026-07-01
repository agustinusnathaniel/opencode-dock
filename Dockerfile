ARG OPENCODE_VERSION=1.17.13

FROM debian:bookworm-slim

ARG OPENCODE_VERSION

# Install system packages and GitHub CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git openssh-client \
    unzip xz-utils build-essential procps \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash opencode

# Copy entrypoint and make executable
COPY docker-entrypoint.sh /home/opencode/docker-entrypoint.sh
RUN chmod +x /home/opencode/docker-entrypoint.sh

# Switch to opencode user for all subsequent commands
USER opencode
ENV HOME=/home/opencode

# Install Node.js via FNM
RUN mkdir -p ~/.local/share/fnm \
    && curl -fsSL https://github.com/Schniz/fnm/releases/download/v1.38.1/fnm-linux.zip -o /tmp/fnm-linux.zip \
    && unzip /tmp/fnm-linux.zip -d ~/.local/share/fnm \
    && rm /tmp/fnm-linux.zip \
    && ~/.local/share/fnm/fnm install 22 \
    && ~/.local/share/fnm/fnm default 22
ENV PATH=/home/opencode/.local/share/fnm/aliases/default/bin:$PATH

# Enable Corepack for pnpm and yarn (needs Node.js on PATH)
RUN corepack enable \
    && corepack prepare pnpm@11.9.0 --activate \
    && corepack prepare yarn@4.17.0 --activate

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH=/home/opencode/.bun/bin:$PATH

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install | bash -s -- ${OPENCODE_VERSION}
ENV PATH=/home/opencode/.opencode/bin:$PATH

# Install RTK (Rust Token Killer) - compresses command output, saves 60-90% tokens
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && ~/.local/bin/rtk init -g --opencode 2>/dev/null || true
ENV PATH=/home/opencode/.local/bin:$PATH

# Install CodeGraph - code intelligence / knowledge graph
RUN npm install -g @colbymchenry/codegraph

# Create config/data directories
RUN mkdir -p ~/.config/opencode ~/.local/share/opencode

WORKDIR /home/opencode

EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:4096/global/health || exit 1

ENTRYPOINT ["/home/opencode/docker-entrypoint.sh"]
CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
