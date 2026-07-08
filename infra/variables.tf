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
# 既存リソースの指定 (APIM / Application Insights のみ。他はすべて新規作成)
# ------------------------------------------------------------------------------------------------------

variable "apim" {
  description = "Existing API Management instance to add the tartaria-agent API / A2A product to"
  type = object({
    name                = string
    resource_group_name = string
  })
}

variable "application_insights" {
  description = "Existing Application Insights used for the tartaria-agent API logger"
  type = object({
    name                = string
    resource_group_name = string
  })
}

variable "log_analytics_workspace" {
  description = "Existing Log Analytics Workspace used for diagnostic settings of the newly created resources"
  type = object({
    name                = string
    resource_group_name = string
  })
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

variable "tpm_limit_token" {
  description = "Tokens per minute limit for OpenAI (APIM 経由の openai API に適用)"
  type        = number
  default     = 30000
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

