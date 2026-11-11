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
    && mkdir -p /opt/npm-global/bin /opt/corepack \
    && chown -R opencode:opencode /home/opencode /opt/npm-global /opt/corepack

# Copy entrypoint to system path (outside home volume)
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# System toolchain locations (outside the home volume so named volumes can
# never shadow them; see ADR-0006). Runtime `npm install -g` still works for
# the opencode user because /opt/npm-global and /opt/corepack stay writable
# by them; ad-hoc global installs land in the image layer and are intentionally
# ephemeral — project-local installs persist via the workspace volume.
ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV COREPACK_HOME=/opt/corepack
ENV PATH=/opt/npm-global/bin:/usr/local/bin:/home/opencode/.npm-global/bin:/home/opencode/.opencode/bin:/home/opencode/.local/bin:$PATH

# Corepack shims go to /usr/local/bin (image layer) and activations to
# $COREPACK_HOME (/opt); a bare `corepack enable` would target a
# HOME-adjacent directory that the home volume shadows.
RUN npm install -g corepack \
    && corepack enable --install-directory /usr/local/bin \
    && corepack prepare pnpm@11.9.0 --activate \
    && corepack prepare yarn@4.17.0 --activate \
    && chown -R opencode:opencode /opt/npm-global /opt/corepack

# RTK binary to /usr/local/bin (image layer). The installer defaults to
# $HOME/.local/bin, so relocate it; `rtk init` (config, home volume) runs in
# the entrypoint on every start instead of here.
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && (test -x /usr/local/bin/rtk || mv /root/.local/bin/rtk /usr/local/bin/rtk) \
    && chmod +x /usr/local/bin/rtk

# Dev-tool binaries to the system npm prefix. MCP/plugin wiring is
# home-volume state and is ensured by the entrypoint, not baked here.
RUN npm install -g @colbymchenry/codegraph tokscale opencode-wakatime \
    && chown -R opencode:opencode /opt/npm-global /opt/corepack

# Switch to opencode user for all subsequent commands
USER opencode
ENV HOME=/home/opencode

# Create config/data directories (home-volume state). ~/.npm-global/bin and
# ~/.local/bin stay on PATH for backward compatibility with pre-existing
# volume contents and manual installs; system tools take precedence via PATH
# order (see ENV above).
RUN mkdir -p ~/.config/opencode ~/.local/share/opencode ~/.npm-global/bin ~/.local/bin

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
