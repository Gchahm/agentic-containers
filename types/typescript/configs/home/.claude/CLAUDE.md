# TypeScript Development Container

## Environment

- **Node.js**: 22 (default) and 24 available via `nvm use 24`
- **Package managers**: pnpm (preferred), npm
- **PostgreSQL**: localhost:5432 (user: postgres, password: postgres)
- **MongoDB**: localhost:27017 (user: mongo, password: mongo, authSource: admin)
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

## MongoDB

MongoDB 8.2 starts automatically on container boot with authentication enabled.
Connect with:
- URI: `mongodb://mongo:mongo@localhost:27017/?authSource=admin`
- Shell: `mongosh -u mongo -p mongo --authenticationDatabase admin`

The `mongo` user has the `root` role, so databases are created on first write.
`mongodump` / `mongorestore` and the rest of the database tools are installed.
Logs are at `/var/log/mongodb/mongod.log`.

## Commands

- `yolo` -- Launch Claude Code with --dangerously-skip-permissions
- `help` -- Show available commands
