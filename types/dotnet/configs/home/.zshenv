# PATH and environment setup for all shell types (interactive and non-interactive)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export USER=$(whoami)

# Local bin (uv, etc.)
. "$HOME/.local/bin/env" 2>/dev/null || true

# .NET SDK
export DOTNET_ROOT=/usr/share/dotnet
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
case ":$PATH:" in
  *":$DOTNET_ROOT:"*) ;;
  *) export PATH="$DOTNET_ROOT:$PATH" ;;
esac

# dotnet global tools
case ":$PATH:" in
  *":$HOME/.dotnet/tools:"*) ;;
  *) export PATH="$HOME/.dotnet/tools:$PATH" ;;
esac
