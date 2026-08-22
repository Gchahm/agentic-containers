# Agentic Containers

Standalone Docker container manager for isolated dev environments. Ships with Claude Code, SSH access, PostgreSQL, and common tooling. Supports multiple container types in one repo.

## Project Structure

```
ac                         CLI script (bash) — manages containers via Docker
install                    Symlinks ac to /usr/local/bin
.env.example               Environment variable template (user copies to .env)
.dockerignore              Trims the build context (the repo root — see How It Works)
shared/                    Copied into every type's image first
  configs/home/            → /home/agent/ (.claude/ also staged to /opt/ac/claude)
    .zshrc .gitconfig .ssh/config .config/gh/ .tmux.conf .claude.json
    .claude/settings.json .claude/statusline.sh .claude/hooks/
    .claude/hooks/damage-control/  Guardrail hooks + patterns.yaml (see below)
  scripts/home/            → /usr/local/bin/
    yolo
types/
  <type>/
    Dockerfile             Image definition for this type
    type.yaml              Container config (ports, mounts, resources, required env)
    configs/home/          Copied over shared/ — only what differs per type
      .zshenv .claude/CLAUDE.md
    scripts/home/          Copied over shared/ — only what differs per type
      startup help
    .extras                Optional, gitignored — user shell customizations
```

Current types:
- `typescript` — Node.js 22/24, pnpm, Playwright + Chromium, MongoDB 8.2
- `dotnet` — .NET SDK 10 (override via `DOTNET_VERSION` env or `--build-arg`)
- `go` — Go 1.25.0 on top of the typescript stack (Node 22/24, pnpm, Playwright)

All types share: Debian slim base, PostgreSQL 18, Claude Code CLI, GitHub CLI, AWS CLI v2, Terraform, SSH server, tmux, zsh + Pure, neovim (upstream), uv, rsync.

## How It Works

1. `ac build <type>` — builds the type's Docker image (e.g., `ts-agent`, `dotnet-agent`). The build context is the **repo root** with `-f types/<type>/Dockerfile`, so a Dockerfile can COPY from both `shared/` and `types/<type>/`; `.dockerignore` keeps the context small.
2. `ac create <type> <name> [index]` — runs a container with port mappings derived from the type's `type.yaml` (base + index), mounts volumes, passes env vars from `.env`, installs SSH key, configures host SSH config. Labels the container with `ac_type=<type>`.
3. Container startup — configures git auth, PostgreSQL, Claude Code, then `exec sshd`.
4. User connects via `ac shell`, `ac open` (VS Code), or `ssh <name>` (config installed automatically).

Other subcommands resolve the type from the container's `ac_type` label and default to `typescript` if missing (covers pre-multi-type containers).

## Key Design Decisions

- **Shared configs + per-type overrides** — anything identical across types lives in `shared/`; `types/<type>/configs` and `types/<type>/scripts` hold only files that genuinely differ (today `.zshenv`, `.claude/CLAUDE.md`, `startup`, `help`). Each Dockerfile copies `shared/` first, then its own dir on top, so a per-type file wins by overwriting. Dockerfiles stay per-type — that's where the real divergence is.
- **Single index pool across types** — `ac_index` is unique across the entire `ac_agent` label set. Per-type port ranges (typescript 2600/3000/5600/27000, dotnet 2700/5000/5700, go 2800/8080/5900) avoid clashes within an index.
- **Bind mount for workspace** — persists at `~/.config/ac/agents/<name>/workspace/`.
- **Shared mounts for Claude + nvim + AWS** — all containers share at `~/.config/ac/shared/<name>/` so credentials, nvim config, and plugin data persist across types and containers. `~/.aws` is shared, so one `aws configure` / SSO login covers every container.
- **Named volumes** — language stores (pnpm, nuget), postgres data, zsh history survive container recreation.
- **SSH key bind mount** — host key bind-mounted read-only into container; rotation on host flows through automatically.

## Modifying a Type

- **Add system packages** — edit `apt-get install` in `types/<type>/Dockerfile`
- **Change runtime version** — typescript: nvm lines, `MONGODB_VERSION` ARG (with `MONGODB_KEY_VERSION` for the repo signing key, which lags the release); dotnet: `DOTNET_VERSION` ARG / .env; terraform (all types): `TERRAFORM_VERSION` ARG / .env
- **Add services** — edit `types/<type>/scripts/home/startup` (start before sshd exec)
- **Add ports** — `ports:` in `types/<type>/type.yaml`
- **Add persistent storage** — `mounts:` in `types/<type>/type.yaml`
- **Change container resources** — `resources:` in `types/<type>/type.yaml`
- **Customize shell** — `shared/configs/home/.zshrc` (all types) or `types/<type>/configs/home/.zshenv` (one type)
- **Customize Claude** — `shared/configs/home/.claude/settings.json` (all types) or `types/<type>/configs/home/.claude/CLAUDE.md` (one type)
- **Change guardrails** — `shared/configs/home/.claude/hooks/damage-control/` (see below)

To make a shared file differ for one type, copy it into that type's `configs/home/`
or `scripts/home/` at the same relative path — the per-type COPY runs second and wins.

## Adding a New Type

1. Copy an existing type dir: `cp -r types/typescript types/<newtype>`
2. Edit `types/<newtype>/type.yaml` — set `name`, `image_name`, port `host_base`s (unique across types)
3. Edit `types/<newtype>/Dockerfile` — add `LABEL ac_type=<newtype>`, install the toolchain you need, and repoint the `COPY … types/typescript/…` lines at `types/<newtype>/`
4. `ac build <newtype>` then `ac create <newtype> <name>`

## Guardrails (damage control hooks)

`PreToolUse` hooks that block destructive Bash/Edit/Write calls. They live in this
repo at `shared/configs/home/.claude/hooks/damage-control/` — three Python hook
scripts plus `patterns.yaml` — and reach the container through the normal config
copy (`configs/home/.` → `/home/agent/`, `configs/home/.claude` → `/opt/ac/claude`,
which `startup` syncs into `~/.claude` on every boot). `settings.json` wires them
up via `uv run .../<tool>-tool-damage-control.py`.

Cost, measured warm: ~48 ms before each Bash call, ~32 ms before each Edit/Write
(~13 ms of it is `uv` startup, most of the rest is re-parsing `patterns.yaml` and
recompiling its ~120 regexes every call). The first call in a fresh container is
seconds, since `uv` downloads PyYAML — `~/.cache/uv` is not a named volume, so
that repeats on every container recreation and needs network.

`patterns.yaml` is the tuning surface. Note how the Bash hook matches
`zeroAccessPaths`: a plain substring search over the whole command, so a literal
entry blocks any command whose *text* merely contains it — a commit message, a PR
body, a grep. Prefer globs, and keep that list to things worth the false
positives. Env files are in neither `zeroAccessPaths` nor `readOnlyPaths` — agents
are expected to read and edit them, since these containers hold local dev config,
not production secrets.

Originally vendored from [Gchahm/claude-code-damage-control](https://github.com/Gchahm/claude-code-damage-control)
(`.claude/skills/damage-control/`); the build no longer clones it. Edit the files
here to change behaviour — most tuning is `patterns.yaml`. Keep the `.py` files
executable.
