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

# Toolchain version pins. Defaults below are the single source of truth, so a
# plain `docker build` (or an env that sets none of these) still produces the
# known-good image; override any of them via Coolify env / compose build args
# to bump without editing this file. The build smoke test at the bottom
# executes every binary, so a bad pin fails the build instead of shipping.
ARG PNPM_VERSION=12.19.0
ARG YARN_VERSION=4.18.1
ARG RTK_VERSION=v1.2.0
ARG CODEGRAPH_VERSION=1.6.2
ARG TOKSCALE_VERSION=4.21.0
ARG WAKATIME_VERSION=1.4.0
ARG CLAUDE_CODE_VERSION=2.1.322

# System toolchain locations (outside the home volume so named volumes can
# never shadow them; see ADR-0006). Runtime `npm install -g` still works for
# the opencode user because /opt/npm-global and /opt/corepack stay writable
# by them; ad-hoc global installs land in the image layer and are intentionally
# ephemeral — project-local installs persist via the workspace volume.
ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV COREPACK_HOME=/opt/corepack
ENV PATH=/opt/npm-global/bin:/usr/local/bin:/home/opencode/.opencode/bin:/home/opencode/.local/bin:$PATH

# Corepack shims go to /usr/local/bin (image layer) and activations to
# $COREPACK_HOME (/opt); a bare `corepack enable` would target a
# HOME-adjacent directory that the home volume shadows.
RUN npm install -g corepack \
    && corepack enable --install-directory /usr/local/bin \
    && corepack prepare pnpm@${PNPM_VERSION} --activate \
    && corepack prepare yarn@${YARN_VERSION} --activate \
    && chown -R opencode:opencode /opt/npm-global /opt/corepack

# RTK binary to /usr/local/bin (image layer). The installer defaults to
# $HOME/.local/bin, so relocate it; `rtk init` (config, home volume) runs in
# the entrypoint on every start instead of here.
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | RTK_VERSION=${RTK_VERSION} sh \
    && (test -x /usr/local/bin/rtk || mv /root/.local/bin/rtk /usr/local/bin/rtk) \
    && chmod +x /usr/local/bin/rtk

# Dev-tool binaries to the system npm prefix. MCP/plugin wiring is
# home-volume state and is ensured by the entrypoint, not baked here.
# Claude Code is pinned exact like pnpm/yarn; it ships musl builds
# (@anthropic-ai/claude-code-linux-x64-musl), so no wrapper is needed —
# the build smoke test below proves it by executing the binary.
RUN npm install -g @colbymchenry/codegraph@${CODEGRAPH_VERSION} tokscale@${TOKSCALE_VERSION} opencode-wakatime@${WAKATIME_VERSION} @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && chown -R opencode:opencode /opt/npm-global /opt/corepack

# CodeGraph's npm launcher execs a vendored glibc-linked Node that cannot run
# on musl (Alpine: "cannot execute: required file not found"). The bundle's JS
# runs fine on the image's system Node 24 (verified), so replace the bin shim
# with a wrapper that resolves the platform bundle at runtime. The shell
# installer (install.sh) is not an alternative: it fetches the same glibc
# bundle and installs into $HOME (the shadowed volume) unpinned by default.
RUN rm -f /opt/npm-global/bin/codegraph && printf '%s\n' \
    '#!/bin/sh' \
    '# codegraph ships a glibc-linked node that cannot execute on musl;' \
    '# run the bundle JS on the image system node instead.' \
    'for d in /opt/npm-global/lib/node_modules/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-*/; do' \
    '  if [ -f "$d/lib/dist/bin/codegraph.js" ]; then' \
    '    exec /usr/bin/node "$d/lib/dist/bin/codegraph.js" "$@"' \
    '  fi' \
    'done' \
    'echo "codegraph: platform bundle not found under @colbymchenry" >&2' \
    'exit 1' \
    > /opt/npm-global/bin/codegraph \
    && chmod +x /opt/npm-global/bin/codegraph

# Build-time smoke test: every toolchain binary must execute. A tool that
# installs but cannot run (e.g. a musl-incompatible bundle) fails the build
# instead of shipping a broken image.
RUN pnpm --version \
    && yarn --version \
    && codegraph --version \
    && tokscale --version \
    && rtk --version \
    && claude --version \
    && test -d /opt/npm-global/lib/node_modules/opencode-wakatime

# Switch to opencode user for all subsequent commands
USER opencode
ENV HOME=/home/opencode

# Create config/data directories (home-volume state). ~/.opencode/bin is
# opencode's own self-update location and ~/.local/bin is the conventional
# user bin dir; both stay on PATH after the system entries. The obsolete
# ~/.npm-global prefix is intentionally absent: globals live in /opt.
RUN mkdir -p ~/.config/opencode ~/.local/share/opencode ~/.local/bin

WORKDIR /home/opencode

EXPOSE 4096

# No Dockerfile HEALTHCHECK: docker-compose.yaml defines the single healthcheck
# (compose overrides the image value whenever both exist), so one definition
# lives there and none can drift.

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# Absolute image path (not bare `opencode`): an upgraded opencode-home volume
# may still contain a previous ~/.opencode/bin/opencode that shadows PATH and
# cannot execute on this base (e.g. v1 glibc binary on Alpine/musl). The server
# must always be the image-pinned binary.
CMD ["/usr/local/bin/opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
