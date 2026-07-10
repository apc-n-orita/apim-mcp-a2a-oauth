#!/bin/bash
# ---------------------------------------------
# Microsoft Foundry prompt agent provisioning script
# Docs references:
# - Agents - create agent / create agent version:
#   https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject
#     - create agent         : POST  {endpoint}/agents?api-version=v1                  (body: name + definition)
#     - create agent version : POST  {endpoint}/agents/{name}/versions?api-version=v1  (body: definition)
#       (既定の version selector は「常に最新バージョンへ 100% ルーティング」のため、
#        新バージョン作成のみで更新が反映される)
# - Configure and share your agent (PATCH は merge-patch):
#   https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent
# - Enable incoming A2A on a Foundry agent (preview):
#   https://learn.microsoft.com/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint
#
# Usage: bash deploy_prompt_agent.sh PROJECT_ENDPOINT AGENT_NAME
# Required environment variables:
#   AGENT_CREATE_PAYLOAD  : JSON body for POST  {endpoint}/agents                 (name + description + definition)
#   AGENT_VERSION_PAYLOAD : JSON body for POST  {endpoint}/agents/{name}/versions (description + definition)
# Optional environment variables:
#   AGENT_PATCH_PAYLOAD   : JSON body for PATCH {endpoint}/agents/{name}          (agent_card + agent_endpoint.protocols)
#                           空または未設定の場合は PATCH をスキップする (A2A 公開が不要なエージェント向け)
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
: "${AGENT_PATCH_PAYLOAD:=}"

# 並列実行 (terraform の for_each) でも競合しないよう、一時ファイルは mktemp で作成する
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

echo "Getting Microsoft Foundry data plane access token (resource=https://ai.azure.com)..."
access_token=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

if [ -z "$access_token" ]; then
  echo "Error: Failed to get access token. Please make sure you're logged in with 'az login'" >&2
  exit 1
fi

request() {
  local method="$1"
  local url="$2"
  local content_type="$3"
  local body="$4"
  local response_file="$5"

  LAST_HTTP_CODE=$(curl -s -o "$response_file" -w "%{http_code}" -X "$method" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: ${content_type}" \
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
    exit 1
  fi
  cat "$response_file" | sed 's/\r//'
  echo "${label} completed."
}

# 1) エージェントの存在確認
#    200 -> 既存: 新バージョン作成 (POST /agents/{name}/versions)
#    404 -> 新規: エージェント作成 (POST /agents)
#    それ以外 (401/403 等) -> 判定不能のため中断 (誤って新規作成パスに進まない)
echo "Checking if agent '${agent_name}' already exists..."
status=$(curl -s -o "${work_dir}/agent_get_resp.json" -w "%{http_code}" \
  -H "Authorization: Bearer ${access_token}" \
  "${endpoint}/agents/${agent_name}?api-version=${api_version}")

case "$status" in
  200)
    echo "Agent '${agent_name}' already exists. Creating a new version..."
    request POST "${endpoint}/agents/${agent_name}/versions?api-version=${api_version}" "application/json" "$AGENT_VERSION_PAYLOAD" "${work_dir}/agent_version_resp.json"
    handle_result "agent version" "${work_dir}/agent_version_resp.json"
    ;;
  404)
    echo "Agent '${agent_name}' does not exist. Creating..."
    request POST "${endpoint}/agents?api-version=${api_version}" "application/json" "$AGENT_CREATE_PAYLOAD" "${work_dir}/agent_create_resp.json"
    handle_result "agent create" "${work_dir}/agent_create_resp.json"
    ;;
  *)
    echo "Error: Unexpected status ${status} while checking agent existence. Response body:" >&2
    cat "${work_dir}/agent_get_resp.json" >&2
    exit 1
    ;;
esac

# 2) agent card の設定 + A2A プロトコルの有効化 (merge-patch)。ペイロードが空の場合はスキップ
if [ -n "$AGENT_PATCH_PAYLOAD" ]; then
  echo "Configuring agent card and enabling A2A protocol on agent '${agent_name}'..."
  request PATCH "${endpoint}/agents/${agent_name}?api-version=${api_version}" "application/merge-patch+json" "$AGENT_PATCH_PAYLOAD" "${work_dir}/agent_patch_resp.json"
  handle_result "agent card / A2A enablement" "${work_dir}/agent_patch_resp.json"
  echo "A2A base path: ${endpoint}/agents/${agent_name}/endpoint/protocols/a2a"
else
  echo "AGENT_PATCH_PAYLOAD is empty. Skipping agent card / A2A enablement."
fi

echo "All agent provisioning steps completed successfully."
