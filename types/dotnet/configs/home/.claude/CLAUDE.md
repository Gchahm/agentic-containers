# .NET Development Container

## Environment

- **.NET SDK**: 10 (default; override at build time with `DOTNET_VERSION`)
- **PostgreSQL**: localhost:5432 (user: postgres, password: postgres)

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
- `dotnet --info` -- Show installed .NET SDK info

## Secrets

API secrets such as `GH_TOKEN` may hold a placeholder (`ac-placeholder-<VAR>`). This
is expected: HTTPS goes through a proxy (`HTTPS_PROXY`) that swaps in the real value
for that secret's own API hosts, so `gh`, `git` and SDKs work as usual. The real
values are not available inside the container.
