output "api_id" {
  description = "Resource ID of the tartaria-agent (a2a) API"
  value       = azapi_resource.a2a_api.id
}

output "api_path" {
  description = "API path on the APIM gateway"
  value       = "a2a/${var.agent_name}"
}

output "product_id" {
  description = "Product ID of the A2A product"
  value       = azurerm_api_management_product.a2a.product_id
}

output "logger_id" {
  description = "Resource ID of the Application Insights logger used by the API diagnostics"
  value       = var.api_management_logger_id
}
