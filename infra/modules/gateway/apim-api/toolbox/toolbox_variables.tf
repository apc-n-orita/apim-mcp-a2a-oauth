variable "resource_group_name" {
  description = "Resource group name of the existing API Management instance"
  type        = string
}

variable "api_management_name" {
  description = "Name of the existing API Management instance"
  type        = string
}

variable "api_management_id" {
  description = "Resource ID of the existing API Management instance"
  type        = string
}

variable "toolbox_name" {
  description = "Name of the Foundry toolbox (used for the API name/path and the mcp uriTemplate)"
  type        = string
  default     = "toolbox"
}

variable "project_name" {
  description = "Name of the AI Foundry project hosting the toolbox (used in the mcp uriTemplate)"
  type        = string
}

variable "foundry_backend_names" {
  description = "List of AI Foundry account names used as toolbox backends (load-balanced by the toolbox product policy via the toolbox-backends named value)"
  type        = list(string)
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID used to validate the inbound Authorization token"
  type        = string
}

variable "api_management_logger_id" {
  type = string
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
