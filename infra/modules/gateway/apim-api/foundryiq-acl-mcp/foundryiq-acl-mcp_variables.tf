variable "resource_group_name" {
  description = "Resource group of the existing API Management instance"
  type        = string
}

variable "api_management_name" {
  description = "Name of the existing API Management instance"
  type        = string
}

variable "api_management_id" {
  description = "Resource ID of the existing API Management instance (parent for the azapi API resource)"
  type        = string
}

variable "api_name" {
  description = "Name/path of the MCP API on APIM"
  type        = string
  default     = "foundryiq-acl-mcp"
}

variable "api_description" {
  description = "Description of the MCP API"
  type        = string
  default     = "MCP tool that searches the ACL-protected Foundry IQ knowledge base"
}

variable "mcp_url" {
  description = "Base URL of the backend (the foundryiq-acl-mcp Function App, e.g. https://<host>)"
  type        = string
}

variable "mcp_api_uri_template" {
  description = "URI template of the Function's native MCP endpoint"
  type        = string
  default     = "/runtime/webhooks/mcp"
}

variable "api_management_logger_id" {
  description = "Resource ID of the existing Application Insights logger on APIM"
  type        = string
}

variable "diagnostic_sampling_percentage" {
  description = "Sampling percentage for the API diagnostic setting"
  type        = number
  default     = 100.0
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID used to validate the inbound Authorization token"
  type        = string
}
