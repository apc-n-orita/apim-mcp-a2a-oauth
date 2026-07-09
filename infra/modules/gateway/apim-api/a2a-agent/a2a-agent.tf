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
  # 先頭の Foundry を既定バックエンドとする (実際のルーティングは A2A Product ポリシーが
  # {{a2a-backends}} を使って oid ごとのスティッキー LB + フェイルオーバーで決定する)
  default_backend_base_url = "https://dummy.services.ai.azure.com/api/projects/${var.project_name}/agents/${var.agent_name}/endpoint/protocols/a2a"

}

# --- Named Values (A2A Product / API ポリシーが参照) ---

# カンマ区切りの AI Foundry アカウント名一覧 (ポリシーのロードバランシング対象)
resource "azurerm_api_management_named_value" "a2a_backends" {
  name                = "a2a-backends"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "a2a-backends"
  value               = join(",", var.foundry_backend_names)
}

# A2A クライアント認可用 Entra アプリの App ID (audience api://{{a2a-oauth-app-id}}/)
resource "azurerm_api_management_named_value" "a2a_oauth_app_id" {
  name                = "a2a-oauth-app-id"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "a2a-oauth-app-id"
  value               = var.oauth_app_client_id
  secret              = true
}

# AI Foundry プロジェクト名 (バックエンド URL の組み立てに使用)
resource "azurerm_api_management_named_value" "ai_foundry_project" {
  name                = "ai-foundry-project"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "ai-foundry-project"
  value               = var.project_name
}

# App Insights IngestionEndpoint (JSON-RPC エラーの exceptions 送信先。末尾スラッシュなし)
resource "azurerm_api_management_named_value" "app_insights_ingestion_endpoint" {
  name                = "app-insights-ingestion-endpoint"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "app-insights-ingestion-endpoint"
  value               = var.application_insights_ingestion_endpoint
  secret              = true
}

# App Insights インストルメンテーションキー
resource "azurerm_api_management_named_value" "app_insights_ikey" {
  name                = "app-insights-ikey"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "app-insights-ikey"
  value               = var.application_insights_instrumentation_key
  secret              = true
}

# --- tartaria-agent API (APIM ネイティブ a2a タイプ) ---
# 2025-09-01-preview 以降の API バージョンでのみ管理可能
resource "azapi_resource" "a2a_api" {
  type                      = "Microsoft.ApiManagement/service/apis@2025-09-01-preview"
  name                      = var.agent_name
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      type                 = "a2a"
      displayName          = var.agent_name
      description          = ""
      path                 = "a2a/${var.agent_name}"
      protocols            = ["https"]
      subscriptionRequired = false
      a2aProperties = {
        agentCardBackendUrl = "${local.default_backend_base_url}/agentCard/v0.3"
        agentCardPath       = "/agent-card.json"
      }
      jsonRpcProperties = {
        backendUrl = local.default_backend_base_url
        path       = "/"
      }
    }
  }

  depends_on = [
    azurerm_api_management_named_value.a2a_backends,
    azurerm_api_management_named_value.ai_foundry_project,
  ]
}

# --- API ポリシー (oid ごとのレートリミット + ルーティング先ヘッダー付与) ---
resource "azurerm_api_management_api_policy" "a2a_api" {
  api_name            = azapi_resource.a2a_api.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content = templatefile("${path.module}/files/policy/a2a_api_policy.xml", {
    rate_limit_calls = var.rate_limit_calls
  })
}

# --- tartaria-agent API の Application Insights 診断設定 ---
# 前提: 既存 APIM に var.apim_logger_name の logger が存在すること
resource "azurerm_api_management_api_diagnostic" "a2a_api" {
  identifier                = "applicationinsights"
  api_name                  = azapi_resource.a2a_api.name
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

# --- Product: A2A ---
resource "azurerm_api_management_product" "a2a" {
  product_id            = "a2a"
  api_management_name   = var.api_management_name
  resource_group_name   = var.resource_group_name
  display_name          = "A2A"
  description           = "A2Aのポリシー"
  subscription_required = false
  published             = false
}

# tartaria-agent API を A2A Product に紐付け
resource "azurerm_api_management_product_api" "a2a" {
  api_name            = azapi_resource.a2a_api.name
  product_id          = azurerm_api_management_product.a2a.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
}

# --- A2A Product ポリシー ---
# Entra ID JWT 検証 (roles クレーム = エージェント名) + {{a2a-backends}} のスティッキー LB
# + リトライ/フェイルオーバー + JSON-RPC エラーの App Insights exceptions 送信 + MSI 認証
resource "azurerm_api_management_product_policy" "a2a" {
  product_id          = azurerm_api_management_product.a2a.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/files/policy/a2a_product_policy.xml")

  depends_on = [
    azurerm_api_management_named_value.a2a_backends,
    azurerm_api_management_named_value.a2a_oauth_app_id,
    azurerm_api_management_named_value.ai_foundry_project,
    azurerm_api_management_named_value.app_insights_ingestion_endpoint,
    azurerm_api_management_named_value.app_insights_ikey,
  ]
}
