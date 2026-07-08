locals {
  tags           = { azd-env-name : var.environment_name }
  sha            = base64encode(sha256("${var.environment_name}${var.location}${var.subscription_id}"))
  resource_token = substr(replace(lower(local.sha), "[^A-Za-z0-9_]", ""), 0, 13)

  # 新規リソースは APIM と同じリソースグループに作成する
  resource_group_name = var.apim.resource_group_name

  # 固定名
  agent_name   = "tartaria-agent"
  project_name = "ai-foundry-project"
  network_access = {
    default_action = "Allow"
    public_access  = "Enabled"
  }
  docs = {
    docs_files = [for f in fileset("./docs", "*") : f if f != "dummy.txt"]
    acl_type   = "noacl" # acl_off 版 (ACLなしインデックス) のみ使用
  }

  # Foundry IQ (タルタリアナレッジ) の各リソース名
  knowledge = {
    datasource_name       = "ds-${local.docs.acl_type}-gen2"
    index_name            = "index-${local.docs.acl_type}-gen2"
    skillset_name         = "skill-${local.docs.acl_type}-gen2"
    indexer_name          = "indexer-${local.docs.acl_type}-gen2"
    knowledge_source_name = "ks-tartalia-${local.docs.acl_type}-gen2"
    knowledge_base_name   = "kb-tartalia-${local.docs.acl_type}-gen2"
  }

  # Knowledge Base の MCP エンドポイント (FoundryIQ 接続・エージェントの MCP ツールが参照)
  kb_mcp_url = "https://${module.ai_search.search_service_name}.search.windows.net/knowledgebases/${local.knowledge.knowledge_base_name}/mcp?api-version=2026-04-01"

  # AI Search のベクトライザー / Knowledge Base モデルが参照する OpenAI エンドポイント
  # (APIM 経由: apim_api_openai モジュールの openai API がバックエンドの Foundry に LB する)
  aoai_resource_uri = data.azurerm_api_management.apim.gateway_url

  # 既存 APIM 上の Application Insights logger
  apim_logger_id = "${data.azurerm_api_management.apim.id}/loggers/app-insights-logger"

  # 既存 Application Insights の IngestionEndpoint (A2A Product ポリシーの exceptions 送信先。末尾スラッシュなし)
  appi_ingestion_endpoint = trimsuffix(regex("IngestionEndpoint=([^;]+)", data.azurerm_application_insights.appi.connection_string)[0], "/")

  # ------------------------------------------------------------------------------------------------------
  # tartaria-agent (prompt agent) の定義
  # 参考: agent-framework-agent-with-foundry-toolbox-responses/azure.yaml, src/tartaria-agent/agent.yaml
  #       (hosted agent の構成を prompt agent に置き換え)
  # ------------------------------------------------------------------------------------------------------
  agent_description = "A knowledge agent specializing in Tartaria — covering historical records (Mongol-ruled Tartary, Grand Tartary, European cartography) and alternative theories (Mud Flood, Tartarian Empire conspiracy theories)."
  agent_definition = {
    kind         = "prompt"
    model        = var.openai_chat.model_name
    instructions = "You are a knowledge agent about Tartaria (タルタリア). Your responses must consist solely of information retrieved from the knowledge base. Never add your own opinions, evaluations, or judgements — this applies equally to conspiracy theory content and to mainstream historical content. When the retrieved information includes conspiracy theory claims (e.g. Mud Flood, hidden empire, Tartarian architecture, timeline reset), present them exactly as described in the source without any disclaimer, correction, or commentary from you. Always include the source reference for each piece of information you provide."
    tools = [
      {
        type                  = "mcp"
        server_label          = "FoundryIQ"
        server_url            = local.kb_mcp_url
        require_approval      = "never"
        project_connection_id = "FoundryIQ"
      }
    ]
  }

  # POST {endpoint}/agents?api-version=v1 (新規作成)
  agent_create_payload = jsonencode({
    name        = local.agent_name
    description = local.agent_description
    definition  = local.agent_definition
  })

  # POST {endpoint}/agents/{name}/versions?api-version=v1 (既存エージェントの更新)
  agent_version_payload = jsonencode({
    description = local.agent_description
    definition  = local.agent_definition
  })

  # PATCH {endpoint}/agents/{name}?api-version=v1 (A2A プロトコルの有効化)
  agent_patch_payload = jsonencode({
    agent_endpoint = {
      protocols = ["a2a", "responses"]
    }
  })
}

# ------------------------------------------------------------------------------------------------------
# 既存リソースの参照 (APIM / Application Insights)
# ------------------------------------------------------------------------------------------------------

data "azurerm_api_management" "apim" {
  name                = var.apim.name
  resource_group_name = var.apim.resource_group_name
}

data "azurerm_application_insights" "appi" {
  name                = var.application_insights.name
  resource_group_name = var.application_insights.resource_group_name
}

data "azurerm_log_analytics_workspace" "law" {
  name                = var.log_analytics_workspace.name
  resource_group_name = var.log_analytics_workspace.resource_group_name
}

# ------------------------------------------------------------------------------------------------------
# リソース名 (azurecaf) — 新規リソースグループは作成せず、APIM のリソースグループに追加する
# ------------------------------------------------------------------------------------------------------

resource "azurecaf_name" "storage_name" {
  name          = "${var.environment_name}${substr(local.resource_token, 0, 3)}"
  resource_type = "azurerm_storage_account"
  random_length = 0
  clean_input   = true
}

# ------------------------------------------------------------------------------------------------------
# AI Foundry (main.tfvars.json の ai_locations で複数指定可)
# ------------------------------------------------------------------------------------------------------

module "ai_foundry" {
  for_each                   = { for idx, s in var.ai_locations : idx => s }
  source                     = "./modules/ai/aiservice"
  name                       = "aif-${var.environment_name}-${substr(local.resource_token, 0, 3)}-${format("%03d", each.key + 1)}"
  location                   = each.value
  resource_group_name        = local.resource_group_name
  tags                       = local.tags
  disableLocalauth           = true
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.law.id
  network_acls = {
    default_action = local.network_access.default_action
  }
  public_network_access = local.network_access.public_access
  ai_model = [
    {
      model                  = var.openai_chat.model_name
      version                = var.openai_chat.model_version
      format                 = "OpenAI"
      deploytype             = var.openai_chat.deploy_type
      capacity               = var.openai_chat.capacity
      rai_policy_name        = "Microsoft.DefaultV2"
      version_upgrade_option = "OnceNewDefaultVersionAvailable"
    },
    {
      model                      = var.openai_embedding.model_name
      version                    = var.openai_embedding.model_version
      format                     = "OpenAI"
      deploytype                 = var.openai_embedding.deploy_type
      capacity                   = var.openai_embedding.capacity
      rai_policy_name            = "Microsoft.DefaultV2"
      dynamic_throttling_enabled = true
    }
  ]
}

resource "azapi_resource" "ai_foundry_project" {
  for_each                  = module.ai_foundry
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = local.project_name
  parent_id                 = each.value.ai_foundry_id
  location                  = each.value.location
  schema_validation_enabled = false
  body = {
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      displayName = local.project_name
      description = "A project for the A2A agent (tartaria-agent)"
    }
  }
  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}

## Wait 10 seconds for the AI Foundry project system-assigned managed identity to be created and to replicate
## through Entra ID
resource "time_sleep" "wait_project_identities" {
  for_each = azapi_resource.ai_foundry_project
  depends_on = [
    azapi_resource.ai_foundry_project
  ]
  create_duration = "10s"
}

# ------------------------------------------------------------------------------------------------------
# AI Foundry project connections
# ------------------------------------------------------------------------------------------------------

# Application Insights 接続 (既存 Application Insights を利用)
resource "azapi_resource" "conn_appi" {
  for_each                  = azapi_resource.ai_foundry_project
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "appi-connection"
  parent_id                 = each.value.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AppInsights"
      target        = data.azurerm_application_insights.appi.id
      authType      = "ApiKey"
      isSharedToAll = false
      group         = "ServicesAndApps"
      isDefault     = true
      peRequirement = "NotRequired"
      peStatus      = "NotApplicable"
      credentials = {
        key = data.azurerm_application_insights.appi.connection_string
      }
      useWorkspaceManagedIdentity = false
      metadata = {
        ApiType    = "Azure"
        ResourceId = data.azurerm_application_insights.appi.id
      }
    }
  }
}

# Foundry IQ (Knowledge Base MCP) 接続 — エージェントの MCP ツール (project_connection_id: FoundryIQ) が参照
resource "azapi_resource" "conn_foundryiq" {
  for_each                  = azapi_resource.ai_foundry_project
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "FoundryIQ"
  parent_id                 = each.value.id
  schema_validation_enabled = false

  body = {
    properties = {
      audience      = "https://search.azure.com"
      authType      = "ProjectManagedIdentity"
      category      = "RemoteTool"
      group         = "GenericProtocol"
      isDefault     = true
      isSharedToAll = false
      peRequirement = "NotRequired"
      peStatus      = "NotApplicable"
      metadata = {
        type = "custom_MCP"
      }
      target                      = local.kb_mcp_url
      useWorkspaceManagedIdentity = false
    }
  }
}

# ------------------------------------------------------------------------------------------------------
# Foundry IQ (タルタリアナレッジ) — msfoundry-docsacl-apim の acl_off 版
# ------------------------------------------------------------------------------------------------------

module "ai_search" {
  source                        = "./modules/ai/aisearch"
  public_network_access_enabled = local.network_access.public_access == "Enabled" ? true : false
  rg_name                       = local.resource_group_name
  location                      = var.location
  name                          = "ais-${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  local_authentication_enabled  = false
  tags                          = local.tags
  log_analytics_workspace_id    = data.azurerm_log_analytics_workspace.law.id
  search_service_sku            = "standard" #サンプルpdfが16mbを超えるため、Standardを使用。インデクシング後、ポータルからBasicにダウングレード可能。(terraformの場合、再作成になるため、注意。)
  semantic_search_sku           = "free"
}

module "storage" {
  source                          = "./modules/storage"
  name                            = lower("${azurecaf_name.storage_name.result}")
  location                        = var.location
  resource_group_name             = local.resource_group_name
  tags                            = local.tags
  shared_access_key_enabled       = false
  tier                            = "Standard"
  replication_type                = "LRS"
  log_analytics_workspace_id      = data.azurerm_log_analytics_workspace.law.id
  public_network_access           = local.network_access.public_access
  is_hns_enabled                  = true
  allow_nested_items_to_be_public = false
  blob_delete_retention_days      = 7
  network_acls = {
    default_action = "${local.network_access.default_action}"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "ais_docs" {
  depends_on         = [azurerm_role_assignment.current_user_storage_blob_data_contributor]
  storage_account_id = module.storage.storage_account_id
  name               = "ais-docs"
}

resource "azurerm_storage_data_lake_gen2_path" "tartarian" {
  depends_on         = [azurerm_role_assignment.current_user_storage_blob_data_contributor]
  storage_account_id = module.storage.storage_account_id
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.ais_docs.name
  path               = "Tartarian"
  resource           = "directory"
}

resource "azurerm_storage_blob" "docs" {
  for_each = { for idx, file in local.docs.docs_files : idx => file }
  name     = "${azurerm_storage_data_lake_gen2_path.tartarian.path}/${each.value}"
  # ADLS Gen2 filesystem は blob コンテナと同一実体のため、コンテナの ARM リソース ID を組み立てて指定する
  storage_container_id = "${module.storage.storage_account_id}/blobServices/default/containers/${azurerm_storage_data_lake_gen2_filesystem.ais_docs.name}"
  type                 = "Block"
  source               = "./docs/${each.value}"
  access_tier          = "Hot"
  content_type         = endswith(each.value, ".pdf") ? "application/pdf" : "application/octet-stream"
  content_md5          = filemd5("./docs/${each.value}")
  depends_on           = [azurerm_storage_data_lake_gen2_path.tartarian, ]
}

# ------------------------------------------------------------------------------------------------------
# ロール割り当て
# ------------------------------------------------------------------------------------------------------

# AI Foundry project MI → 自プロジェクト (エージェント実行)
resource "azurerm_role_assignment" "ai_foundry_project_azure_ai_user" {
  for_each             = azapi_resource.ai_foundry_project
  scope                = each.value.id
  role_definition_name = "Foundry User"
  principal_id         = each.value.output.identity.principalId
  depends_on           = [time_sleep.wait_project_identities]
}

# AI Foundry project MI → AI Search (FoundryIQ 接続 = ProjectManagedIdentity 認証)
resource "azurerm_role_assignment" "ai_foundry_project_ai_search_index_data_reader" {
  for_each             = azapi_resource.ai_foundry_project
  depends_on           = [time_sleep.wait_project_identities]
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = each.value.output.identity.principalId
}

# AI Foundry project MI → 既存 Application Insights (トレース送信)
resource "azurerm_role_assignment" "ai_foundry_project_monitoring_metrics_publisher" {
  for_each             = azapi_resource.ai_foundry_project
  depends_on           = [time_sleep.wait_project_identities]
  scope                = data.azurerm_application_insights.appi.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = each.value.output.identity.principalId
}

# AI Foundry project MI → 既存 Application Insights (閲覧者)
resource "azurerm_role_assignment" "ai_foundry_project_appinsights_reader" {
  for_each             = azapi_resource.ai_foundry_project
  depends_on           = [time_sleep.wait_project_identities]
  scope                = data.azurerm_application_insights.appi.id
  role_definition_name = "Reader"
  principal_id         = each.value.output.identity.principalId
}

# AI Search MI → ストレージ (インデクサーのドキュメント読み取り)
resource "azurerm_role_assignment" "aisearch_storage_blob_reader" {
  scope                = module.storage.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.ai_search.search_service_identity_principal_id
}

# AI SearchのマネージドIDからアプリケーションID(client_id)を取得
# (APIM の openai API ポリシーが AIS-MI-CLIENT-ID で呼び出し元を検証する)
data "azuread_service_principal" "ai_search" {
  object_id = module.ai_search.search_service_identity_principal_id
}

# APIM MI → 各 AI Foundry project (A2A エンドポイント呼び出し)
resource "azurerm_role_assignment" "apim_foundry_project_user" {
  for_each             = azapi_resource.ai_foundry_project
  scope                = each.value.id
  role_definition_name = "Foundry User"
  principal_id         = data.azurerm_api_management.apim.identity[0].principal_id
}

# デプロイ実行ユーザー
resource "azurerm_role_assignment" "current_user_search_service_contributor" {
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_search_index_data_contributor" {
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_search_index_data_reader" {
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_storage_blob_data_contributor" {
  scope                = module.storage.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_foundry_user" {
  for_each             = azapi_resource.ai_foundry_project
  scope                = each.value.id
  role_definition_name = "Foundry User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ------------------------------------------------------------------------------------------------------
# AI Search インデックス / Knowledge Base (acl_off 版)
# ------------------------------------------------------------------------------------------------------

resource "null_resource" "provision_search_index" {
  triggers = {
    subscription_id      = var.subscription_id
    resource_group_name  = local.resource_group_name
    search_service_name  = module.ai_search.search_service_name
    datasource_name      = local.knowledge.datasource_name
    storage_account_name = module.storage.name
    blob_container_name  = azurerm_storage_data_lake_gen2_filesystem.ais_docs.name
    blob_query           = "Tartarian/"
    index_name           = local.knowledge.index_name
    skillset_name        = local.knowledge.skillset_name
    indexer_name         = local.knowledge.indexer_name
    resource_uri         = local.aoai_resource_uri
    deployment_id        = var.openai_embedding.model_name
    model_name           = var.openai_embedding.model_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/ais_set_noacl_index.sh \
        ${self.triggers.subscription_id} \
        ${self.triggers.resource_group_name} \
        ${self.triggers.search_service_name} \
        ${self.triggers.datasource_name} \
        ${self.triggers.storage_account_name} \
        ${self.triggers.blob_container_name} \
        ${self.triggers.blob_query} \
        ${self.triggers.index_name} \
        ${self.triggers.skillset_name} \
        ${self.triggers.indexer_name} \
        ${self.triggers.resource_uri} \
        ${self.triggers.deployment_id} \
        ${self.triggers.model_name}
    EOT
  }

  depends_on = [
    module.ai_foundry,
    module.apim_api_openai,
    azurerm_storage_blob.docs,
    azurerm_role_assignment.aisearch_storage_blob_reader,
    azurerm_role_assignment.current_user_search_service_contributor,
    azurerm_role_assignment.current_user_search_index_data_contributor,
  ]
}

resource "null_resource" "provision_search_knowledge" {
  triggers = {
    search_service_name   = module.ai_search.search_service_name
    knowledge_source_name = local.knowledge.knowledge_source_name
    index_name            = local.knowledge.index_name
    knowledge_base_name   = local.knowledge.knowledge_base_name
    resource_uri          = local.aoai_resource_uri
    chat_deployment_id    = var.openai_chat.model_name
    chat_model_name       = var.openai_chat.model_name
    reasoning_effort      = var.knowledge_reasoning_effort
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/ais_set_knowledge.sh \
        ${self.triggers.search_service_name} \
        ${self.triggers.knowledge_source_name} \
        ${self.triggers.index_name} \
        ${self.triggers.knowledge_base_name} \
        ${self.triggers.resource_uri} \
        ${self.triggers.chat_deployment_id} \
        ${self.triggers.chat_model_name} \
        ${self.triggers.reasoning_effort}
    EOT
  }

  depends_on = [null_resource.provision_search_index]
}

# ------------------------------------------------------------------------------------------------------
# tartaria-agent (prompt agent) のデプロイ + A2A プロトコル有効化
# ------------------------------------------------------------------------------------------------------

resource "null_resource" "deploy_prompt_agent" {
  for_each = azapi_resource.ai_foundry_project
  triggers = {
    endpoint        = "https://${module.ai_foundry[each.key].name}.services.ai.azure.com/api/projects/${each.value.name}"
    agent_name      = local.agent_name
    create_payload  = local.agent_create_payload
    version_payload = local.agent_version_payload
    patch_payload   = local.agent_patch_payload
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "bash ${path.module}/scripts/deploy_prompt_agent.sh '${self.triggers.endpoint}' '${self.triggers.agent_name}'"
    environment = {
      AGENT_CREATE_PAYLOAD  = self.triggers.create_payload
      AGENT_VERSION_PAYLOAD = self.triggers.version_payload
      AGENT_PATCH_PAYLOAD   = self.triggers.patch_payload
    }
  }

  depends_on = [
    azapi_resource.conn_foundryiq,
    null_resource.provision_search_knowledge,
    azurerm_role_assignment.current_user_foundry_user,
    azurerm_role_assignment.ai_foundry_project_azure_ai_user,
    azurerm_role_assignment.ai_foundry_project_ai_search_index_data_reader,
  ]
}

# ------------------------------------------------------------------------------------------------------
# Entra ID アプリ (A2A クライアント認可用: roles クレーム = エージェント名)
# ------------------------------------------------------------------------------------------------------

resource "random_uuid" "tartaria_agent_role" {}
resource "random_uuid" "knowledge_agent_role" {}
resource "random_uuid" "s1_wildcard_role" {}
resource "random_uuid" "user_impersonation_scope_id" {}

resource "azuread_application" "a2a_agent" {
  display_name = "a2a-agent-${substr(local.resource_token, 0, 3)}"
  owners       = [data.azuread_client_config.current.object_id]

  app_role {
    allowed_member_types = ["User", "Application"]
    description          = "tartaria-agentの実行権限"
    display_name         = "tartaria-agent"
    enabled              = true
    id                   = random_uuid.tartaria_agent_role.result
    value                = "tartaria-agent"
  }


  lifecycle {
    ignore_changes = [
      identifier_uris,
      api,
    ]
  }
}

resource "azuread_service_principal" "a2a_agent_sp" {
  client_id = azuread_application.a2a_agent.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Set Application ID URI
resource "azuread_application_identifier_uri" "a2a_agent_uri" {
  application_id = azuread_application.a2a_agent.id
  identifier_uri = "api://${azuread_application.a2a_agent.client_id}"
}

# Set user_impersonation scope
resource "azuread_application_permission_scope" "user_impersonation" {
  application_id = azuread_application.a2a_agent.id
  scope_id       = random_uuid.user_impersonation_scope_id.result
  value          = "user_impersonation"

  admin_consent_description  = "Allow the application to access the A2A agent on behalf of the signed-in user."
  admin_consent_display_name = "Access A2A agent"
  user_consent_description   = "Allow the application to access the A2A agent on your behalf."
  user_consent_display_name  = "Access A2A agent"
  type                       = "User" # Both admin and user can consent
}

# Azure CLI からのトークン取得を許可 (動作確認用)
resource "azuread_application_pre_authorized" "a2a_agent" {
  application_id       = azuread_application.a2a_agent.id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46" # Azure CLI

  permission_ids = [
    azuread_application_permission_scope.user_impersonation.scope_id,
  ]
}

# デプロイ実行ユーザーへ tartaria-agent ロールを割り当て (動作確認用)
resource "azuread_app_role_assignment" "tartaria_agent_current_user" {
  principal_object_id = data.azuread_client_config.current.object_id
  app_role_id         = azuread_service_principal.a2a_agent_sp.app_role_ids["tartaria-agent"]
  resource_object_id  = azuread_service_principal.a2a_agent_sp.object_id
}

# ------------------------------------------------------------------------------------------------------
# APIM: tartaria-agent API (type=a2a) + A2A Product + Application Insights logger
# ------------------------------------------------------------------------------------------------------

# ------------------------------------------------------------------------------------------------------
# A2A Product ポリシー用の外部キャッシュ (Azure Managed Redis)
# oid ごとのスティッキーバックエンド割り当てを cache-lookup-value / cache-store-value (caching-type=external) で保持する
# ------------------------------------------------------------------------------------------------------

resource "azurerm_managed_redis" "a2a_cache" {
  name                      = "redis-${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  resource_group_name       = local.resource_group_name
  location                  = var.location
  sku_name                  = "Balanced_B0"
  high_availability_enabled = false
  tags                      = local.tags

  default_database {
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    clustering_policy                  = "EnterpriseCluster"
    eviction_policy                    = "NoEviction"
  }
}

# デプロイ実行ユーザーが Entra ID 認証でデータアクセスできるようにする
# (default データベースの default アクセスポリシーを割り当て)
resource "azurerm_managed_redis_access_policy_assignment" "a2a_cache_current_user" {
  managed_redis_id = azurerm_managed_redis.a2a_cache.id
  object_id        = data.azuread_client_config.current.object_id
}

# APIM の外部キャッシュとして登録 (ゲートウェイのリージョンから利用)
resource "azurerm_api_management_redis_cache" "a2a_external_cache" {
  name              = azurerm_managed_redis.a2a_cache.name
  api_management_id = data.azurerm_api_management.apim.id
  connection_string = "${azurerm_managed_redis.a2a_cache.hostname}:${azurerm_managed_redis.a2a_cache.default_database[0].port},password=${azurerm_managed_redis.a2a_cache.default_database[0].primary_access_key},ssl=True,abortConnect=False"
  description       = azurerm_managed_redis.a2a_cache.hostname
  redis_cache_id    = azurerm_managed_redis.a2a_cache.id
  cache_location    = var.location
}

# Foundry IQ (AI Search) からの OpenAI モデル呼び出しを APIM 経由にするための openai API
# (msfoundry-docsacl-apim の openai モジュールをそのまま使用)
module "apim_api_openai" {
  source = "./modules/gateway/apim-api/openai"

  resource_group_name            = var.apim.resource_group_name
  api_management_name            = data.azurerm_api_management.apim.name
  foundry_backend_names          = [for k, v in module.ai_foundry : v.name]
  foundry_backend_ids            = [for k, v in module.ai_foundry : v.ai_foundry_id]
  ais_mi_client_id               = data.azuread_service_principal.ai_search.client_id
  api_management_logger_id       = local.apim_logger_id
  api_management_id              = data.azurerm_api_management.apim.id
  apim_gateway_url               = data.azurerm_api_management.apim.gateway_url
  apim_principal_id              = data.azurerm_api_management.apim.identity[0].principal_id
  diagnostic_sampling_percentage = 100.0
  token_limit                    = var.tpm_limit_token
}

module "apim_a2a_agent" {
  source              = "./modules/gateway/apim-api/a2a-agent"
  resource_group_name = var.apim.resource_group_name
  api_management_name = data.azurerm_api_management.apim.name
  api_management_id   = data.azurerm_api_management.apim.id

  agent_name            = local.agent_name
  project_name          = local.project_name
  foundry_backend_names = [for k, v in module.ai_foundry : v.name]

  oauth_app_client_id = azuread_application.a2a_agent.client_id

  application_insights_instrumentation_key = data.azurerm_application_insights.appi.instrumentation_key
  application_insights_ingestion_endpoint  = local.appi_ingestion_endpoint
  diagnostic_sampling_percentage           = 100.0
  api_management_logger_id                 = local.apim_logger_id

  # A2A Product ポリシーが external キャッシュ (Redis) を前提とするため
  depends_on = [azurerm_api_management_redis_cache.a2a_external_cache]
}
