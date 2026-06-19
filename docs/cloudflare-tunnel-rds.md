# Reaching a Private RDS Instance from Dev Containers via Cloudflare Tunnel

This document walks through setting up Cloudflare Tunnel + Cloudflare Access so that dev containers running on your laptop can connect to a private RDS instance in AWS — with no public IP on RDS and no IP allowlisting on either side.

## Why this setup

- Dev containers (`ac create …`) run on your Mac, outside any AWS VPC. They need a way into the VPC to reach RDS.
- The naive answer — make RDS publicly accessible + allowlist your laptop's IP — breaks every time your ISP rotates your IP and exposes RDS to the public internet.
- Cloudflare Tunnel solves this by establishing an outbound connection from inside the VPC to Cloudflare's edge. Containers reach RDS through that pipe, authenticated by Cloudflare Access (SSO for humans, service tokens for containers).
- Result: RDS stays private, no inbound firewall holes anywhere, identity-based access instead of IP-based.

## Architecture

```
┌──────────────────────┐         ┌──────────────────┐         ┌─────────────────────────────────┐
│  Dev container        │         │  Cloudflare      │         │  AWS VPC (your region)         │
│  (on your Mac)        │         │  edge            │         │                                 │
│                       │         │                  │         │  ┌───────────────────────────┐  │
│  cloudflared          │ ──TLS──▶│  Access policy   │◀──TLS── │  │ EC2 (t4g.nano)            │  │
│  access tcp           │         │  + tunnel router │         │  │ cloudflared connector     │  │
│  → localhost:5432     │         │                  │         │  └──────────┬────────────────┘  │
│                       │         │                  │         │             │ VPC (5432)        │
│  App → localhost:5432 │         │                  │         │  ┌──────────▼────────────────┐  │
│                       │         │                  │         │  │ RDS PostgreSQL (private)  │  │
└──────────────────────┘         └──────────────────┘         │  └───────────────────────────┘  │
                                                              └─────────────────────────────────┘
```

Both ends dial **out** to Cloudflare — nothing accepts inbound from the internet except Cloudflare itself.

## Prerequisites

- A domain on Cloudflare (DNS managed by Cloudflare). Required for Access policies and tunnel hostnames.
- Cloudflare Zero Trust enabled on your account (free tier covers up to 50 users — sign up at `one.dash.cloudflare.com` if you haven't).
- RDS instance running in your AWS VPC. Note its endpoint (RDS console → instance → Connectivity & security → Endpoint) and the port (5432 by default for PostgreSQL).
- RDS set to **not publicly accessible** (the goal — we'll route to it through the tunnel).
- AWS CLI configured locally, or comfort with the AWS console.

## Part 1 — Create the tunnel and Access policy (Cloudflare)

> **Dashboard menu names move around.** Cloudflare reshuffles Zero Trust navigation every few months — the paths below match the current docs (as of 2026-06) but may drift. If something doesn't match, cross-reference [developers.cloudflare.com/cloudflare-one](https://developers.cloudflare.com/cloudflare-one/) and trust the official docs over this one.

### 1.1 Create the tunnel

1. In the **Cloudflare Zero Trust dashboard** (`one.dash.cloudflare.com`), go to **Networks → Connectors → Cloudflare Tunnels → Create a tunnel**.
2. Choose **Cloudflared** as the connector type. Click **Next**.
3. Name it something descriptive (e.g. `rds-<region>` or `rds-tunnel`). Click **Save tunnel**.
4. Cloudflare shows install commands for various platforms (Docker, Debian, RHEL, etc.). You have two options:
   - **Copy the entire install command** and run it on the EC2 — easiest, runs cloudflared as a foreground process.
   - **Copy just the token** (the long string after `--token`) and use `sudo cloudflared service install <token>` on the EC2 — recommended, runs cloudflared as a systemd service so it restarts on reboot.
   Don't close this tab yet — once the connector is running, the dashboard advances to the route configuration step.

### 1.2 Define the public hostname → private service route

After the connector reports as connected, the wizard moves to **Route traffic** (or you can find this later under the tunnel's **Published applications** tab — older dashboards labelled it **Public Hostnames**).

1. Click **Add a published application** and fill in the dialog:
   - **Subdomain** (optional): pick a label like `db-dev`
   - **Domain**: your Cloudflare-managed zone (resulting hostname = `<subdomain>.<domain>`)
   - **Path** (optional): leave empty — path matching is HTTP-only and doesn't apply to TCP
   - **Service URL**: `tcp://<rds-endpoint>:5432`
     *(find this in AWS console → RDS → your instance → **Connectivity & security** → **Endpoint**. Format: `<db-identifier>.<random>.<region>.rds.amazonaws.com`. The current UI no longer has a separate "Type" dropdown — the scheme in the URL (`tcp://`, `http://`, `https://`, `ssh://`, …) selects the protocol.)*
2. Click **Add route**.

Cloudflare automatically creates the CNAME `<subdomain>.<domain> → <tunnel-id>.cfargotunnel.com`.

### 1.3 Protect the hostname with an Access application

Without this step, the hostname is reachable by anyone who knows the URL. Access is what gates it.

1. **Zero Trust → Access controls → Applications → Add an application** (newer dashboards: **Create new application**).
2. Two-level type selection:
   - Top tab: **Self-hosted and private**
   - Sub-tab: **Public DNS** *(this matches the public hostname created by the tunnel in Part 1.2. The other sub-tabs — **Private destinations** for WARP-routed access, **Workers** for serverless apps, **Service auth** for M2M-only apps — don't fit this use case.)*
   Click **Continue with Self-hosted and private**.
3. Application name: `RDS Dev`. Session duration: 24h (or whatever you prefer).
4. **Add public hostname** → set Subdomain and Domain to the same values used in Part 1.2.
5. Under **Access policies**, add a policy:
   - Name: `Allow me`
   - Action: **Allow**
   - Include: **Emails** → `<your-sso-email>`
6. Save.

Test it: visit `https://<subdomain>.<domain>` in a browser. You should get a Cloudflare Access login page. Don't worry that the browser shows nothing useful after login — it's a TCP endpoint, not HTTP. The login flow is what matters.

### 1.4 Create a service token for the dev containers

Containers can't do interactive browser SSO. They authenticate with a service token instead.

1. **Zero Trust → Access controls → Service credentials → Service Tokens → Create Service Token**.
2. Name: `ac-dev-containers`. Duration: pick something long (1 year) — you can rotate later.
3. Cloudflare shows the **Client ID** and **Client Secret** **once**. Copy both immediately.

Now attach the service token to the Access application — **this is where there's a gotcha**:

4. Go back to the `RDS Dev` application → **Policies** → **Add a policy** (don't edit the existing email policy — add a second one).
5. Configure the new policy:
   - Name: `Allow dev containers`
   - Action: **Service Auth** *(NOT Allow — if you pick Allow, Cloudflare will still prompt for browser SSO and the service token won't bypass it)*
   - Include: **Service Token** → `ac-dev-containers`
6. Save.

You should now have **two policies** on the application: one `Allow` for your email, one `Service Auth` for the service token. Humans authenticate via browser; containers authenticate via headers.

## Part 2 — Run the tunnel connector (AWS)

### 2.1 Launch the EC2

Use the AWS console or CLI. Key requirements:

- **Region**: same as RDS
- **Instance type**: `t4g.nano` (sufficient — cloudflared idles at <10MB RAM)
- **AMI**: Amazon Linux 2023 (arm64) or Ubuntu 24.04 (arm64) — examples below assume Amazon Linux 2023
- **VPC**: same VPC as RDS
- **Subnet**: any subnet in that VPC (public or private — only outbound 443 to Cloudflare needed)
- **Auto-assign public IP**: not strictly required, but enable it for easier troubleshooting (SSH in to debug). Disable later.
- **Security group**: new SG `sg-tunnel-connector`. Inbound: SSH from your IP (for setup). Outbound: all (default).
- **Key pair**: pick one you have access to, or skip and use SSM Session Manager.

### 2.2 Allow the connector to reach RDS

The connector EC2 has its own security group, but that controls inbound traffic *to* the EC2. RDS by default rejects inbound from anything outside its own SG, so we need a rule on **RDS's** security group that lets the connector in.

1. **RDS console** → your instance → **Connectivity & security** tab → click the **VPC security group** (this opens that SG in the EC2 console).
2. **Inbound rules** tab → **Edit inbound rules** → **Add rule**:
   - **Type**: PostgreSQL (auto-fills Protocol = TCP, Port = 5432)
   - **Source**: Custom → paste the **connector EC2's security group ID** (e.g., `sg-tunnel-connector` or whatever yours is named)
   - **Description**: `cloudflared tunnel connector`
3. **Save rules**.

This is the only network rule the tunnel needs. Verify from the connector EC2:

```bash
timeout 5 bash -c '</dev/tcp/<rds-endpoint>/5432' && echo OPEN || echo BLOCKED
```

`OPEN` means the path works. `BLOCKED` means either the rule didn't save or you referenced the wrong SG.

### 2.3 Install and start cloudflared on the EC2

SSH into the EC2 and run:

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.rpm -o cloudflared.rpm
sudo dnf install -y ./cloudflared.rpm

# Install as a system service using the token from Part 1.1
sudo cloudflared service install <PASTE_TUNNEL_TOKEN_HERE>

# Verify
sudo systemctl status cloudflared
```

You should see `active (running)`. Back in the Cloudflare dashboard, the tunnel status should flip to **Healthy** within ~30 seconds.

### 2.4 Make sure RDS is private

Now that the tunnel is up, flip RDS back to not publicly accessible (if it isn't already):

- RDS console → instance → Modify → Connectivity → **Not publicly accessible** → Apply immediately.
- Remove any "My IP" rules from RDS's security group. Keep only the `sg-tunnel-connector` reference.

## Part 3 — Connect from a dev container

### 3.1 Add credentials to `.env`

In your repo's `.env` (gitignored), add:

```
# Cloudflare Access service token (from Part 1.4)
CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...

# Cloudflare-side hostname (from Part 1.2 — <subdomain>.<your-domain>)
DB_TUNNEL_HOSTNAME=<subdomain>.<your-domain>

# Real AWS RDS endpoint — the container maps this to 127.0.0.1 via --add-host
# so apps can connect using the RDS hostname and pass sslmode=verify-full.
DB_RDS_HOSTNAME=<db-identifier>.<random>.<region>.rds.amazonaws.com

# Postgres connection details — these are per-app, see "App-level setup" below
DB_HOST=localhost
DB_PORT=5432
DB_USER=app1
DB_PASSWORD=...
DB_NAME=app1_dev
```

Update `.env.example` to document the new vars (without values).

### 3.2 Wire the tunnel into container startup

Edit `types/<type>/scripts/home/startup` (the script that runs before `exec sshd`). Add, before the sshd exec line:

```bash
# Cloudflare Access tunnel to RDS (if configured)
if [[ -n "${DB_TUNNEL_HOSTNAME:-}" && -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then
  echo "Starting cloudflared access tunnel to ${DB_TUNNEL_HOSTNAME}…"
  nohup cloudflared access tcp \
    --hostname "$DB_TUNNEL_HOSTNAME" \
    --url "localhost:${DB_PORT:-5432}" \
    --service-token-id "$CF_ACCESS_CLIENT_ID" \
    --service-token-secret "$CF_ACCESS_CLIENT_SECRET" \
    >/var/log/cloudflared-rds.log 2>&1 &
fi
```

Notes:
- Service tokens are passed via `--service-token-id` / `--service-token-secret` flags. The `TUNNEL_SERVICE_TOKEN_*` env-var convention applies to `cloudflared tunnel`, not `cloudflared access tcp` — that one needs explicit flags.
- The tunnel runs in the background; the script continues to `exec sshd`.
- Output goes to `/var/log/cloudflared-rds.log` for troubleshooting.

Apply the same change to every type (`typescript`, `dotnet`, …) — or factor it into a shared script later when you refactor types.

### 3.3 Provision the per-app database and role

First time only — connect from the EC2 connector (or temporarily from your laptop via `cloudflared access tcp` on your Mac) as the master `postgres` user and run:

```sql
CREATE DATABASE app1_dev;
CREATE ROLE app1 WITH LOGIN PASSWORD '<strong-password>';
GRANT CONNECT ON DATABASE app1_dev TO app1;
\c app1_dev
GRANT ALL ON SCHEMA public TO app1;
REVOKE CONNECT ON DATABASE app1_dev FROM PUBLIC;
```

Repeat per app. Stash each `app1`/`app2`/… password in your secrets manager.

## Part 4 — Test it

Rebuild and start a container:

```bash
ac build typescript
ac create typescript test-tunnel
ac shell test-tunnel
```

Inside the container:

```bash
# Confirm tunnel is up
tail -n 20 /var/log/cloudflared-rds.log
# Expect a line like: "Proxying tcp to <your-tunnel-hostname> via cloudflare"

# Confirm local port is listening
ss -tlnp | grep 5432

# Connect via psql
psql "postgresql://app1:${DB_PASSWORD}@localhost:5432/app1_dev?sslmode=require"
```

If `psql` connects and `\l` shows `app1_dev`, the path is working end-to-end:

```
your container → cloudflared access tcp → Cloudflare edge → tunnel connector EC2 → RDS
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `cloudflared access tcp` exits immediately with auth error | Wrong service token, or token not added to the Access policy | Re-add the service token in the Access app's policy under **Include** |
| Tunnel status "Down" in Cloudflare dashboard | EC2 connector can't reach Cloudflare on 443 | Check EC2 outbound SG, NACL, and route to internet gateway |
| `psql` connects but hangs forever before prompt | TLS mismatch — RDS requires SSL and your client didn't provide it | Add `?sslmode=require` (or `verify-full` with the RDS CA bundle `global-bundle.pem`) |
| `psql` "no pg_hba.conf entry" | Connected to wrong DB or user not granted | Check `\du` and `\l` from master account |
| Local port 5432 not listening | Tunnel command failed silently | Check `/var/log/cloudflared-rds.log` |
| Connector EC2 can't reach RDS | RDS SG doesn't allow the connector SG | Add `sg-tunnel-connector` to RDS SG inbound on 5432 |

## Costs

- EC2 `t4g.nano` 24/7: ~$3/month
- RDS: unchanged
- Cloudflare Zero Trust free tier (up to 50 users): $0
- Cloudflare Tunnel bandwidth: $0 (no charge for tunnel traffic)

## Next steps (later, not now)

- Move the connector from a single EC2 to a Fargate task for HA (still ~$3-5/month).
- Add a separate tunnel for staging if/when you split prod and staging RDS.
- Rotate the service token annually (set a calendar reminder).
- When apps deploy to AWS (ECS/Fargate), they skip the tunnel and connect to RDS directly via VPC — same connection string code, different env vars.
