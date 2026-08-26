output "AZURE_RESOURCE_GROUP" {
  description = "Resource group for the newly created resources (same as the existing APIM)"
  value       = local.resource_group_name
}

output "APIM_GATEWAY_URL" {
  description = "Gateway URL of the existing API Management instance"
  value       = data.azurerm_api_management.apim.gateway_url
}

output "A2A_AGENT_API_URL" {
  description = "A2A JSON-RPC endpoint of the tartaria-agent API on APIM"
  value       = "${data.azurerm_api_management.apim.gateway_url}/${module.apim_a2a_agent.api_path}"
}

output "A2A_AGENT_CARD_URL" {
  description = "Agent card URL of the tartaria-agent API on APIM"
  value       = "${data.azurerm_api_management.apim.gateway_url}/${module.apim_a2a_agent.api_path}/agent-card.json"
}

output "A2A_OAUTH_APP_CLIENT_ID" {
  description = "Client ID of the Entra ID application used for A2A client authorization"
  value       = azuread_application.a2a_agent.client_id
}

output "FOUNDRY_PROJECT_ENDPOINTS" {
  description = "Endpoints of the AI Foundry projects hosting the tartaria-agent"
  value       = [for k, v in azapi_resource.ai_foundry_project : "https://${module.ai_foundry[k].name}.services.ai.azure.com/api/projects/${v.name}"]
}

output "FOUNDRY_A2A_BACKEND_URLS" {
  description = "Direct A2A base paths of the tartaria-agent on each Foundry project"
  value       = [for k, v in azapi_resource.ai_foundry_project : "https://${module.ai_foundry[k].name}.services.ai.azure.com/api/projects/${v.name}/agents/${local.agent_name}/endpoint/protocols/a2a"]
}

output "SEARCH_SERVICE_NAME" {
  description = "Name of the Azure AI Search service hosting the Foundry IQ knowledge base"
  value       = module.ai_search.search_service_name
}

output "ADLS_ACL_GROUP_ID" {
  description = "Object ID of the Entra ID group with read access to the ACL-protected Tartarian/ documents; add test users/groups to this group to see them in the filtered search results"
  value       = azuread_group.adls_acl_group.object_id
}

output "REDIS_HOSTNAME" {
  description = "Hostname of the Managed Redis instance used as the APIM external cache (sticky backend assignments)"
  value       = azurerm_managed_redis.a2a_cache.hostname
}

output "FOUNDRYIQ_ACL_MCP_APIM_URL" {
  description = "APIM-fronted MCP endpoint of the foundryiq-acl-mcp Function (Authorization: audience https://search.azure.com)"
  value       = "${data.azurerm_api_management.apim.gateway_url}/${module.foundryiq_acl_mcp_api.api_path}/runtime/webhooks/mcp"
}

output "TOOLBOX_APIM_URL" {
  description = "APIM-fronted toolbox MCP endpoint (oid-sticky load balanced across Foundry backends; client Authorization token is passed through unchanged to preserve foundryiqmcp's UserEntraToken OBO)"
  value       = "${data.azurerm_api_management.apim.gateway_url}/${module.apim_toolbox.api_path}${module.apim_toolbox.mcp_uri_template}?api-version=v1"
}

output "TOOLBOX_PROJECT_ENDPOINTS" {
  description = "Endpoints of the toolbox-project projects (foundryiqmcp / logicmcp connections). Use with `azd ai project set <endpoint>` before `azd ai toolbox create --from-file infra/toolbox.yaml`"
  value       = { for k, v in azapi_resource.toolbox_project : k => "https://${module.ai_foundry[k].name}.services.ai.azure.com/api/projects/${v.name}" }
}

output "VERIFY_PROJECT_ENDPOINTS" {
  description = "Endpoints of the verification projects (a2a-caller agent calls tartaria-agent via the APIM A2A endpoint; with-approle passes the APIM policy, without-approle gets 403)"
  value       = { for k, v in azapi_resource.verify_project : k => "https://${module.ai_foundry["0"].name}.services.ai.azure.com/api/projects/${v.name}" }
}
