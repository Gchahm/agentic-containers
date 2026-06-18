# Agentic Containers

Standalone Docker container manager for isolated dev environments. Ships with Claude Code, SSH access, PostgreSQL, and common tooling. Supports multiple container types in one repo.

## Project Structure

```
ac                         CLI script (bash) — manages containers via Docker
install                    Symlinks ac to /usr/local/bin
.env.example               Environment variable template (user copies to .env)
types/
  <type>/
    Dockerfile             Image definition for this type
    type.yaml              Container config (ports, mounts, resources, required env)
    configs/home/          Files copied into /home/agent/ at build time
      .zshenv .zshrc .gitconfig .ssh/config .config/gh/ .claude/ .tmux.conf
    scripts/home/          Scripts available inside container
      startup help yolo
    .extras                Optional, gitignored — user shell customizations
```

Current types:
- `typescript` — Node.js 22/24, pnpm, Playwright + Chromium
- `dotnet` — .NET SDK 10 (override via `DOTNET_VERSION` env or `--build-arg`)

Both types share: Debian slim base, PostgreSQL 18, Claude Code CLI, GitHub CLI, SSH server, tmux, zsh + Pure, neovim (upstream), uv, cloudflared, rsync.

## How It Works

1. `ac build <type>` — builds the type's Docker image (e.g., `ts-agent`, `dotnet-agent`).
2. `ac create <type> <name> [index]` — runs a container with port mappings derived from the type's `type.yaml` (base + index), mounts volumes, passes env vars from `.env`, installs SSH key, configures host SSH config. Labels the container with `ac_type=<type>`.
3. Container startup — configures git auth, PostgreSQL, Claude Code, optional cloudflared, then `exec sshd`.
4. User connects via `ac shell`, `ac open` (VS Code), or `ssh <name>` (config installed automatically).

Other subcommands resolve the type from the container's `ac_type` label and default to `typescript` if missing (covers pre-multi-type containers).

## Key Design Decisions

- **Per-type Dockerfile, configs, scripts** — duplication keeps each type self-contained. No shared base today; refactor later if drift becomes painful.
- **Single index pool across types** — `ac_index` is unique across the entire `ac_agent` label set. Per-type port ranges (typescript 2600/3000/5600, dotnet 2700/5000/5700) avoid clashes within an index.
- **Bind mount for workspace** — persists at `~/.config/ac/agents/<name>/workspace/`.
- **Shared mounts for Claude + nvim** — all containers share at `~/.config/ac/shared/<name>/` so credentials, nvim config, and plugin data persist across types and containers.
- **Named volumes** — language stores (pnpm, nuget), postgres data, zsh history survive container recreation.
- **SSH key bind mount** — host key bind-mounted read-only into container; rotation on host flows through automatically.

## Modifying a Type

- **Add system packages** — edit `apt-get install` in `types/<type>/Dockerfile`
- **Change runtime version** — typescript: nvm lines; dotnet: `DOTNET_VERSION` ARG / .env
- **Add services** — edit `types/<type>/scripts/home/startup` (start before sshd exec)
- **Add ports** — `ports:` in `types/<type>/type.yaml`
- **Add persistent storage** — `mounts:` in `types/<type>/type.yaml`
- **Change container resources** — `resources:` in `types/<type>/type.yaml`
- **Customize shell** — `types/<type>/configs/home/.zshrc` and `.zshenv`
- **Customize Claude** — `types/<type>/configs/home/.claude/settings.json` and `.claude/CLAUDE.md`

## Adding a New Type

1. Copy an existing type dir: `cp -r types/typescript types/<newtype>`
2. Edit `types/<newtype>/type.yaml` — set `name`, `image_name`, port `host_base`s (unique across types)
3. Edit `types/<newtype>/Dockerfile` — add `LABEL ac_type=<newtype>`, install the toolchain you need
4. `ac build <newtype>` then `ac create <newtype> <name>`
