ARG DEBIAN_VERSION=trixie-20250908-slim

FROM debian:${DEBIAN_VERSION}

LABEL ac_agent=true

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
    locales \
    lsb-release \
    make \
    nano \
    openssh-client \
    openssh-server \
    sudo \
    tini \
    vim \
    neovim \
    tmux \
    unzip \
    wget \
    zsh \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install PostgreSQL 18 and GitHub CLI
RUN set -eux; \
    # PostgreSQL 18
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
    # Install all
    apt-get update && apt-get install -y \
      postgresql-18 postgresql-client-18 \
      gh; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/run/postgresql && chown postgres:postgres /var/run/postgresql

# Create agent user with targeted sudo permissions
RUN useradd -m -s /bin/zsh -u 1000 agent && \
    echo "agent ALL=(ALL) NOPASSWD: /usr/sbin/sshd, /usr/bin/pg_ctlcluster, /usr/bin/pg_isready, /usr/bin/psql, /usr/bin/chown" \
      > /etc/sudoers.d/agent && \
    chmod 0440 /etc/sudoers.d/agent

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

# Copy all home configs
COPY --chown=agent:agent configs/home/. /home/agent/

# Fix SSH permissions
RUN chmod 700 /home/agent/.ssh && chmod 600 /home/agent/.ssh/config

# Stage Claude configs (copied at startup due to bind mount)
COPY --chown=agent:agent configs/home/.claude /opt/ac/claude

# Copy .extras if it exists
COPY --chown=agent:agent .extra[s] /home/agent/

# Copy user scripts
COPY --chown=agent:agent scripts/home/. /usr/local/bin/

# Install nvm with Node 22 (LTS default) and Node 24
ENV NVM_DIR="/home/agent/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install 22 && \
    nvm install 24 && \
    nvm alias default 22 && \
    ln -s "$(dirname "$(nvm which default)")" "$NVM_DIR/default-bin"

# Setup npm global directory, pnpm, and pure prompt
RUN mkdir -p /home/agent/.npm-global /home/agent/.pnpm-store /home/agent/.zsh && \
    . "$NVM_DIR/nvm.sh" && \
    npm config set prefix '/home/agent/.npm-global' && \
    npm config delete prefix && \
    wget -qO- https://get.pnpm.io/install.sh | ENV="$HOME/.zshrc" SHELL="$(which zsh)" zsh - && \
    git clone https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"

ENV PATH="/home/agent/.nvm/default-bin:/home/agent/.npm-global/bin:${PATH}"

# Install uv (Python package manager, useful for MCP tools)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

USER root

# Install Playwright system dependencies and Chromium
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
ENV PLAYWRIGHT_MCP_SANDBOX=false
ENV PLAYWRIGHT_MCP_OUTPUT_DIR=.playwright-cli
RUN . "/home/agent/.nvm/nvm.sh" && nvm use 22 && \
    npm install -g @playwright/cli@latest && \
    node "$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js" install --with-deps chromium && \
    chmod -R 777 /opt/playwright && \
    mkdir -p /opt/google/chrome && \
    ln -s "$(find /opt/playwright -name chrome -path '*/chromium-*/chrome' -type f | head -1)" /opt/google/chrome/chrome

# Install Playwright CLI skills and stage them
USER agent
RUN . "$NVM_DIR/nvm.sh" && nvm use 22 && \
    playwright-cli install --skills && \
    cp -r /home/agent/.claude/skills /opt/ac/claude/skills
USER root

# Install Claude Code Damage Control hooks from git
USER agent
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
USER root

# Copy root scripts
COPY --chmod=0755 scripts/root/. /usr/local/bin/

WORKDIR /home/agent/workspace

EXPOSE 22 3000 5432

USER root
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/startup"]
