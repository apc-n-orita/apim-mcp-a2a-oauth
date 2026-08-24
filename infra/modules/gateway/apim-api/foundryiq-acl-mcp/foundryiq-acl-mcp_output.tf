output "api_id" {
  description = "Resource ID of the foundryiq-acl-mcp API"
  value       = azapi_resource.mcp_api.id
}

output "api_path" {
  description = "API path on the APIM gateway"
  value       = var.api_name
}

output "logger_id" {
  description = "Resource ID of the Application Insights logger used by the API diagnostics"
  value       = var.api_management_logger_id
}