terraform {
  required_providers {
    azurerm = {
      version = "~>4.80.0"
      source  = "hashicorp/azurerm"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~>2.0.0"
    }
  }
}

resource "azurerm_api_management_backend" "mcp" {
  name                = "mcp-backend-${var.api_name}"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  protocol            = "http"
  url                 = var.mcp_url
  description         = "Backend for ${var.api_name} mcp"
}

# apim-mcp-oauth の modules/core/gateway/apim-api/mcp-api を参考にした、APIM ネイティブ mcp タイプのAPI
resource "azapi_resource" "mcp_api" {
  type                      = "Microsoft.ApiManagement/service/apis@2025-03-01-preview"
  name                      = var.api_name
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      apiRevision          = "1"
      displayName          = var.api_name
      path                 = var.api_name
      protocols            = ["https"]
      type                 = "mcp"
      subscriptionRequired = false
      authenticationSettings = {
        oAuth2                          = null
        oAuth2AuthenticationSettings    = []
        openid                          = null
        openidAuthenticationSettings    = []
        returnProtectedResourceMetadata = false
      }
      mcpProperties = {
        endpoints = {
          mcp = {
            uriTemplate = var.mcp_api_uri_template
          }
        }
      }
      backendId   = azurerm_api_management_backend.mcp.name
      serviceUrl  = null
      description = var.api_description
      subscriptionKeyParameterNames = {
        header = "Ocp-Apim-Subscription-Key"
        query  = "subscription-key"
      }
    }
  }
}

# --- API ポリシー (このAPIスコープで完結させる。共有の"MCP"製品ポリシーには乗せない) ---
#   inbound  : Authorization ヘッダーの検証は audience=https://search.azure.com で行う。
#              これはツール呼び出し元(agent/クライアント)がACL評価対象のユーザー本人であることの証明であり、
#              そのまま x-ms-query-source-authorization としてバックエンドへ引き継ぐ。
#   backend  : Function の Easy Auth (audience api://{oauth-app-id}/) は別トークンで満たす。
#              named value "oauth-app-id" は apim-mcp-oauth 側の mcp-product モジュールが
#              同じ共有APIMに既に作成済みなので、ここでは新規作成せずそのまま {{oauth-app-id}} を参照する。
#              APIM のマネージド ID (システム割り当て) は Mcp.Invoke ロールを oauth-app 上に
#              既に持っている (apim-mcp-oauth 側で付与済み) ため、authentication-managed-identity で
#              取得したトークンがそのまま Easy Auth の役割チェックを通過する。
resource "azurerm_api_management_api_policy" "mcp" {
  api_name            = azapi_resource.mcp_api.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/files/policy/mcp_api_policy.xml")
}

resource "azurerm_api_management_api_diagnostic" "mcp" {
  identifier                = "applicationinsights"
  api_name                  = azapi_resource.mcp_api.name
  api_management_name       = var.api_management_name
  resource_group_name       = var.resource_group_name
  api_management_logger_id  = var.api_management_logger_id
  sampling_percentage       = var.diagnostic_sampling_percentage
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes     = 0
    headers_to_log = []
  }

  frontend_response {
    body_bytes     = 0
    headers_to_log = []
  }

  backend_request {
    body_bytes     = 0
    headers_to_log = []
  }

  backend_response {
    body_bytes     = 0
    headers_to_log = []
  }
}
