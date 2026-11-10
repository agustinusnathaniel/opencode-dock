# OpenCode v2 remote server, extended from the official image.
#
# Base (Alpine + opencode binary) is owned by upstream; this layer adds only
# the agent toolchain: git/gh/ssh, Node.js (Alpine apk), pnpm/yarn via
# Corepack, and the dev tools (codegraph, tokscale, wakatime, rtk).
# Version pin = image tag (single source; see docker-compose.yaml).
ARG OPENCODE_VERSION=2.2.7
FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}

USER root

# Agent toolchain (Alpine equivalents of the former Debian set)
RUN apk add --no-cache \
    bash curl ca-certificates git github-cli openssh-client \
    nodejs npm procps xdg-utils \
    && rm -rf /var/cache/apk/*

# Non-root user (base image runs as root)
RUN adduser -D -s /bin/bash -h /home/opencode opencode \
    && mkdir -p /home/opencode/workspace \
    && chown -R opencode:opencode /home/opencode

# Copy entrypoint to system path (outside home volume)
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Switch to opencode user for all subsequent commands
USER opencode
ENV HOME=/home/opencode
ENV NPM_CONFIG_PREFIX=/home/opencode/.npm-global
ENV PATH=/home/opencode/.npm-global/bin:/home/opencode/.opencode/bin:/home/opencode/.local/bin:$PATH

# Enable Corepack for pnpm and yarn (Alpine's nodejs package omits the
# corepack shim, so bootstrap it via npm; pnpm/yarn versions stay pinned)
RUN npm install -g corepack \
    && corepack enable \
    && corepack prepare pnpm@11.9.0 --activate \
    && corepack prepare yarn@4.17.0 --activate

# Install RTK (Rust Token Killer)
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && ~/.local/bin/rtk init -g --opencode 2>/dev/null || true

# Install CodeGraph, Tokscale, and opencode-wakatime
RUN --mount=type=cache,target=/home/opencode/.npm,uid=1000,gid=1000,sharing=locked \
    npm install -g @colbymchenry/codegraph tokscale opencode-wakatime \
    && codegraph install --yes --target=opencode 2>/dev/null || true

# Create config/data directories
RUN mkdir -p ~/.config/opencode ~/.local/share/opencode

WORKDIR /home/opencode

EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f -u "opencode:${OPENCODE_PASSWORD:-$OPENCODE_SERVER_PASSWORD}" http://localhost:4096/api/info

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# Absolute image path (not bare `opencode`): an upgraded opencode-home volume
# may still contain a previous ~/.opencode/bin/opencode that shadows PATH and
# cannot execute on this base (e.g. v1 glibc binary on Alpine/musl). The server
# must always be the image-pinned binary.
CMD ["/usr/local/bin/opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
