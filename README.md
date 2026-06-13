# Agentic Containers

Isolated Docker dev environments for TypeScript/Node.js with Claude Code, SSH access, PostgreSQL, and common tooling pre-installed.

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

3. **Build the Docker image:**

   ```bash
   ac build
   ```

## Usage

### Create a container

```bash
ac create my-project
```

This auto-assigns an index (1, 2, 3...) that determines port mappings. You can also specify one explicitly:

```bash
ac create my-project 5
```

Default port scheme (host port = base + index):

| Service | Base Port | Example (index 1) |
|---|---|---|
| SSH | 2600 | 2601 |
| HTTP | 3000 | 3001 |
| PostgreSQL | 5600 | 5601 |

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

- Debian (slim) base
- Node.js 22 (default) + 24 via `nvm use 24`
- pnpm, npm
- PostgreSQL 18 (localhost:5432, user: `postgres`, password: `postgres`)
- Playwright + Chromium
- Claude Code CLI
- GitHub CLI, tmux, zsh with Pure prompt, uv, jq

## Persistent data

- **Workspace** — bind-mounted at `~/.config/ac/agents/<name>/workspace/`
- **Claude credentials** — shared across containers at `~/.config/ac/shared/claude/`
- **Named volumes** — npm-global, pnpm-store, PostgreSQL data, and zsh history survive container recreation

## Customization

| Change | Where |
|---|---|
| System packages | `apt-get install` block in `Dockerfile` |
| Node version | `nvm install` lines in `Dockerfile` |
| Services | `scripts/home/startup` (start before sshd) |
| Ports | `ports:` in `type.yaml` |
| Persistent storage | `mounts:` in `type.yaml` |
| Container resources | `resources:` in `type.yaml` |
| Shell config | `configs/home/.zshrc` and `.zshenv` |
| Claude settings | `configs/home/.claude/settings.json` and `configs/home/.claude/CLAUDE.md` |
| Personal shell additions | `.extras` (see below) |

### Personal shell additions with `.extras`

Create a `.extras` file in the repo root for shell customizations you don't want to commit (it's gitignored). It's copied into the container at build time and sourced by `.zshrc` on every interactive shell.

```bash
touch .extras
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
