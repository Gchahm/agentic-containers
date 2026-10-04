"""ac secrets proxy -- mitmproxy addon.

Agent containers hold a placeholder (ac-placeholder-<VAR>) instead of each real
secret. This addon swaps the placeholder for the real value in outgoing request
headers and URLs, but only on HTTPS requests to the hosts that secret is bound
to in secrets.conf. Everything else is tunnelled through untouched (no TLS
interception), so a placeholder sent anywhere else stays a placeholder.

Real values come from this container's environment, set by `ac`.
"""

import base64
import binascii
import logging
import os
import re
from urllib.parse import quote

from mitmproxy import ctx, http

CONF_PATH = os.environ.get("AC_SECRETS_CONF", "/addon/secrets.conf")
PLACEHOLDER_PREFIX = "ac-placeholder-"
VAR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
NEVER_MATCH = "(?!)"

logger = logging.getLogger("ac-proxy")


def host_matches(pattern: str, host: str) -> bool:
    if pattern.startswith("*."):
        return host.endswith(pattern[1:])
    return host == pattern


def host_regex(pattern: str) -> str:
    if pattern.startswith("*."):
        body = r".+\." + re.escape(pattern[2:])
    else:
        body = re.escape(pattern)
    return rf"^{body}(:443)?$"


def load_secrets(path: str) -> list[tuple[str, str, str, list[str]]]:
    """Return (name, placeholder, value, hosts) for every usable conf line."""
    secrets = []
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 2 or not VAR_RE.match(parts[0]):
                logger.warning("secrets.conf:%d: ignoring malformed line", lineno)
                continue
            name = parts[0]
            hosts = [h.lower() for h in parts[1].split(",") if h]
            value = os.environ.get(name, "")
            if not value:
                logger.info("%s: no value set, skipping", name)
                continue
            secrets.append((name, PLACEHOLDER_PREFIX + name, value, hosts))
    # Longest placeholder first, so FOO never clobbers part of FOO_BAR
    secrets.sort(key=lambda s: len(s[1]), reverse=True)
    return secrets


class InjectSecrets:
    def __init__(self) -> None:
        self.secrets = load_secrets(CONF_PATH)

    def running(self) -> None:
        # Intercept TLS only for hosts that have a secret bound to them
        patterns = sorted({host_regex(h) for s in self.secrets for h in s[3]})
        ctx.options.update(allow_hosts=patterns or [NEVER_MATCH])
        for name, _, _, hosts in self.secrets:
            logger.info("%s -> %s", name, ", ".join(hosts))

    def requestheaders(self, flow: http.HTTPFlow) -> None:
        req = flow.request
        if req.scheme != "https" or req.port != 443:
            return
        # req.host is the connection target, not the client-supplied Host header
        host = req.host.lower()
        upstream = flow.server_conn.address
        if upstream and upstream[0].lower() != host:
            return

        for name, placeholder, value, hosts in self.secrets:
            if not any(host_matches(h, host) for h in hosts):
                continue
            if self._replace(req, placeholder, value):
                logger.info("injected %s for %s", name, host)

    @staticmethod
    def _replace(req: http.Request, placeholder: str, value: str) -> bool:
        hit = False
        for key, val in list(req.headers.items(multi=True)):
            new = val
            if placeholder in new:
                new = new.replace(placeholder, value)
            elif key.lower() == "authorization" and new[:6].lower() == "basic ":
                # git sends the token base64-encoded in Basic auth
                try:
                    decoded = base64.b64decode(new[6:].strip(), validate=True).decode()
                except (binascii.Error, UnicodeDecodeError):
                    continue
                if placeholder in decoded:
                    creds = decoded.replace(placeholder, value)
                    new = "Basic " + base64.b64encode(creds.encode()).decode()
            if new != val:
                hit = True
                values = [new if v == val else v for v in req.headers.get_all(key)]
                req.headers.set_all(key, values)
        if placeholder in req.path:
            req.path = req.path.replace(placeholder, quote(value, safe=""))
            hit = True
        return hit


addons = [InjectSecrets()]
