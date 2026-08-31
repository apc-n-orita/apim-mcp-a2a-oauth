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

locals {
  # mcp タイプAPIの実パス。実際のバックエンドホストは product ポリシーが oid スティッキーで都度上書きする
  toolbox_uri_template = "/api/projects/${var.project_name}/toolboxes/${var.toolbox_name}/mcp"
}

# --- Named Values (Toolbox Product / API ポリシーが参照) ---

# カンマ区切りの AI Foundry アカウント名一覧 (ポリシーのロードバランシング対象)
# a2a-backends と値は同じでも名前空間を分けるため別名にする
resource "azurerm_api_management_named_value" "toolbox_backends" {
  name                = "toolbox-backends"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "toolbox-backends"
  value               = join(",", var.foundry_backend_names)
}

resource "azurerm_api_management_named_value" "toolbox_project_name" {
  name                = "toolbox-project-name"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "toolbox-project-name"
  value               = var.project_name
}

resource "azurerm_api_management_backend" "toolbox" {
  for_each            = toset(var.foundry_backend_names)
  name                = "toolbox-${each.value}"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  protocol            = "http"
  url                 = "https://${each.value}.services.ai.azure.com"
  description         = "Toolbox mcp API backend for Foundry account ${each.value}"
}

resource "azapi_resource" "toolbox_api" {
  type                      = "Microsoft.ApiManagement/service/apis@2025-03-01-preview"
  name                      = var.toolbox_name
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      apiRevision          = "1"
      displayName          = var.toolbox_name
      path                 = var.toolbox_name
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
            uriTemplate = local.toolbox_uri_template
          }
        }
      }
      backendId   = azurerm_api_management_backend.toolbox[var.foundry_backend_names[0]].name
      serviceUrl  = null
      description = "Foundry Toolbox MCP endpoint, oid-sticky load balanced across Foundry backends (same method as tartaria-agent's a2a API)"
      subscriptionKeyParameterNames = {
        header = "Ocp-Apim-Subscription-Key"
        query  = "subscription-key"
      }
    }
  }

  depends_on = [
    azurerm_api_management_named_value.toolbox_backends,
    azurerm_api_management_named_value.toolbox_project_name,
  ]
}

# --- API ポリシー (base のみ。実処理は Toolbox Product ポリシー側で完結させる) ---
resource "azurerm_api_management_api_policy" "toolbox" {
  api_name            = azapi_resource.toolbox_api.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/files/policy/toolbox_api_policy.xml")
}

# --- toolbox API の Application Insights 診断設定 ---
resource "azurerm_api_management_api_diagnostic" "toolbox" {
  identifier                = "applicationinsights"
  api_name                  = azapi_resource.toolbox_api.name
  api_management_name       = var.api_management_name
  resource_group_name       = var.resource_group_name
  api_management_logger_id  = var.api_management_logger_id
  sampling_percentage       = var.diagnostic_sampling_percentage
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    data_masking {
      query_params {
        mode  = "Hide"
        value = "*"
      }
    }
  }

  backend_request {
    data_masking {
      query_params {
        mode  = "Hide"
        value = "*"
      }
    }
  }
}

# --- Product: Toolbox ---
resource "azurerm_api_management_product" "toolbox" {
  product_id            = "toolbox"
  api_management_name   = var.api_management_name
  resource_group_name   = var.resource_group_name
  display_name          = "Toolbox"
  description           = "oid スティッキー負荷分散 (a2a と同方式)。JSON-RPC サーキットブレイカーなし。バックエンド認証はクライアントの元トークンをパススルー"
  subscription_required = false
  published             = false
}

# toolbox API を Toolbox Product に紐付け
resource "azurerm_api_management_product_api" "toolbox" {
  api_name            = azapi_resource.toolbox_api.name
  product_id          = azurerm_api_management_product.toolbox.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
}

# --- Toolbox Product ポリシー ---
# Entra ID JWT 検証 (audience のみ、role claim チェックなし) + {{toolbox-backends}} のスティッキー LB
# + リトライ/フェイルオーバー (JSON-RPC 検知なし) + バックエンド認証はクライアントトークンをパススルー
resource "azurerm_api_management_product_policy" "toolbox" {
  product_id          = azurerm_api_management_product.toolbox.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/files/policy/toolbox_product_policy.xml")

  depends_on = [
    azurerm_api_management_named_value.toolbox_backends,
    azurerm_api_management_named_value.toolbox_project_name,
  ]
}
