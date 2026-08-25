output "api_id" {
  description = "Resource ID of the toolbox API"
  value       = azapi_resource.toolbox_api.id
}

output "api_path" {
  description = "API path on the APIM gateway"
  value       = var.toolbox_name
}

output "mcp_uri_template" {
  description = "URI template of the toolbox mcp endpoint, appended after api_path on the gateway URL"
  value       = local.toolbox_uri_template
}

output "product_id" {
  description = "Product ID of the Toolbox product"
  value       = azurerm_api_management_product.toolbox.product_id
}

output "logger_id" {
  description = "Resource ID of the Application Insights logger used by the API diagnostics"
  value       = var.api_management_logger_id
}
