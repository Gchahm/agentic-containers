#!/usr/bin/env bash
# infra/create-rds.sh
# Provision a private RDS PostgreSQL instance with its own subnet group and
# security group. Assumes admin AWS credentials are configured (AWS_PROFILE
# or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars).
#
# Idempotent: if the instance, subnet group, or security group already
# exist, they are reused.

set -eu
# Intentionally NOT setting pipefail: the random-password helper uses
# `tr ... | head -c 32`, and tr getting SIGPIPE when head exits would
# otherwise crash the script silently under set -e.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- load .env ----------
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

# ---------- defaults ----------
REGION="${AWS_REGION:-sa-east-1}"
CLASS="db.t4g.micro"
STORAGE=20
ENGINE_VERSION="16"
MASTER_USER="dbadmin"
MASTER_PASSWORD=""
NAME=""
VPC_ID=""
BACKUP_DAYS=7

usage() {
  cat <<EOF
Usage: $(basename "$0") --name <identifier> [options]

Provisions a private RDS PostgreSQL instance. The instance is created
with NO inbound rules on its security group — add those later via
another script or grant access from a tunnel-connector SG.

Required:
  --name <id>            DB instance identifier

Options:
  --region <region>      AWS region (default: \$AWS_REGION or sa-east-1)
  --class <class>        Instance class (default: db.t4g.micro — free tier)
  --storage <gib>        Allocated storage in GiB (default: 20)
  --engine-version <v>   Postgres major version (default: 16)
  --master-user <name>   Master username (default: dbadmin)
  --master-password <p>  Master password (default: random 32-char, printed once)
  --vpc-id <id>          VPC ID (default: default VPC in the region)
  --backup-days <n>      Backup retention in days (default: 7)
  -h, --help

Example:
  $(basename "$0") --name shared-dev-apps --region sa-east-1
EOF
}

# ---------- argparse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)             NAME="$2"; shift 2 ;;
    --region)           REGION="$2"; shift 2 ;;
    --class)            CLASS="$2"; shift 2 ;;
    --storage)          STORAGE="$2"; shift 2 ;;
    --engine-version)   ENGINE_VERSION="$2"; shift 2 ;;
    --master-user)      MASTER_USER="$2"; shift 2 ;;
    --master-password)  MASTER_PASSWORD="$2"; shift 2 ;;
    --vpc-id)           VPC_ID="$2"; shift 2 ;;
    --backup-days)      BACKUP_DAYS="$2"; shift 2 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$NAME" ]] && { echo "ERROR: --name is required" >&2; usage >&2; exit 1; }

# ---------- helpers ----------
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
aws_rds() { aws rds "$@" --region "$REGION"; }
aws_ec2() { aws ec2 "$@" --region "$REGION"; }

# ---------- idempotency ----------
if aws_rds describe-db-instances --db-instance-identifier "$NAME" &>/dev/null; then
  log "RDS instance '$NAME' already exists in $REGION."
  ENDPOINT=$(aws_rds describe-db-instances --db-instance-identifier "$NAME" \
    --query 'DBInstances[0].Endpoint.Address' --output text)
  echo "  Endpoint: $ENDPOINT"
  exit 0
fi

# ---------- VPC ----------
if [[ -z "$VPC_ID" ]]; then
  VPC_ID=$(aws_ec2 describe-vpcs --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)
  if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
    echo "ERROR: no default VPC in $REGION. Pass --vpc-id explicitly." >&2
    exit 1
  fi
fi
log "Using VPC $VPC_ID"

# ---------- password ----------
GENERATED_PASSWORD=
if [[ -z "$MASTER_PASSWORD" ]]; then
  MASTER_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
  GENERATED_PASSWORD=1
fi

# ---------- subnet group ----------
SUBNET_GROUP="${NAME}-subnets"
if ! aws_rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" &>/dev/null; then
  log "Creating DB subnet group $SUBNET_GROUP"
  # shellcheck disable=SC2046
  aws_rds create-db-subnet-group \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --db-subnet-group-description "Subnets for RDS $NAME" \
    --subnet-ids $(aws_ec2 describe-subnets \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'Subnets[*].SubnetId' --output text) \
    >/dev/null
fi

# ---------- security group ----------
SG_NAME="${NAME}-rds-sg"
SG_ID=$(aws_ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  log "Creating security group $SG_NAME"
  SG_ID=$(aws_ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "RDS $NAME — inbound rules added separately" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)
fi
log "Security group: $SG_ID"

# ---------- create instance ----------
log "Creating RDS instance $NAME (~5 min)"
aws_rds create-db-instance \
  --db-instance-identifier "$NAME" \
  --db-instance-class "$CLASS" \
  --engine postgres \
  --engine-version "$ENGINE_VERSION" \
  --master-username "$MASTER_USER" \
  --master-user-password "$MASTER_PASSWORD" \
  --allocated-storage "$STORAGE" \
  --storage-type gp3 \
  --storage-encrypted \
  --vpc-security-group-ids "$SG_ID" \
  --db-subnet-group-name "$SUBNET_GROUP" \
  --no-publicly-accessible \
  --backup-retention-period "$BACKUP_DAYS" \
  --no-multi-az \
  --auto-minor-version-upgrade \
  --tags "Key=ManagedBy,Value=ac-infra" "Key=Name,Value=$NAME" \
  >/dev/null

log "Waiting for instance to become available..."
aws_rds wait db-instance-available --db-instance-identifier "$NAME"

ENDPOINT=$(aws_rds describe-db-instances --db-instance-identifier "$NAME" \
  --query 'DBInstances[0].Endpoint.Address' --output text)

cat <<EOF

==> RDS instance ready

  Identifier:     $NAME
  Endpoint:       $ENDPOINT
  Port:           5432
  Master user:    $MASTER_USER
  Security group: $SG_ID  ($SG_NAME)
  Subnet group:   $SUBNET_GROUP

EOF

if [[ -n "$GENERATED_PASSWORD" ]]; then
  cat <<EOF
GENERATED MASTER PASSWORD — save this NOW, it won't be shown again:

  $MASTER_PASSWORD

EOF
fi
