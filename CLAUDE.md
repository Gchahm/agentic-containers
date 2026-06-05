# Agentic Containers

Standalone Docker container manager for TypeScript/Node.js development. Provides isolated dev environments with Claude Code, SSH access, and common tooling pre-installed.

## Project Structure

```
ac                         CLI script (bash) — manages containers via Docker
install                    Symlinks ac to /usr/local/bin
type.yaml                  Container configuration (ports, mounts, resources, required env vars)
Dockerfile                 Container image definition
.env.example               Environment variable template (user copies to .env)
configs/home/              Files copied into /home/agent/ at build time
  .zshenv                  PATH setup for all shell types (non-interactive included)
  .zshrc                   Interactive shell config (aliases, prompt, tmux)
  .gitconfig               Git identity (templated — {GIT_NAME}, {GIT_EMAIL} replaced at startup)
  .ssh/config              SSH client config (GitHub host pinning)
  .config/gh/              GitHub CLI config (templated — {GITHUB_USERNAME} replaced at startup)
  .claude.json             Claude Code onboarding state
  .claude/settings.json    Claude Code settings (hooks, model, statusline)
  .claude/CLAUDE.md        Instructions for Claude inside the container
  .claude/statusline.sh    Status bar script for Claude Code
  .claude/hooks/           Claude Code event hooks (start, stop, notification, etc.)
  .tmux.conf               Tmux configuration
scripts/root/startup       Container entrypoint (runs as root, sets up postgres, ssh, auth, then exec sshd)
scripts/home/              User commands available inside container (help, yolo)
```

## Container Stack

- Debian (slim) base
- Node.js 22 (default) + 24 via nvm
- pnpm, npm
- PostgreSQL 18
- Playwright + Chromium
- Claude Code CLI (installed at startup if missing)
- GitHub CLI, SSH server, tmux, zsh + Pure prompt, uv, jq

## How It Works

1. `ac build` — builds Docker image `ts-agent` from the Dockerfile
2. `ac create <name> [index]` — creates a container with port mappings derived from type.yaml (base + index), mounts volumes, passes env vars from .env, installs SSH key, configures SSH config on host
3. Container startup (`scripts/root/startup`) — configures git auth, PostgreSQL, Claude Code, pnpm, then runs sshd as the main process
4. User connects via `ac shell`, `ac open` (VS Code), or direct SSH

## Key Design Decisions

- **No project-specific init** — this is a generic template. Users clone their own repos after container creation.
- **Single type** — no types/ directory. The root IS the type. Customize type.yaml directly.
- **Startup runs as root** — needed for PostgreSQL and sshd. Switches to agent user for all interactive work.
- **Bind mount for workspace** — persists at `~/.config/ac/agents/<name>/workspace/`
- **Shared mount for .claude/** — all containers share Claude credentials at `~/.config/ac/shared/claude/`
- **Named volumes** — npm-global, pnpm-store, postgres data, zsh history survive container recreation

## Port Scheme (type.yaml)

Host port = host_base + container index. Default bases:
- SSH: 2600 (container 22)
- HTTP: 3000 (container 3000)
- PostgreSQL: 5600 (container 5432)

## Modifying the Template

- **Add system packages** — edit the `apt-get install` block in Dockerfile
- **Change Node version** — edit the nvm install lines in Dockerfile
- **Add services** — edit `scripts/root/startup` (start before sshd exec)
- **Add ports** — add entries to `ports:` in type.yaml
- **Add persistent storage** — add entries to `mounts:` in type.yaml
- **Change container resources** — edit `resources:` in type.yaml
- **Customize shell** — edit `configs/home/.zshrc` and `.zshenv`
- **Customize Claude** — edit `configs/home/.claude/settings.json` and `configs/home/.claude/CLAUDE.md`
