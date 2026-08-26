#!/usr/bin/env bash
# Calls a Foundry toolbox's MCP endpoint (tools/list) and prints only the
# OAuth consent URL(s) if the response contains CONSENT_REQUIRED errors.
# Each tool's consent URL is printed with a label, separated by a blank line.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <toolbox-mcp-url>" >&2
  exit 1
fi
TOOLBOX_URL="$1"

TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

TOOLS_RESP=$(curl -sS -X POST "$TOOLBOX_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')

python3 - "$TOOLS_RESP" <<'PYEOF'
import json
import sys

resp = json.loads(sys.argv[1])
error = resp.get("error", {})
message = error.get("message", "")

brace_index = message.find("{")
try:
    detail = json.loads(message[brace_index:]) if brace_index != -1 else None
except (TypeError, json.JSONDecodeError):
    detail = None

entries = detail.get("errors", []) if isinstance(detail, dict) else []
consent_entries = [
    e for e in entries
    if e.get("error", {}).get("code") == "CONSENT_REQUIRED"
]

if not consent_entries:
    print("No consent URL found. Raw response:", file=sys.stderr)
    print(json.dumps(resp, indent=2, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)

for i, entry in enumerate(consent_entries):
    if i > 0:
        print()
    print(f"[{entry.get('name')}] ({entry.get('type')})")
    print(entry["error"]["message"])
PYEOF
