#!/bin/bash
# ---------------------------------------------
# Microsoft Foundry prompt agent provisioning script
# Docs references:
# - Agents - create agent / create agent version:
#   https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject
# - Enable incoming A2A on a Foundry agent (preview):
#   https://learn.microsoft.com/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint
#
# Usage: bash deploy_prompt_agent.sh PROJECT_ENDPOINT AGENT_NAME
# Required environment variables:
#   AGENT_CREATE_PAYLOAD  : JSON body for POST {endpoint}/agents (name + definition)
#   AGENT_VERSION_PAYLOAD : JSON body for POST {endpoint}/agents/{name}/versions (definition only)
#   AGENT_PATCH_PAYLOAD   : JSON body for PATCH {endpoint}/agents/{name} (agent_endpoint.protocols)
# ---------------------------------------------
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: bash $0 PROJECT_ENDPOINT AGENT_NAME" >&2
  echo "Example: bash $0 https://aif-sample.services.ai.azure.com/api/projects/ai-foundry-project tartaria-agent" >&2
  exit 1
fi

endpoint="$1"
agent_name="$2"
api_version="v1"

: "${AGENT_CREATE_PAYLOAD:?AGENT_CREATE_PAYLOAD is required}"
: "${AGENT_VERSION_PAYLOAD:?AGENT_VERSION_PAYLOAD is required}"
: "${AGENT_PATCH_PAYLOAD:?AGENT_PATCH_PAYLOAD is required}"

echo "Getting Microsoft Foundry data plane access token (resource=https://ai.azure.com)..."
access_token=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

if [ -z "$access_token" ]; then
  echo "Error: Failed to get access token. Please make sure you're logged in with 'az login'" >&2
  exit 1
fi

request() {
  local method="$1"
  local url="$2"
  local body="$3"
  local response_file="$4"

  LAST_HTTP_CODE=$(curl -s -o "$response_file" -w "%{http_code}" -X "$method" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    "$url" \
    --data "$body")
}

handle_result() {
  local label="$1"
  local response_file="$2"

  echo "${label} HTTP Response Code: ${LAST_HTTP_CODE}"
  if [[ "$LAST_HTTP_CODE" != "200" && "$LAST_HTTP_CODE" != "201" ]]; then
    echo "Failed: ${label}. Response body:" >&2
    cat "$response_file" >&2
    rm -f "$response_file"
    exit 1
  fi
  cat "$response_file" | sed 's/\r//'
  echo "${label} completed."
  rm -f "$response_file"
}

# 1) エージェントの存在確認 → 新規作成 or 新バージョン作成
echo "Checking if agent '${agent_name}' already exists..."
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${access_token}" \
  "${endpoint}/agents/${agent_name}?api-version=${api_version}")

if [ "$status" = "200" ]; then
  echo "Agent '${agent_name}' already exists. Creating a new version..."
  request POST "${endpoint}/agents/${agent_name}/versions?api-version=${api_version}" "$AGENT_VERSION_PAYLOAD" "/tmp/agent_version_resp.json"
  handle_result "agent version" "/tmp/agent_version_resp.json"
else
  echo "Agent '${agent_name}' does not exist (status ${status}). Creating..."
  request POST "${endpoint}/agents?api-version=${api_version}" "$AGENT_CREATE_PAYLOAD" "/tmp/agent_create_resp.json"
  handle_result "agent create" "/tmp/agent_create_resp.json"
fi

# 2) A2A プロトコルの有効化 (agent_endpoint.protocols = ["a2a", "responses"])
echo "Enabling A2A protocol on agent '${agent_name}'..."
request PATCH "${endpoint}/agents/${agent_name}?api-version=${api_version}" "$AGENT_PATCH_PAYLOAD" "/tmp/agent_patch_resp.json"
handle_result "agent A2A enablement" "/tmp/agent_patch_resp.json"

echo "All agent provisioning steps completed successfully."
echo "A2A base path: ${endpoint}/agents/${agent_name}/endpoint/protocols/a2a"
