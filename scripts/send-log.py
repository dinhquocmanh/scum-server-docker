#!/usr/bin/env python3
"""Send a minimal lifecycle message to an optional Discord-compatible webhook."""
import json
import os
import sys
import urllib.request

url = os.environ.get("LOG_WEBHOOK_URL", "").strip()
if not url:
    raise SystemExit(0)

message = " ".join(sys.argv[1:]).strip()
payload = json.dumps({"content": f"[SCUM] {message}"}).encode()
request = urllib.request.Request(
    url,
    data=payload,
    headers={"Content-Type": "application/json", "User-Agent": "scum-server-docker/1.0"},
    method="POST",
)
try:
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status not in (200, 204):
            raise RuntimeError(f"HTTP {response.status}")
except Exception as exc:
    print(f"webhook error: {exc}", file=sys.stderr)
    raise SystemExit(1)
