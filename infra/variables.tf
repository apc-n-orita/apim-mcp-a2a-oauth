# Input variables for the module

variable "location" {
  description = "The supported Azure location where the resource deployed"
  type        = string
}

variable "environment_name" {
  description = "The name of the azd environment to be deployed"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

# ------------------------------------------------------------------------------------------------------
# 既存リソースの指定 (APIM / Application Insights / Log Analytics Workspace。他はすべて新規作成)
# 既存リソースはすべて resource_group_name のリソースグループにあり、新規リソースも同じ場所に作成する
# ------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Existing resource group containing the APIM / Application Insights / Log Analytics Workspace. Newly created resources are also placed here."
  type        = string
}

variable "apim_name" {
  description = "Existing API Management instance to add the tartaria-agent API / A2A product to"
  type        = string
}

variable "application_insights_name" {
  description = "Existing Application Insights used for the tartaria-agent API logger"
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Existing Log Analytics Workspace used for diagnostic settings of the newly created resources"
  type        = string
}

# ------------------------------------------------------------------------------------------------------
# AI Foundry (新規作成 / main.tfvars.json で複数指定可)
# ------------------------------------------------------------------------------------------------------

variable "ai_locations" {
  description = "List of locations for AI Foundry instances"
  type        = list(string)
}

variable "openai_chat" {
  description = "OpenAI Chat model configuration"
  type = object({
    model_name    = string
    model_version = string
    deploy_type   = string
    capacity      = number
  })
}

variable "openai_embedding" {
  description = "OpenAI Embedding model configuration"
  type = object({
    model_name    = string
    model_version = string
    deploy_type   = string
    capacity      = number
  })
}

variable "a2a_rate_limit_calls" {
  description = "tartaria-agent API の oid ごとのレートリミット回数 (60 秒あたりの許可リクエスト数)"
  type        = number
  default     = 20
}

variable "tpm_limit_token" {
  description = "Tokens per minute limit for OpenAI (APIM 経由の openai API に適用)"
  type        = number
  default     = 30000
}

variable "logicmcp_api_name" {
  description = "apim-mcp-oauth 側の logicappmcp (la_mcp, Logic App) の APIM 上のAPI名/パス (toolbox の logicmcp 接続の target に使用)"
  type        = string
}

variable "knowledge_reasoning_effort" {
  description = "Retrieval reasoning effort for Knowledge Base. Valid values: minimal, low, medium"
  type        = string
  default     = "medium"
  validation {
    condition     = contains(["minimal", "low", "medium"], var.knowledge_reasoning_effort)
    error_message = "Allowed values for knowledge_reasoning_effort are: minimal, low, medium"
  }
}

# ------------------------------------------------------------------------------------------------------
# エージェント / APIM 設定
# ------------------------------------------------------------------------------------------------------

