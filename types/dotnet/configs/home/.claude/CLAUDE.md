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
