
output "search_service_id" {
  description = "The resource ID of the Azure Cognitive Search service."
  value       = azurerm_search_service.search.id
}

output "search_service_name" {
  description = "The name of the Azure Cognitive Search service."
  value       = azurerm_search_service.search.name
}

output "search_service_identity_principal_id" {
  description = "The principal ID of the system-assigned managed identity for the Azure Cognitive Search service."
  value       = azurerm_search_service.search.identity[0].principal_id
}

output "search_service_identity_tenant_id" {
  description = "The tenant ID of the system-assigned managed identity for the Azure Cognitive Search service."
  value       = azurerm_search_service.search.identity[0].tenant_id
}
