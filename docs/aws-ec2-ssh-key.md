# Trusting an AWS EC2 SSH Key on macOS

When you create an EC2 key pair, AWS lets you download the private key as a `.pem` file **once**. This document covers how to set it up so `ssh` will use it, and how to integrate with the macOS keychain so you stop typing `-i ~/.ssh/whatever.pem` every time.

## 1. Move and lock down the key

SSH refuses to use a key file that's readable by anyone but you.

```bash
mkdir -p ~/.ssh
mv ~/Downloads/your-key.pem ~/.ssh/
chmod 400 ~/.ssh/your-key.pem
```

- `400` = read-only for you, no access for group or others. `600` also works.
- Verify: `ls -l ~/.ssh/your-key.pem` should show `-r--------`.

## 2. Use it for a one-off connection

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<ec2-public-dns>
```

Default users by AMI:

| AMI | User |
|---|---|
| Amazon Linux 2 / 2023 | `ec2-user` |
| Ubuntu | `ubuntu` |
| Debian | `admin` |
| RHEL | `ec2-user` |

## 3. Add a host alias (recommended)

Edit `~/.ssh/config` and add:

```
Host tunnel-connector
    HostName ec2-54-85-254-247.compute-1.amazonaws.com
    User ec2-user
    IdentityFile ~/.ssh/your-key.pem
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
```

Now you can just run:

```bash
ssh tunnel-connector
```

Key options:

- `IdentitiesOnly yes` — only try the key listed in `IdentityFile`. Without this, SSH offers every key in your agent first, and AWS may rate-limit your connection after a few wrong attempts.
- `AddKeysToAgent yes` + `UseKeychain yes` — load the key into `ssh-agent` and store the passphrase (if any) in the macOS keychain. For unencrypted EC2 keys this just keeps the key in-memory after first use so subsequent connections skip filesystem reads.

## 4. (Optional) Add to ssh-agent + keychain manually

If your key has a passphrase, or you just want to preload it:

```bash
ssh-add --apple-use-keychain ~/.ssh/your-key.pem
```

This stores the passphrase in the macOS keychain so you don't get prompted again across reboots.

To verify what keys are loaded:

```bash
ssh-add -l
```

## 5. Back up the key

AWS only lets you download the `.pem` once at key creation time. If you lose it, you can't SSH into instances using that key — recovery means stopping the instance, detaching the root volume, mounting it on another instance, and editing `authorized_keys`. Painful.

Save a copy somewhere durable:

- 1Password supports file attachments — paste the `.pem` contents into a secure note
- Or copy to an encrypted external drive

Don't commit it to git, don't share via Slack/email, don't store it unencrypted in cloud storage.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Permissions … are too open` | Key file is group/world-readable | `chmod 400 ~/.ssh/your-key.pem` |
| `Permission denied (publickey)` | Wrong user, or key doesn't match the instance's authorized_keys | Verify default user for the AMI; confirm you're using the right key |
| `Too many authentication failures` | SSH tried other keys first, AWS rate-limited | Add `IdentitiesOnly yes` to `~/.ssh/config` |
| Hangs on connect | Security group doesn't allow your IP on port 22 | Update SG inbound: SSH / TCP 22 / My IP |
| `Host key verification failed` | Instance was replaced and has a new host key | `ssh-keygen -R <hostname>` to clear the old fingerprint, then reconnect |
