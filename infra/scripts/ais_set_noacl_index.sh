#!/bin/bash

# Non-interactive argument parsing
# Usage: aif_set_sh SUBSCRIPTION_ID RESOURCE_GROUP SEARCH_SERVICE_NAME DATASOURCE_NAME STORAGE_ACCOUNT_NAME BLOB_CONTAINER_NAME BLOB_QUERY INDEX_NAME SKILLSET_NAME INDEXER_NAME

if [ $# -lt 13 ]; then
  echo "Usage: bash $0 SUBSCRIPTION_ID RESOURCE_GROUP SEARCH_SERVICE_NAME DATASOURCE_NAME STORAGE_ACCOUNT_NAME BLOB_CONTAINER_NAME BLOB_QUERY INDEX_NAME SKILLSET_NAME INDEXER_NAME RESOURCE_URI DEPLOYMENT_ID MODEL_NAME" >&2
  echo "Example: bash $0 00000000-0000-0000-0000-000000000000 my-rg mysearchsvc ds-blob mystorage rawdocs '' mainindex mainskill mainindexer https://apim-test.azure-api.net text-embedding-3-small text-embedding-3-small" >&2
  exit 1
fi

subscription_id="$1"
resource_group="$2"
search_service_name="$3"
datasource_name="$4"
storage_account_name="$5"
blob_container_name="$6"
blob_query="$7"          # pass '' for empty
index_name="$8"
skillset_name="$9"
indexer_name="${10}"
resource_uri="${11}"
deployment_id="${12}"
model_name="${13}"

if [ "$model_name" = "text-embedding-3-large" ]; then
  dimensions=3072
else
  dimensions=1536
fi

# Get Azure access token
echo "Getting Azure access token..."
access_token=$(az account get-access-token --query accessToken -o tsv)

if [ -z "$access_token" ]; then
    echo "Error: Failed to get access token. Please make sure you're logged in with 'az login'"
    exit 1
fi

# ---------------------------------------------
# Azure AI Search Data Source creation (via REST)
# Docs references:
# - Data Sources - Create Or Update (2025-11-01-preview): https://learn.microsoft.com/en-us/rest/api/searchservice/data-sources/create-or-update?view=rest-searchservice-2025-11-01-preview
# - Data Sources - Get (2025-11-01-preview): https://learn.microsoft.com/en-us/rest/api/searchservice/data-sources/get?view=rest-searchservice-2025-11-01-preview
# - RBAC (Bearer token instead of api-key): https://learn.microsoft.com/en-us/azure/search/search-security-rbac
# ---------------------------------------------


api_version="2025-11-01-preview"  # preview version required for flightingOptIn

echo "Getting Azure AI Search data plane access token (resource=https://search.azure.com)..."
search_access_token=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

if [ -z "$search_access_token" ]; then
    echo "Error: Failed to get search access token. Ensure az login and proper permissions (Azure roles)." >&2
    exit 1
fi

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
    -H "Prefer: return=representation" \
    "${concurrency_header[@]}" \
    -H "Authorization: Bearer ${search_access_token}" \
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
    echo "Cleaning up ${resource_label} temp file (error case)..." >&2
    rm -f "$response_file" || echo "Warning: could not remove ${response_file}" >&2
    exit 1
  fi

  echo "Success. ${resource_label} response JSON:"
  cat "$response_file" | sed 's/\r//'
  echo "${resource_label} provisioning step completed."
  echo "Cleaning up ${resource_label} temp file..."
  rm -f "$response_file" || echo "Warning: could not remove ${response_file}" >&2
}

storage_account_resource_id="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Storage/storageAccounts/${storage_account_name}"
connection_string="ResourceId=${storage_account_resource_id};"  # Managed identity style connection string

# Build JSON body for ADLS Gen2 ACL-aware datasource
datasource_body=$(cat <<EOF
{
  "name": "${datasource_name}",
  "type": "adlsgen2",
  "credentials": {
    "connectionString": "${connection_string}"
  },
  "container": {
    "name": "${blob_container_name}"$( [ -n "$blob_query" ] && printf ",\n    \"query\": \"%s\"" "$blob_query" )
  },
  "dataDeletionDetectionPolicy": {
    "@odata.type": "#Microsoft.Azure.Search.NativeBlobSoftDeleteDeletionDetectionPolicy"
  }
}
EOF
)

datasource_url="https://${search_service_name}.search.windows.net/datasources('${datasource_name}')?api-version=${api_version}"
put_resource_with_concurrency "datasource '${datasource_name}'" "$datasource_url" "$datasource_url" "${datasource_body}" "/tmp/datasource_resp.json"
handle_put_result "datasource" "/tmp/datasource_resp.json"

# ---------------------------------------------
# Azure AI Search Index creation/update (via REST)
# Docs references consulted:
# - Create or Update Index: https://learn.microsoft.com/en-us/rest/api/searchservice/indexes/create-or-update
# - Semantic configuration: https://learn.microsoft.com/en-us/azure/search/semantic-how-to-configure
# - Field definitions: https://learn.microsoft.com/en-us/azure/search/search-how-to-create-search-index#configure-field-definitions
# ---------------------------------------------


echo "Building index definition JSON..."
index_body=$(cat <<EOF
{
  "name": "${index_name}",
  "description": "Search index for knowledge source 'tartalia'. has acl fields.",
  "fields": [
    {"name": "uid", "type": "Edm.String", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": true, "facetable": false, "key": true, "analyzer": "keyword", "synonymMaps": []},
    {"name": "snippet_parent_id", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "blob_url", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "snippet", "type": "Edm.String", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "image_snippet_parent_id", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "snippet_vector", "type": "Collection(Edm.Single)", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "dimensions": ${dimensions}, "vectorSearchProfile": "tartalia-vector-search-profile", "synonymMaps": []},
    {"name": "title", "type": "Edm.String", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "analyzer": "standard.lucene", "synonymMaps": []},
    {"name": "metadata_storage_name", "type": "Edm.String", "searchable": true, "filterable": true, "retrievable": true, "stored": true, "sortable": true, "facetable": false, "key": false, "analyzer": "standard.lucene", "synonymMaps": []},
    {"name": "metadata_storage_path", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []}
  ],
  "scoringProfiles": [],
  "suggesters": [],
  "analyzers": [],
  "normalizers": [],
  "tokenizers": [],
  "tokenFilters": [],
  "charFilters": [],
  "similarity": {"@odata.type": "#Microsoft.Azure.Search.BM25Similarity"},
  "semantic": {
    "defaultConfiguration": "tartalia-semantic-configuration",
    "configurations": [
      {
        "name": "tartalia-semantic-configuration",
        "flightingOptIn": false,
        "rankingOrder": "BoostedRerankerScore",
        "prioritizedFields": {
          "titleField": {"fieldName": "title"},
          "prioritizedContentFields": [{"fieldName": "snippet"}],
          "prioritizedKeywordsFields": []
        }
      }
    ]
  },
  "vectorSearch": {
    "algorithms": [
      {
        "name": "tartalia-vector-search-algorithm",
        "kind": "hnsw",
        "hnswParameters": {"metric": "cosine", "m": 4, "efConstruction": 400, "efSearch": 500}
      }
    ],
    "profiles": [
      {
        "name": "tartalia-vector-search-profile",
        "algorithm": "tartalia-vector-search-algorithm",
        "vectorizer": "tartalia-vectorizer",
        "compression": "tartalia-vector-search-scalar-quantization"
      }
    ],
    "vectorizers": [
      {
        "name": "tartalia-vectorizer",
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${resource_uri}",
          "deploymentId": "${deployment_id}",
          "modelName": "${model_name}"
        }
      }
    ],
    "compressions": [
      {
        "name": "tartalia-vector-search-scalar-quantization",
        "kind": "scalarQuantization",
        "scalarQuantizationParameters": {"quantizedDataType": "int8"},
        "rescoringOptions": {"enableRescoring": true, "defaultOversampling": 4, "rescoreStorageMethod": "preserveOriginals"}
      }
    ]
  }
}
EOF
)

index_get_url="https://${search_service_name}.search.windows.net/indexes('${index_name}')?api-version=${api_version}"
index_put_url="https://${search_service_name}.search.windows.net/indexes('${index_name}')?allowIndexDowntime=true&api-version=${api_version}"
put_resource_with_concurrency "index '${index_name}'" "$index_get_url" "$index_put_url" "${index_body}" "/tmp/index_resp.json"
handle_put_result "index" "/tmp/index_resp.json"

# ---------------------------------------------
# Azure AI Search Skillset creation/update (via REST)
# Docs references consulted:
# - Create Skillset: https://learn.microsoft.com/en-us/rest/api/searchservice/skillsets/create
# - Skillset definition & skills: https://learn.microsoft.com/en-us/azure/search/cognitive-search-defining-skillset#add-a-skillset-definition
# ---------------------------------------------


echo "Building skillset JSON definition..."
skillset_body=$(cat <<EOF
{
  "name": "${skillset_name}",
  "description": "Skillset for knowledge source 'tartalia-acl' - text processing only",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
      "name": "SplitSkill",
      "description": "Split document content into chunks",
      "context": "/document",
      "defaultLanguageCode": "en",
      "textSplitMode": "pages",
      "maximumPageLength": 2000,
      "pageOverlapLength": 200,
      "maximumPagesToTake": 0,
      "unit": "characters",
      "inputs": [{"name": "text", "source": "/document/content", "inputs": []}],
      "outputs": [{"name": "textItems", "targetName": "pages"}]
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "AzureOpenAIEmbeddingSkill",
      "description": "Generate embeddings",
      "context": "/document/pages/*",
      "resourceUri": "${resource_uri}",
      "deploymentId": "${deployment_id}",
      "dimensions": ${dimensions},
      "modelName": "${model_name}",
      "inputs": [{"name": "text", "source": "/document/pages/*", "inputs": []}],
      "outputs": [{"name": "embedding", "targetName": "text_vector"}]
    }
  ],
  "indexProjections": {
    "selectors": [
      {
        "targetIndexName": "${index_name}",
        "parentKeyFieldName": "snippet_parent_id",
        "sourceContext": "/document/pages/*",
        "mappings": [
          {"name": "snippet_vector", "source": "/document/pages/*/text_vector", "inputs": []},
          {"name": "snippet", "source": "/document/pages/*", "inputs": []},
          {"name": "metadata_storage_path", "source": "/document/metadata_storage_path", "inputs": []},
          {"name": "title", "source": "/document/title", "inputs": []},
          {"name": "metadata_storage_name", "source": "/document/metadata_storage_name", "inputs": []}
        ]
      }
    ],
    "parameters": {"projectionMode": "skipIndexingParentDocuments"}
  }
}
EOF
)

skillset_url="https://${search_service_name}.search.windows.net/skillsets('${skillset_name}')?api-version=${api_version}"
put_resource_with_concurrency "skillset '${skillset_name}'" "$skillset_url" "$skillset_url" "${skillset_body}" "/tmp/skillset_resp.json"
handle_put_result "skillset" "/tmp/skillset_resp.json"

# ---------------------------------------------
# Azure AI Search Indexer creation/update (via REST)
# Docs references consulted:
# - Create Indexer: https://learn.microsoft.com/en-us/rest/api/searchservice/indexers/create
# - Field mappings functions (base64Encode): https://learn.microsoft.com/en-us/azure/search/search-indexer-field-mappings#mapping-functions-and-examples
# - Indexer request body parameters: https://learn.microsoft.com/en-us/rest/api/searchservice/create-indexer#request-body
# ---------------------------------------------


echo "Building indexer JSON definition..."
indexer_body=$(cat <<EOF
{
  "name": "${indexer_name}",
  "dataSourceName": "${datasource_name}",
  "skillsetName": "${skillset_name}",
  "targetIndexName": "${index_name}",
  "parameters": {
    "maxFailedItems": -1,
    "maxFailedItemsPerBatch": -1,
    "configuration": {}
  },
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_storage_name",
      "targetFieldName": "title"
    },
    {
      "sourceFieldName": "metadata_storage_path",
      "targetFieldName": "snippet_parent_id",
      "mappingFunction": {
        "name": "base64Encode",
        "parameters": {"useHttpServerUtilityUrlTokenEncode": false}
      }
    }
  ],
  "outputFieldMappings": []
}
EOF
)

indexer_url="https://${search_service_name}.search.windows.net/indexers('${indexer_name}')?api-version=${api_version}"
put_resource_with_concurrency "indexer '${indexer_name}'" "$indexer_url" "$indexer_url" "${indexer_body}" "/tmp/indexer_resp.json"
handle_put_result "indexer" "/tmp/indexer_resp.json"
