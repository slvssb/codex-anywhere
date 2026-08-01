FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Codex Anywhere" \
      org.opencontainers.image.description="Persistent Railway native SSH environment for OpenAI Codex"

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash
ENV PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base system packages plus external repos for Node.js and GitHub CLI.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini bubblewrap git curl wget vim nano jq tmux zip unzip \
    ripgrep fd-find tree less sudo procps lsof \
    ca-certificates gnupg python3 python3-pip python3-venv \
    build-essential libicu74 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Create the unprivileged runtime user. Passwordless sudo lets the user update
# the environment later without rebuilding the image.
RUN useradd -m -s /bin/bash user \
    && printf '%s\n' "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/codex-anywhere \
    && chmod 0440 /etc/sudoers.d/codex-anywhere \
    && mkdir -p /home/user/.codex \
    && mkdir -p /opt/default-codex \
    && chown -R user:user /home/user/.codex /opt/default-codex

RUN curl -fsSL https://railway.com/install.sh | bash -s -- --yes --bin-dir /usr/local/bin \
    && npm install -g @openai/codex@latest \
    && runuser -u user -- env HOME=/home/user PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" railway setup agent -y \
    && cp -a /home/user/.codex/. /opt/default-codex/ \
    && chown -R user:user /opt/default-codex

ENV CODEX_HOME=/data/.codex
ENV NPM_CONFIG_PREFIX=/home/user/.local
ENV PATH="/home/user/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

COPY entrypoint.sh /usr/local/bin/codex-anywhere-entrypoint
COPY codex-wrapper.sh /usr/local/bin/codex
RUN chmod +x /usr/local/bin/codex-anywhere-entrypoint /usr/local/bin/codex

USER user
WORKDIR /tmp

RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD grep -qs " /data " /proc/mounts || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/codex-anywhere-entrypoint"]
