variable "resource_group_name" {}
variable "api_management_name" {}

variable "foundry_backend_names" {
  description = "List of Foundry backend names (e.g. ['aif-env-001', 'aif-env-002'])"
  type        = list(string)
}

variable "foundry_backend_ids" {
  description = "Set of Foundry backend resource IDs for role assignment scope"
  type        = list(string)
}

variable "api_management_logger_id" {
  type = string
}

variable "api_management_id" {
  type = string
}

variable "apim_gateway_url" {
  type = string
}

variable "apim_principal_id" {
  description = "Principal ID for role assignment (APIM managed identity)"
  type        = string
}

variable "mi_client_ids" {
  description = "Managed identity client ID(s) allowed to call this API directly (e.g. the shared 'mcp' user-assigned identity used by toolbox / foundryiq-acl-mcp)"
  type        = list(string)
}

variable "ops_group_ids" {
  description = "Entra ID group object ID(s) allowed to call this API directly (empty = no group allowed)"
  type        = list(string)
  default     = []
}

variable "diagnostic_sampling_percentage" {
  description = "APIM診断のサンプリング率（0.0 〜 100.0）。本番環境では 20.0 〜 50.0 を推奨。"
  type        = number
  default     = 100.0
  validation {
    condition     = var.diagnostic_sampling_percentage >= 0.0 && var.diagnostic_sampling_percentage <= 100.0
    error_message = "diagnostic_sampling_percentage must be between 0.0 and 100.0"
  }
}
