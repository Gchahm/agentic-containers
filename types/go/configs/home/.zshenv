# PATH and environment setup for all shell types (interactive and non-interactive)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
export USER=$(whoami)

# Local bin (uv, etc.)
. "$HOME/.local/bin/env" 2>/dev/null || true

# nvm - add node/npm to PATH without sourcing nvm.sh (which is slow)
export NVM_DIR="$HOME/.nvm"
export PATH="$HOME/.nvm/default-bin:$PATH"

# npm global
export PATH="/home/agent/.npm-global/bin:${PATH}"

# pnpm
export PNPM_HOME="/home/agent/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# Go
export GOPATH="$HOME/go"
export GOMODCACHE="$HOME/go/pkg/mod"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"
