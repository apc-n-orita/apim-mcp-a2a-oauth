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

variable "agent_name" {
  description = "Name of the A2A agent (used for the API name and the backend URL path)"
  type        = string
}

variable "project_name" {
  description = "Name of the AI Foundry project hosting the agent (referenced by the a2a product policy via the ai-foundry-project named value)"
  type        = string
}

variable "foundry_backend_names" {
  description = "List of AI Foundry account names used as A2A backends (load-balanced by the a2a product policy via the a2a-backends named value)"
  type        = list(string)
}

variable "oauth_app_client_id" {
  description = "Client ID of the Entra ID application used for A2A client authorization (audience api://{client_id}/)"
  type        = string
}

variable "application_insights_instrumentation_key" {
  description = "Instrumentation key of the existing Application Insights (app-insights-ikey named value)"
  type        = string
  sensitive   = true
}

variable "application_insights_ingestion_endpoint" {
  description = "IngestionEndpoint of the existing Application Insights without trailing slash (app-insights-ingestion-endpoint named value)"
  type        = string
}

variable "api_management_logger_id" {
  type = string
}

variable "rate_limit_calls" {
  description = "oid ごとのレートリミット回数 (renewal-period 60 秒あたりの許可リクエスト数)"
  type        = number
  default     = 20
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

variable "agent_card_version" {
  description = "Foundry の agent card のバージョン (例: 0.3)。バックエンドの .../agentCard/v{version} を APIM の A2A API (agentCardBackendUrl) と A2A Product ポリシー (named value a2a-agent-card-version) の両方で参照する。APIM の A2A API は v0.3 の agent card しか書き換えない (v1.0 は supportedInterfaces が Foundry の URL を指したままになる)"
  type        = string
  default     = "0.3"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.agent_card_version))
    error_message = "agent_card_version must look like 0.3 or 1.0"
  }
}
