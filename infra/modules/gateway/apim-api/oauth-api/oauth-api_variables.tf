variable "resource_group_name" {
  description = "Resource group name of the existing API Management instance"
  type        = string
}

variable "api_management_name" {
  description = "Name of the existing API Management instance"
  type        = string
}

variable "api_management_logger_id" {
  description = "Resource ID of the existing Application Insights logger on APIM"
  type        = string
}

variable "api_name" {
  description = "Name of the API on APIM. Defaults to \"oauth\" to match/replace apim-mcp-oauth's existing oauth API (that one must be deleted first to avoid a name/path collision)"
  type        = string
  default     = "oauth"
}

variable "api_path" {
  description = "Path of the API on APIM (no leading/trailing slash). Fixed to the RFC 9728 well-known path so MCP-server-specific operations (see the mcp-prm-operation module) can be added underneath it."
  type        = string
  default     = ".well-known/oauth-protected-resource"
}

variable "diagnostic_sampling_percentage" {
  description = "Percentage of requests to log to Application Insights (0.0 to 100.0)"
  type        = number
  default     = 100.0
}
