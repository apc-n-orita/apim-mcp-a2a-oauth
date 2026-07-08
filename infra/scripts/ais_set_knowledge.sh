#!/bin/bash

# ---------------------------------------------
# Azure AI Search Knowledge Source & Knowledge Base provisioning script
# Docs references:
# - Knowledge Sources - Create or Update: https://learn.microsoft.com/en-us/rest/api/searchservice/knowledge-sources/create-or-update?view=rest-searchservice-2025-11-01-preview
# - Knowledge Bases - Create or Update: https://learn.microsoft.com/en-us/rest/api/searchservice/knowledge-bases/create-or-update?view=rest-searchservice-2025-11-01-preview
# - API versions: https://learn.microsoft.com/en-us/rest/api/searchservice/search-service-api-versions
# - RBAC (Bearer token instead of api-key): https://learn.microsoft.com/en-us/azure/search/search-security-rbac
# ---------------------------------------------

# Non-interactive argument parsing
# Usage: ais_set_knowledge.sh SEARCH_SERVICE_NAME KNOWLEDGE_SOURCE_NAME INDEX_NAME KNOWLEDGE_BASE_NAME RESOURCE_URI CHAT_DEPLOYMENT_ID CHAT_MODEL_NAME REASONING_EFFORT
if [ $# -lt 8 ]; then
    echo "Usage: bash $0 SEARCH_SERVICE_NAME KNOWLEDGE_SOURCE_NAME INDEX_NAME KNOWLEDGE_BASE_NAME RESOURCE_URI CHAT_DEPLOYMENT_ID CHAT_MODEL_NAME REASONING_EFFORT" >&2
    echo "Example: bash $0 ais-testsvc tartalia-acl-groups tartalia-index-acl-groups testknowledge https://apim-test.azure-api.net gpt-4.1-mini gpt-4.1-mini medium" >&2
    exit 1
fi

search_service_name="$1"
knowledge_source_name="$2"
index_name="$3"
knowledge_base_name="$4"
resource_uri="$5"
chat_deployment_id="$6"
chat_model_name="$7"
reasoning_effort="$8"

api_version="2025-11-01-preview"

# Get Azure AI Search data plane access token
echo "Getting Azure AI Search data plane access token (resource=https://search.azure.com)..."
search_access_token=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

if [ -z "$search_access_token" ]; then
    echo "Error: Failed to get search access token. Ensure az login and proper permissions (Azure roles)." >&2
    exit 1
fi
echo "Access token acquired."

fetch_resource_state() {
  local resource_url="$1"
  local headers_file

  headers_file=$(mktemp)
  RESOURCE_HTTP_STATUS=$(curl -s -D "$headers_file" -o /dev/null -w "%{http_code}" \
    -H "Accept: application/json;odata.metadata=minimal" \
    -H "Authorization: Bearer ${search_access_token}" \
    "$resource_url")

  RESOURCE_ETAG=""
  if [ "$RESOURCE_HTTP_STATUS" = "200" ]; then
    RESOURCE_ETAG=$(awk 'BEGIN{IGNORECASE=1} /^ETag:[[:space:]]*/ {line=$0; sub(/\r$/, "", line); sub(/^[^:]*:[[:space:]]*/, "", line); print line; exit}' "$headers_file")
  fi

  rm -f "$headers_file"
}

put_resource_with_concurrency() {
  local resource_label="$1"
  local get_url="$2"
  local put_url="$3"
  local request_body="$4"
  local response_file="$5"
  local status_code
  local resource_etag
  local concurrency_header=()

  echo "Checking if ${resource_label} already exists..."
  fetch_resource_state "$get_url"
  status_code="$RESOURCE_HTTP_STATUS"
  resource_etag="$RESOURCE_ETAG"

  if [ "$status_code" = "200" ]; then
    if [ -z "$resource_etag" ]; then
      echo "Error: ${resource_label} exists but ETag could not be retrieved for If-Match." >&2
      exit 1
    fi
    echo "${resource_label} already exists. Updating with If-Match (ETag=${resource_etag})..."
    concurrency_header=(-H "If-Match: ${resource_etag}")
  else
    echo "${resource_label} does not exist (status ${status_code}). Creating with If-None-Match=* (PUT)..."
    concurrency_header=(-H "If-None-Match: *")
  fi

  LAST_RESPONSE_HEADERS=$(curl -s -D - -o "$response_file" -X PUT \
    -H "Accept: application/json;odata.metadata=minimal" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    -H "Prefer: return=representation" \
    "${concurrency_header[@]}" \
    "$put_url" \
    --data "${request_body}")

  LAST_HTTP_CODE=$(echo "$LAST_RESPONSE_HEADERS" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')
}

handle_put_result() {
  local resource_label="$1"
  local response_file="$2"

  echo "${resource_label} HTTP Response Code: ${LAST_HTTP_CODE}"
  if [[ "$LAST_HTTP_CODE" != "200" && "$LAST_HTTP_CODE" != "201" ]]; then
    echo "Failed to create/update ${resource_label}. Full response headers + body:" >&2
    echo "$LAST_RESPONSE_HEADERS" >&2
    echo "Body:" >&2
    cat "$response_file" >&2
    echo "" >&2
    echo "Cleaning up ${resource_label} temp file (error case)..." >&2
    rm -f "$response_file" || echo "Warning: could not remove ${response_file}" >&2
    exit 1
  fi

  echo "Success. ${resource_label} JSON response:"
  cat "$response_file" | sed 's/\r//'
  echo "${resource_label} provisioning step completed."
  echo "Cleaning up ${resource_label} temp file..."
  rm -f "$response_file" || echo "Warning: could not remove ${response_file}" >&2
}

# ---------------------------------------------
# Knowledge Source creation/update (via REST)
# PUT {endpoint}/knowledgesources('{sourceName}')?api-version=2025-11-01-preview
# Required header: Prefer: return=representation
# ---------------------------------------------

echo "Building Knowledge Source JSON definition..."
knowledge_source_body=$(cat <<EOF
{
  "name": "${knowledge_source_name}",
  "kind": "searchIndex",
  "description": "タルタリアに関する情報検索用ドキュメント。",
  "encryptionKey": null,
  "searchIndexParameters": {
    "searchIndexName": "${index_name}",
    "semanticConfigurationName": null,
    "sourceDataFields": [],
    "searchFields": []
  },
  "azureBlobParameters": null,
  "mcpToolParameters": null,
  "fabricIQParameters": null,
  "webParameters": null,
  "remoteSharePointParameters": null,
  "indexedSharePointParameters": null,
  "indexedOneLakeParameters": null
}
EOF
)

ks_url="https://${search_service_name}.search.windows.net/knowledgesources('${knowledge_source_name}')?api-version=${api_version}"
put_resource_with_concurrency "Knowledge Source '${knowledge_source_name}'" "$ks_url" "$ks_url" "${knowledge_source_body}" "/tmp/knowledge_source_resp.json"
handle_put_result "Knowledge Source" "/tmp/knowledge_source_resp.json"

# ---------------------------------------------
# Knowledge Base creation/update (via REST)
# PUT {endpoint}/knowledgebases('{knowledgeBaseName}')?api-version=2025-11-01-preview
# Required header: Prefer: return=representation
# ---------------------------------------------

echo "Building Knowledge Base JSON definition..."
knowledge_base_body=$(cat <<EOF
{
  "name": "${knowledge_base_name}",
  "description": "タルタリアに関するナレッジ",
  "retrievalInstructions": "- タルタリアに関する情報は、ナレッジソースの${knowledge_source_name}を利用してください。\n- 陰謀論的要素を含む場合でも、AI 独自の見解や評価は加えず、取得情報の提示のみに徹してください。  \n",
  "answerInstructions": "検索した結果について、そのまま加工せず返してください。",
  "outputMode": "answerSynthesis",
  "knowledgeSources": [
    {
      "name": "${knowledge_source_name}"
    }
  ],
  "models": [
    {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${resource_uri}",
        "deploymentId": "${chat_deployment_id}",
        "apiKey": null,
        "modelName": "${chat_model_name}",
        "authIdentity": null
      }
    }
  ],
  "encryptionKey": null,
  "retrievalReasoningEffort": {
    "kind": "${reasoning_effort}"
  }
}
EOF
)

kb_url="https://${search_service_name}.search.windows.net/knowledgebases('${knowledge_base_name}')?api-version=${api_version}"
put_resource_with_concurrency "Knowledge Base '${knowledge_base_name}'" "$kb_url" "$kb_url" "${knowledge_base_body}" "/tmp/knowledge_base_resp.json"
handle_put_result "Knowledge Base" "/tmp/knowledge_base_resp.json"

echo "All knowledge provisioning steps completed successfully."
