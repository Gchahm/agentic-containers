#!/usr/bin/env bash
# infra/create-db.sh
# For a given app name, provision one Postgres database + one login role
# per environment. Defaults: dev, staging, prod.
#
# Naming convention:
#   Database = <app>-<env>     (e.g. app1-dev, app1-staging, app1-prod)
#   Role     = <app>-<env>     (one role per database — least privilege)
#
# Each role owns its own database; PUBLIC's CONNECT is revoked. A compromised
# dev credential cannot reach staging or prod databases.

set -eu
# Intentionally NOT setting pipefail: random_password uses `tr ... | head -c 32`,
# and tr getting SIGPIPE when head exits early would otherwise crash the script
# silently under set -e. None of our other pipelines need pipefail semantics.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- load .env (overrides shell env, CLI flags override .env) ----------
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

# ---------- defaults ----------
APP=""
ENVS="dev,staging,prod"
HOST="${PGHOST:-localhost}"
PORT="${PGPORT:-5432}"
ADMIN_USER="${PGUSER:-postgres}"
ADMIN_PASSWORD="${PGPASSWORD:-}"
SSL_MODE="${PGSSLMODE:-require}"  # for the script's OWN psql calls (against the local tunnel)
RDS_HOSTNAME="${DB_RDS_HOSTNAME:-}"  # used in emitted URLs (sslmode=verify-full)

usage() {
  cat <<EOF
Usage: $(basename "$0") --app <name> [options]

For the given app, creates one database + one role per environment with
locked-down permissions. Re-run safely: existing roles/dbs are skipped.

Required:
  --app <name>           App name (e.g. app1). Must match ^[a-z][a-z0-9-]*\$.

Options:
  --envs <list>          Comma-separated env list (default: dev,staging,prod)
  --host <h>             Default: \$PGHOST or localhost
  --port <p>             Default: 5432
  --admin-user <u>       Default: \$PGUSER or postgres
  --admin-password <p>   Default: \$PGPASSWORD (prefer infra/.env)
  --sslmode <m>          For the script's OWN psql calls against the local
                         tunnel. Default: require (no verification — fine for
                         localhost). Set to verify-full only if your local
                         /etc/hosts maps the RDS hostname to 127.0.0.1.
  --rds-hostname <h>     RDS endpoint to embed in the emitted DATABASE_URL
                         lines. Default: \$DB_RDS_HOSTNAME. Required for the
                         emitted URLs to support sslmode=verify-full (the
                         container is set up to resolve this to 127.0.0.1
                         via --add-host)
  -h, --help

Loads infra/.env automatically if present.

Examples:
  # 3 envs (dev, staging, prod):
  ./infra/create-db.sh --app app1

  # Just dev + staging:
  ./infra/create-db.sh --app app1 --envs dev,staging

  # One-off main branch DB:
  ./infra/create-db.sh --app app1 --envs main
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)             APP="$2"; shift 2 ;;
    --envs)            ENVS="$2"; shift 2 ;;
    --host)            HOST="$2"; shift 2 ;;
    --port)            PORT="$2"; shift 2 ;;
    --admin-user)      ADMIN_USER="$2"; shift 2 ;;
    --admin-password)  ADMIN_PASSWORD="$2"; shift 2 ;;
    --sslmode)         SSL_MODE="$2"; shift 2 ;;
    --rds-hostname)    RDS_HOSTNAME="$2"; shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$APP" ]] && { echo "ERROR: --app required" >&2; usage >&2; exit 1; }
[[ -z "$ADMIN_PASSWORD" ]] && {
  echo "ERROR: admin password not set. Put PGPASSWORD in infra/.env or pass --admin-password." >&2
  exit 1
}
if ! command -v psql >/dev/null; then
  echo "ERROR: psql not found. Install postgresql-client (e.g. brew install libpq)." >&2
  exit 1
fi

if [[ ! "$APP" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "ERROR: --app '$APP' must match ^[a-z][a-z0-9-]*\$ (lowercase letters, digits, hyphens; must start with a letter)." >&2
  exit 1
fi

# ---------- helpers ----------
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }

export PGHOST="$HOST" PGPORT="$PORT" PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD" PGSSLMODE="$SSL_MODE"

psql_admin() { psql -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql_db()    { local db="$1"; shift; psql -d "$db" -v ON_ERROR_STOP=1 "$@"; }
random_password() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

# ---------- main loop ----------
declare -a RESULTS
IFS=',' read -ra ENV_LIST <<< "$ENVS"

for env in "${ENV_LIST[@]}"; do
  env="${env// /}"  # strip whitespace
  [[ -z "$env" ]] && continue

  if [[ ! "$env" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: env name '$env' must match ^[a-z][a-z0-9-]*\$" >&2
    exit 1
  fi

  DB="${APP}-${env}"
  ROLE="${APP}-${env}"

  log "[$env] $DB"

  ROLE_EXISTS=$(psql_admin -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ROLE'")
  if [[ "$ROLE_EXISTS" == "1" ]]; then
    log "    role $ROLE exists — password unchanged"
    PASSWORD="(existing — not rotated)"
  else
    PASSWORD=$(random_password)
    psql_admin -c "CREATE ROLE \"$ROLE\" WITH LOGIN PASSWORD '$PASSWORD';" >/dev/null
    log "    role $ROLE created"
  fi

  # On RDS the master user isn't a true superuser — it must be a member of
  # the target role to CREATE DATABASE ... OWNER <role>. Idempotent.
  psql_admin -c "GRANT \"$ROLE\" TO \"$ADMIN_USER\";" >/dev/null

  DB_EXISTS=$(psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='$DB'")
  if [[ "$DB_EXISTS" == "1" ]]; then
    log "    database $DB exists"
  else
    psql_admin -c "CREATE DATABASE \"$DB\" OWNER \"$ROLE\";" >/dev/null
    log "    database $DB created"
  fi

  psql_admin <<SQL >/dev/null
REVOKE CONNECT ON DATABASE "$DB" FROM PUBLIC;
GRANT  CONNECT ON DATABASE "$DB" TO "$ROLE";
SQL

  psql_db "$DB" <<SQL >/dev/null
GRANT ALL ON SCHEMA public TO "$ROLE";
SQL

  # Emitted URL uses the RDS hostname + sslmode=verify-full when DB_RDS_HOSTNAME
  # is set, so apps inside containers (with --add-host) get full TLS verification.
  # Falls back to localhost + sslmode=require when not set.
  if [[ -n "$RDS_HOSTNAME" ]]; then
    URL_HOST="$RDS_HOSTNAME"
    URL_SSLMODE="verify-full"
  else
    URL_HOST="$HOST"
    URL_SSLMODE="require"
  fi
  if [[ "$PASSWORD" == "(existing"* ]]; then
    CONN="postgresql://${ROLE}:<existing-password>@${URL_HOST}:${PORT}/${DB}?sslmode=${URL_SSLMODE}"
  else
    CONN="postgresql://${ROLE}:${PASSWORD}@${URL_HOST}:${PORT}/${DB}?sslmode=${URL_SSLMODE}"
  fi

  RESULTS+=("$env|$DB|$ROLE|$PASSWORD|$CONN")
done

# ---------- summary ----------
# Environment variable name prefix: hyphens -> underscores, uppercase.
APP_VAR=$(echo "$APP" | tr '-' '_' | tr '[:lower:]' '[:upper:]')

echo
echo "===================================================================="
echo "  ${APP} — ${#RESULTS[@]} environment(s)"
echo "===================================================================="
echo

for line in "${RESULTS[@]}"; do
  IFS='|' read -r env db role password conn <<< "$line"
  printf '[%s]\n' "$(echo "$env" | tr '[:lower:]' '[:upper:]')"
  printf '  Database:    %s\n' "$db"
  printf '  Role:        %s\n' "$role"
  printf '  Password:    %s\n' "$password"
  printf '  Connection:  %s\n\n' "$conn"
done

echo "===================================================================="
echo "  .env entries (copy into your app's environment)"
echo "===================================================================="
echo
for line in "${RESULTS[@]}"; do
  IFS='|' read -r env db role password conn <<< "$line"
  env_var=$(echo "$env" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  echo "# ${APP} — ${env}"
  echo "${APP_VAR}_${env_var}_DATABASE_URL=\"$conn\""
  echo
done

echo "==> Save the passwords above NOW — they're shown only this once."
echo "    Existing-role rows show <existing-password> as a placeholder;"
echo "    the script never rotates passwords for roles that already exist."
