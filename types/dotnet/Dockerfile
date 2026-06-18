ARG DEBIAN_VERSION=trixie-20250908-slim

FROM debian:${DEBIAN_VERSION}

LABEL ac_agent=true
LABEL ac_type=dotnet

# Install all dependencies in one layer
RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    inotify-tools \
    jq \
    less \
    libicu76 \
    locales \
    lsb-release \
    make \
    nano \
    openssh-client \
    openssh-server \
    rsync \
    sudo \
    tini \
    vim \
    tmux \
    unzip \
    wget \
    zsh \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install PostgreSQL 17 + TimescaleDB, GitHub CLI, RabbitMQ
RUN set -eux; \
    # PostgreSQL 17 (pgdg)
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
      gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list; \
    # GitHub CLI
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
      gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    # TimescaleDB (using bookworm repo; package is OS-independent, works on trixie)
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | \
      gpg --dearmor -o /usr/share/keyrings/timescaledb-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/timescaledb-keyring.gpg] https://packagecloud.io/timescale/timescaledb/debian/ bookworm main" \
      > /etc/apt/sources.list.d/timescaledb.list; \
    apt-get update && apt-get install -y \
      postgresql-17 postgresql-client-17 \
      timescaledb-2-postgresql-17 \
      gh \
      rabbitmq-server; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/run/postgresql && chown postgres:postgres /var/run/postgresql; \
    # Configure PostgreSQL: network access + TimescaleDB preload
    echo "listen_addresses = '*'" >> /etc/postgresql/17/main/postgresql.conf; \
    echo "shared_preload_libraries = 'timescaledb'" >> /etc/postgresql/17/main/postgresql.conf; \
    echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/17/main/pg_hba.conf; \
    # RabbitMQ: enable management plugin, point data/log dirs at /data/rabbitmq
    rabbitmq-plugins enable --offline rabbitmq_management; \
    mkdir -p /data/rabbitmq/mnesia /data/rabbitmq/log /data/redis; \
    chown -R agent:agent /data; \
    printf 'NODENAME=rabbit@localhost\nMNESIA_BASE=/data/rabbitmq/mnesia\nLOG_BASE=/data/rabbitmq/log\n' \
      > /etc/rabbitmq/rabbitmq-env.conf

# Install latest Neovim from upstream
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) nvim_arch="x86_64" ;; \
      arm64) nvim_arch="arm64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz" \
      -o /tmp/nvim.tar.gz; \
    tar -xzf /tmp/nvim.tar.gz -C /opt; \
    ln -s "/opt/nvim-linux-${nvim_arch}/bin/nvim" /usr/local/bin/nvim; \
    rm /tmp/nvim.tar.gz

# Install cloudflared (for Cloudflare Tunnel webhook ingress)
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb" \
      -o /tmp/cloudflared.deb; \
    dpkg -i /tmp/cloudflared.deb; \
    rm /tmp/cloudflared.deb

# Install Dragonfly (Redis-compatible in-memory store)
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) df_arch="x86_64" ;; \
      arm64) df_arch="aarch64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/dragonflydb/dragonfly/releases/latest/download/dragonfly-${df_arch}.tar.gz" \
      -o /tmp/dragonfly.tar.gz; \
    tar -xzf /tmp/dragonfly.tar.gz -C /tmp; \
    install -m 755 "/tmp/dragonfly-${df_arch}" /usr/local/bin/dragonfly; \
    rm -rf /tmp/dragonfly.tar.gz "/tmp/dragonfly-${df_arch}"

# Install .NET SDK (channel-based, defaults to 10.0)
ARG DOTNET_VERSION=10.0
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="/usr/share/dotnet:/home/agent/.dotnet/tools:${PATH}"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
RUN set -eux; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh; \
    chmod +x /tmp/dotnet-install.sh; \
    /tmp/dotnet-install.sh --channel "${DOTNET_VERSION}" --install-dir /usr/share/dotnet; \
    rm /tmp/dotnet-install.sh; \
    chmod -R a+rx /usr/share/dotnet

# Create agent user with targeted sudo permissions
RUN useradd -m -s /bin/zsh -u 1000 agent && \
    echo "agent ALL=(ALL) NOPASSWD: /usr/sbin/sshd, /usr/bin/pg_ctlcluster, /usr/bin/pg_isready, /usr/bin/psql, /usr/bin/chown, /usr/sbin/rabbitmq-server, /usr/sbin/rabbitmqctl, /usr/sbin/rabbitmq-plugins" \
      > /etc/sudoers.d/agent && \
    chmod 0440 /etc/sudoers.d/agent && \
    chown -R agent:agent /data /var/lib/rabbitmq /etc/rabbitmq

# Make /etc/environment writable by agent (for persisting env vars through SSH sessions)
RUN chmod 666 /etc/environment

# Configure SSH server and seed GitHub host keys
RUN mkdir -p /run/sshd /etc/ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    printf "\nAllowUsers agent\nX11Forwarding no\nAllowTcpForwarding yes\nAllowAgentForwarding yes\nPerSourcePenalties no\n" >> /etc/ssh/sshd_config && \
    ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts 2>/dev/null || true

# Create staging directory for bind-mounted paths
RUN mkdir -p /opt/ac && chown agent:agent /opt/ac

USER agent
WORKDIR /home/agent

# Pre-create dirs that bind mounts and Claude installer expect to be agent-owned
# (Docker auto-creates parent dirs of mounts as root, which blocks ~/.local/share writes)
RUN mkdir -p /home/agent/.zsh /home/agent/.local/bin /home/agent/.local/share && \
    git clone https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# --- Everything below here changes frequently and rebuilds fast ---

# Install Claude Code Damage Control hooks from git
RUN git clone --depth 1 https://github.com/Gchahm/claude-code-damage-control.git /tmp/damage-control && \
    mkdir -p /home/agent/.claude/hooks/damage-control /opt/ac/claude/hooks/damage-control && \
    cp /tmp/damage-control/.claude/skills/damage-control/hooks/damage-control-python/bash-tool-damage-control.py \
       /tmp/damage-control/.claude/skills/damage-control/hooks/damage-control-python/edit-tool-damage-control.py \
       /tmp/damage-control/.claude/skills/damage-control/hooks/damage-control-python/write-tool-damage-control.py \
       /home/agent/.claude/hooks/damage-control/ && \
    cp /tmp/damage-control/.claude/skills/damage-control/patterns.yaml \
       /home/agent/.claude/hooks/damage-control/ && \
    cp -r /home/agent/.claude/hooks/damage-control/. /opt/ac/claude/hooks/damage-control/ && \
    rm -rf /tmp/damage-control

# Copy all home configs (shell, git, ssh, gh, claude, tmux)
COPY --chown=agent:agent configs/home/. /home/agent/
RUN chmod 700 /home/agent/.ssh && chmod 600 /home/agent/.ssh/config

# Stage Claude configs (copied at startup due to bind mount)
COPY --chown=agent:agent configs/home/.claude /opt/ac/claude

# Copy .extras if it exists
COPY --chown=agent:agent .extra[s] /home/agent/

# Copy user scripts (startup, help, yolo)
COPY --chown=agent:agent scripts/home/. /usr/local/bin/

WORKDIR /home/agent/workspace

EXPOSE 22 5000 5432 5672 15672 6379
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/startup"]
