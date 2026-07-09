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

output "KNOWLEDGE_BASE_MCP_URL" {
  description = "MCP endpoint of the Foundry IQ knowledge base"
  value       = local.kb_mcp_url
}

output "STORAGE_ACCOUNT_NAME" {
  description = "Name of the storage account holding the knowledge documents"
  value       = module.storage.name
}

output "REDIS_HOSTNAME" {
  description = "Hostname of the Managed Redis instance used as the APIM external cache (sticky backend assignments)"
  value       = azurerm_managed_redis.a2a_cache.hostname
}

output "VERIFY_PROJECT_ENDPOINTS" {
  description = "Endpoints of the verification projects (a2a-caller agent calls tartaria-agent via the APIM A2A endpoint; with-approle passes the APIM policy, without-approle gets 403)"
  value       = { for k, v in azapi_resource.verify_project : k => "https://${module.ai_foundry["0"].name}.services.ai.azure.com/api/projects/${v.name}" }
}
