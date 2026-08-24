<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.1.7, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~>2.0.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~>3.5.0 |
| <a name="requirement_azurecaf"></a> [azurecaf](#requirement\_azurecaf) | ~>1.2.24 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.80.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~>3.2.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~>0.13.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | 2.0.1 |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | 3.5.0 |
| <a name="provider_azurecaf"></a> [azurecaf](#provider\_azurecaf) | 1.2.34 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.80.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.13.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ai_foundry"></a> [ai\_foundry](#module\_ai\_foundry) | ./modules/ai/aiservice | n/a |
| <a name="module_ai_search"></a> [ai\_search](#module\_ai\_search) | ./modules/ai/aisearch | n/a |
| <a name="module_apim_a2a_agent"></a> [apim\_a2a\_agent](#module\_apim\_a2a\_agent) | ./modules/gateway/apim-api/a2a-agent | n/a |
| <a name="module_apim_api_openai"></a> [apim\_api\_openai](#module\_apim\_api\_openai) | ./modules/gateway/apim-api/openai | n/a |
| <a name="module_foundryiq_acl_mcp"></a> [foundryiq\_acl\_mcp](#module\_foundryiq\_acl\_mcp) | ./modules/app/function/app | n/a |
| <a name="module_foundryiq_acl_mcp_api"></a> [foundryiq\_acl\_mcp\_api](#module\_foundryiq\_acl\_mcp\_api) | ./modules/gateway/apim-api/foundryiq-acl-mcp | n/a |
| <a name="module_foundryiq_acl_mcp_plan"></a> [foundryiq\_acl\_mcp\_plan](#module\_foundryiq\_acl\_mcp\_plan) | ./modules/host/appserviceplan | n/a |
| <a name="module_foundryiq_acl_mcp_storage"></a> [foundryiq\_acl\_mcp\_storage](#module\_foundryiq\_acl\_mcp\_storage) | ./modules/storage | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage | n/a |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.ai_foundry_project](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_appi](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_foundryiq](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_tartaria_a2a](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.verify_project](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azuread_app_role_assignment.tartaria_agent_current_user](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/app_role_assignment) | resource |
| [azuread_app_role_assignment.verify_project_tartaria_role](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/app_role_assignment) | resource |
| [azuread_application.a2a_agent](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_identifier_uri.a2a_agent_uri](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_identifier_uri) | resource |
| [azuread_application_permission_scope.user_impersonation](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_permission_scope) | resource |
| [azuread_application_pre_authorized.a2a_agent](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_pre_authorized) | resource |
| [azuread_group.adls_acl_group](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group) | resource |
| [azuread_service_principal.a2a_agent_sp](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azurecaf_name.storage_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurerm_api_management_redis_cache.a2a_external_cache](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_redis_cache) | resource |
| [azurerm_managed_redis.a2a_cache](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_redis) | resource |
| [azurerm_managed_redis_access_policy_assignment.a2a_cache_current_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_redis_access_policy_assignment) | resource |
| [azurerm_role_assignment.ai_foundry_project_ai_search_index_data_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ai_foundry_project_appinsights_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ai_foundry_project_azure_ai_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ai_foundry_project_monitoring_metrics_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aisearch_foundry_cognitive_services_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aisearch_storage_blob_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.apim_foundry_project_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_foundry_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_search_index_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_search_index_data_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_search_service_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_storage_blob_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_storage_blob_data_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_verify_project_foundry_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.foundryiq_acl_mcp_search_index_data_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.foundryiq_acl_mcp_storage_blob_data_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.foundryiq_acl_mcp_storage_queue_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.foundryiq_acl_mcp_storage_table_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_blob.docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_blob) | resource |
| [azurerm_storage_data_lake_gen2_filesystem.ais_docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_data_lake_gen2_filesystem) | resource |
| [azurerm_storage_data_lake_gen2_path.tartarian](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_data_lake_gen2_path) | resource |
| [null_resource.deploy_prompt_agent](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.deploy_verify_agent](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.provision_search_index](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.provision_search_index_acl](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.provision_search_knowledge](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.provision_search_knowledge_acl](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_uuid.knowledge_agent_role](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [random_uuid.s1_wildcard_role](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [random_uuid.tartaria_agent_role](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [random_uuid.user_impersonation_scope_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [time_sleep.wait_project_identities](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_verify_project_identities](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [azuread_application.mcp_oauth](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/application) | data source |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azuread_service_principal.ai_search](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_api_management.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/api_management) | data source |
| [azurerm_application_insights.appi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/application_insights) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_log_analytics_workspace.law](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/log_analytics_workspace) | data source |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_user_assigned_identity.mcp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ai_locations"></a> [ai\_locations](#input\_ai\_locations) | List of locations for AI Foundry instances | `list(string)` | n/a | yes |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Existing API Management instance to add the tartaria-agent API / A2A product to | `string` | n/a | yes |
| <a name="input_application_insights_name"></a> [application\_insights\_name](#input\_application\_insights\_name) | Existing Application Insights used for the tartaria-agent API logger | `string` | n/a | yes |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | The name of the azd environment to be deployed | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The supported Azure location where the resource deployed | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_name"></a> [log\_analytics\_workspace\_name](#input\_log\_analytics\_workspace\_name) | Existing Log Analytics Workspace used for diagnostic settings of the newly created resources | `string` | n/a | yes |
| <a name="input_openai_chat"></a> [openai\_chat](#input\_openai\_chat) | OpenAI Chat model configuration | <pre>object({<br/>    model_name    = string<br/>    model_version = string<br/>    deploy_type   = string<br/>    capacity      = number<br/>  })</pre> | n/a | yes |
| <a name="input_openai_embedding"></a> [openai\_embedding](#input\_openai\_embedding) | OpenAI Embedding model configuration | <pre>object({<br/>    model_name    = string<br/>    model_version = string<br/>    deploy_type   = string<br/>    capacity      = number<br/>  })</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Existing resource group containing the APIM / Application Insights / Log Analytics Workspace. Newly created resources are also placed here. | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription ID | `string` | n/a | yes |
| <a name="input_a2a_rate_limit_calls"></a> [a2a\_rate\_limit\_calls](#input\_a2a\_rate\_limit\_calls) | tartaria-agent API の oid ごとのレートリミット回数 (60 秒あたりの許可リクエスト数) | `number` | `20` | no |
| <a name="input_knowledge_reasoning_effort"></a> [knowledge\_reasoning\_effort](#input\_knowledge\_reasoning\_effort) | Retrieval reasoning effort for Knowledge Base. Valid values: minimal, low, medium | `string` | `"medium"` | no |
| <a name="input_tpm_limit_token"></a> [tpm\_limit\_token](#input\_tpm\_limit\_token) | Tokens per minute limit for OpenAI (APIM 経由の openai API に適用) | `number` | `30000` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_A2A_AGENT_API_URL"></a> [A2A\_AGENT\_API\_URL](#output\_A2A\_AGENT\_API\_URL) | A2A JSON-RPC endpoint of the tartaria-agent API on APIM |
| <a name="output_A2A_AGENT_CARD_URL"></a> [A2A\_AGENT\_CARD\_URL](#output\_A2A\_AGENT\_CARD\_URL) | Agent card URL of the tartaria-agent API on APIM |
| <a name="output_A2A_OAUTH_APP_CLIENT_ID"></a> [A2A\_OAUTH\_APP\_CLIENT\_ID](#output\_A2A\_OAUTH\_APP\_CLIENT\_ID) | Client ID of the Entra ID application used for A2A client authorization |
| <a name="output_ADLS_ACL_GROUP_ID"></a> [ADLS\_ACL\_GROUP\_ID](#output\_ADLS\_ACL\_GROUP\_ID) | Object ID of the Entra ID group with read access to the ACL-protected Tartarian/ documents; add test users/groups to this group to see them in the filtered search results |
| <a name="output_APIM_GATEWAY_URL"></a> [APIM\_GATEWAY\_URL](#output\_APIM\_GATEWAY\_URL) | Gateway URL of the existing API Management instance |
| <a name="output_AZURE_RESOURCE_GROUP"></a> [AZURE\_RESOURCE\_GROUP](#output\_AZURE\_RESOURCE\_GROUP) | Resource group for the newly created resources (same as the existing APIM) |
| <a name="output_FOUNDRYIQ_ACL_MCP_APIM_URL"></a> [FOUNDRYIQ\_ACL\_MCP\_APIM\_URL](#output\_FOUNDRYIQ\_ACL\_MCP\_APIM\_URL) | APIM-fronted MCP endpoint of the foundryiq-acl-mcp Function (Authorization: audience https://search.azure.com) |
| <a name="output_FOUNDRY_A2A_BACKEND_URLS"></a> [FOUNDRY\_A2A\_BACKEND\_URLS](#output\_FOUNDRY\_A2A\_BACKEND\_URLS) | Direct A2A base paths of the tartaria-agent on each Foundry project |
| <a name="output_FOUNDRY_PROJECT_ENDPOINTS"></a> [FOUNDRY\_PROJECT\_ENDPOINTS](#output\_FOUNDRY\_PROJECT\_ENDPOINTS) | Endpoints of the AI Foundry projects hosting the tartaria-agent |
| <a name="output_REDIS_HOSTNAME"></a> [REDIS\_HOSTNAME](#output\_REDIS\_HOSTNAME) | Hostname of the Managed Redis instance used as the APIM external cache (sticky backend assignments) |
| <a name="output_SEARCH_SERVICE_NAME"></a> [SEARCH\_SERVICE\_NAME](#output\_SEARCH\_SERVICE\_NAME) | Name of the Azure AI Search service hosting the Foundry IQ knowledge base |
| <a name="output_VERIFY_PROJECT_ENDPOINTS"></a> [VERIFY\_PROJECT\_ENDPOINTS](#output\_VERIFY\_PROJECT\_ENDPOINTS) | Endpoints of the verification projects (a2a-caller agent calls tartaria-agent via the APIM A2A endpoint; with-approle passes the APIM policy, without-approle gets 403) |
<!-- END_TF_DOCS -->