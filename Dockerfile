ARG OPENCODE_VERSION=1.17.13

FROM debian:bookworm-slim

ARG OPENCODE_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash opencode
USER opencode
WORKDIR /home/opencode
ENV HOME=/home/opencode

RUN curl -fsSL https://opencode.ai/install | bash -s -- ${OPENCODE_VERSION}
ENV PATH=/home/opencode/.opencode/bin:$PATH

EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:4096/doc || exit 1

CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]