# Agentic Containers

Isolated Docker dev environments with Claude Code, SSH access, PostgreSQL, and common tooling pre-installed. Multiple container types — currently `typescript` (Node.js, pnpm, Playwright) and `dotnet` (.NET SDK 10).

## Prerequisites

- Docker
- An SSH key (`~/.ssh/id_ed25519`) — create one with `ssh-keygen -t ed25519` if needed
- (Optional) [VS Code](https://code.visualstudio.com/) with the Remote - SSH extension

## Setup

1. **Clone this repo and install the CLI:**

   ```bash
   ./install
   ```

   This symlinks `ac` to `/usr/local/bin` so you can use it from anywhere.

2. **Configure environment variables:**

   ```bash
   cp .env.example .env
   ```

   Fill in the required values:

   | Variable | Description |
   |---|---|
   | `GIT_NAME` | Your name for git commits |
   | `GIT_EMAIL` | Your email for git commits |
   | `GH_TOKEN` | GitHub personal access token (for `gh` CLI) |
   | `GITHUB_USERNAME` | Your GitHub username |

   Optional Claude Code auth variables (not needed if using `ac sync-auth` on macOS):

   | Variable | Description |
   |---|---|
   | `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token |
   | `ANTHROPIC_AUTH_TOKEN` | Anthropic auth token |
   | `ANTHROPIC_BASE_URL` | Custom API base URL |

3. **Build a type's image:**

   ```bash
   ac build typescript
   # or:
   ac build dotnet
   ```

   List available types with `ac types`.

   To override `.NET` version: set `DOTNET_VERSION=9.0` in `.env`, or pass `--build-arg DOTNET_VERSION=9.0` after the type.

## Usage

### Create a container

```bash
ac create typescript my-project
# or:
ac create dotnet my-api
```

This auto-assigns an index (1, 2, 3...) that determines port mappings. You can also specify one explicitly:

```bash
ac create typescript my-project 5
```

Port scheme (host port = base + index, base depends on type):

| Service | typescript base | dotnet base |
|---|---|---|
| SSH | 2600 | 2700 |
| HTTP | 3000 | 5000 |
| PostgreSQL | 5600 | 5700 |

After creation, the container is accessible via SSH using its name directly (e.g., `ssh my-project`).

### Connect to a container

**Interactive shell:**

```bash
ac shell my-project
```

Opens a zsh session inside the container. Add `--no-tmux` to skip tmux, or specify a repo to `cd` into:

```bash
ac shell my-project my-repo
```

**VS Code:**

```bash
ac open my-project
ac open my-project my-repo    # open a specific repo
```

**Direct SSH:**

```bash
ssh my-project
```

### Clone repositories

```bash
ac clone my-project git@github.com:org/repo.git
ac clone my-project git@github.com:org/repo1.git git@github.com:org/repo2.git
```

Repos are cloned into `~/workspace/` inside the container. This uses SSH agent forwarding, so your host SSH keys work automatically.

### Run Claude Code

Run a task in the background:

```bash
ac run my-project my-repo "fix the failing tests"
```

Run in the foreground (attached):

```bash
ac run -f my-project my-repo "fix the failing tests"
```

### List containers

```bash
ac list
```

Shows all containers with their status, ports, and workspace contents.

### Other commands

```bash
ac start my-project          # Start a stopped container
ac stop my-project           # Stop a running container
ac delete my-project         # Delete a container (prompts for confirmation)
ac info my-project           # Show container details
ac logs my-project           # Tail container logs
ac setup-ssh my-project      # Regenerate SSH config entry
ac sync-auth                 # Sync Claude Code credentials from macOS Keychain
```

## What's inside each container

Shared by all types:
- Debian (slim) base
- PostgreSQL 18 (localhost:5432, user: `postgres`, password: `postgres`)
- Claude Code CLI
- GitHub CLI, AWS CLI v2, Terraform (override with `TERRAFORM_VERSION`), tmux, zsh + Pure prompt, neovim (upstream), uv, jq, rsync

Type-specific:
- **typescript**: Node.js 22 (default) + 24 via nvm, pnpm/npm, Playwright + Chromium
- **dotnet**: .NET SDK 10 (override with `DOTNET_VERSION`)

## Secrets proxy

API secrets never enter the agent containers. A single `ac-proxy` container (mitmproxy, started automatically by `ac create`) holds the real values; every agent container gets a placeholder such as `GH_TOKEN=ac-placeholder-GH_TOKEN` and sends HTTPS through the proxy, which swaps in the real value — only for the hosts that secret is bound to. A placeholder sent anywhere else stays a placeholder.

To add a secret:

1. Put the real value in `.env`: `export JEV_API_KEY="..."`
2. Bind it to its API host(s) in `proxy/secrets.conf`: `JEV_API_KEY  api.jev.example`
3. `ac proxy restart`, then `ac upgrade <name>` for containers that need the new variable

```bash
ac proxy status     # which secrets the proxy holds, and for which hosts
ac proxy restart    # apply changes to .env / proxy/secrets.conf
ac proxy logs       # one line per injection (never the values)
```

Limits:

- **HTTPS APIs only.** A secret used locally or over another protocol (a database password, a signing key) cannot be protected this way.
- **Use, not possession.** Code in a container can still call the API with the secret's permissions while the proxy is up, so keep keys narrowly scoped.
- **Proxy-aware clients only.** Tools that ignore `HTTPS_PROXY` send the placeholder directly and fail to authenticate. A browser (Playwright) will not trust the proxy's certificate for the bound hosts.
- **Not covered:** the SSH key mounted for git, and Claude credentials from `ac sync-auth`. Claude tokens set in `.env` can be moved behind the proxy by uncommenting their lines in `proxy/secrets.conf`.
- TLS is intercepted only for the hosts in `proxy/secrets.conf`; all other traffic is tunnelled untouched. The CA lives in `~/.config/ac/proxy/` and only its public certificate is mounted into containers.

Set `AC_PROXY=0` in `.env` to turn the proxy off and pass real values into the containers instead.

## Persistent data

- **Workspace** — bind-mounted at `~/.config/ac/agents/<name>/workspace/`
- **Claude credentials** — shared across containers at `~/.config/ac/shared/claude/`
- **AWS config/credentials** — shared across containers at `~/.config/ac/shared/aws/` (mounted as `~/.aws`)
- **Named volumes** — npm-global, pnpm-store, PostgreSQL data, and zsh history survive container recreation

## Customization

Files identical across all types live under `shared/`; `types/<type>/` holds the Dockerfile plus the few files that differ. Each image copies `shared/` first, then its type dir on top — so a per-type file overrides the shared one.

| Change | Where |
|---|---|
| System packages | `apt-get install` block in `types/<type>/Dockerfile` |
| Runtime version | `nvm` lines (typescript) / `DOTNET_VERSION` ARG (dotnet) |
| Services | `types/<type>/scripts/home/startup` (start before sshd) |
| Ports | `ports:` in `types/<type>/type.yaml` |
| Persistent storage | `mounts:` in `types/<type>/type.yaml` |
| Container resources | `resources:` in `types/<type>/type.yaml` |
| Shell config | `shared/configs/home/.zshrc` (all types), `types/<type>/configs/home/.zshenv` (one type) |
| Claude settings | `shared/configs/home/.claude/settings.json` (all types), `types/<type>/configs/home/.claude/CLAUDE.md` (one type) |
| Personal shell additions | `types/<type>/.extras` (see below) |

### Personal shell additions with `.extras`

Create a `types/<type>/.extras` file for shell customizations you don't want to commit (it's gitignored). It's copied into the container at build time and sourced by `.zshrc` on every interactive shell.

```bash
touch types/typescript/.extras
```

Example contents:

```bash
# Custom env vars
export EDITOR=nvim
export MY_API_KEY="..."

# Custom aliases
alias dev="pnpm dev --hostname 0.0.0.0"
alias migrate="pnpm db:migrate"

# Disable tmux auto-attach
# export AC_NO_TMUX=1
```

After editing `.extras`, rebuild the image and recreate containers to pick up the changes:

```bash
ac build
ac upgrade-all
```

### Upgrading containers

After modifying the `Dockerfile`, `type.yaml`, or `.extras`, run:

```bash
ac upgrade-all
```

This rebuilds the image (optional `--no-cache`) and recreates every container in place, preserving volumes, the workspace bind mount, and each container's running/stopped state.

## Notes

- Dev servers inside containers (e.g., Next.js 16+) must bind to `0.0.0.0` to be reachable from the host. Use `--hostname 0.0.0.0` or equivalent.
- Containers share a Docker network (`ac-network`) so they can communicate with each other by name.
- After rebuilding the image (`ac build`), you need to recreate containers to pick up changes.
