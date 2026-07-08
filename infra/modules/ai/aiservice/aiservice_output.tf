output "ai_foundry_id" {
  description = "The resource ID of the AI foundry."
  value       = azapi_resource.ai_foundry.id
}

output "name" {
  description = "The name of the AI foundry."
  value       = azapi_resource.ai_foundry.name
}

output "principal_id" {
  description = "The principal ID of the AI foundry's managed identity."
  value       = azapi_resource.ai_foundry.output.identity.principalId
}

output "internal_id" {
  description = "The internal ID of the AI foundry"
  value       = azapi_resource.ai_foundry.output.properties.internalId
}

output "location" {
  description = "The location of the AI foundry."
  value       = azapi_resource.ai_foundry.location
}
