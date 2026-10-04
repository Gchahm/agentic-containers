# Go + TypeScript Development Container

## Environment

- **Go**: 1.25.0 (`/usr/local/go`, `GOPATH=~/go`)
- **Node.js**: 22 (default) and 24 available via `nvm use 24`
- **Package managers**: pnpm (preferred), npm
- **PostgreSQL**: localhost:5432 (user: postgres, password: postgres)
- **Playwright**: Available for browser automation

## Quick Navigation

- `w` -- ~/workspace

## PostgreSQL

PostgreSQL starts automatically on container boot. Connect with:
- Host: localhost
- Port: 5432
- User: postgres
- Password: postgres

Create a database: `sudo -u postgres psql -c "CREATE DATABASE myapp;"`

## Commands

- `yolo` -- Launch Claude Code with --dangerously-skip-permissions
- `help` -- Show available commands

## Secrets

API secrets such as `GH_TOKEN` may hold a placeholder (`ac-placeholder-<VAR>`). This
is expected: HTTPS goes through a proxy (`HTTPS_PROXY`) that swaps in the real value
for that secret's own API hosts, so `gh`, `git` and SDKs work as usual. The real
values are not available inside the container.
