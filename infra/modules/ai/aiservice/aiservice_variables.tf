variable "name" {
  description = "The name of the AI service."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resource."
  type        = map(string)
  default     = {}
}

variable "ai_model" {
  description = "AI model deployment configurations (複数モデル対応)."
  type = list(object({
    model                      = string
    version                    = string
    format                     = string
    deploytype                 = string
    capacity                   = number
    version_upgrade_option     = optional(string)
    dynamic_throttling_enabled = optional(bool)
  }))
}

variable "public_network_access" {
  description = "Whether public network access is enabled for the storage account. Possible values: Enabled, Disabled"
  type        = string
  default     = "Disabled"
  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "Allowed values for public_network_access are: Enabled, Disabled"
  }
}

variable "network_acls" {
  description = "Network ACLs for the AI service."
  type = object({
    default_action = optional(string, "Deny")
    bypass         = optional(string, "AzureServices")
  })
}

variable "ip_rules" {
  description = "List of allowed IP addresses or CIDR ranges for the AI Foundry service firewall."
  type        = list(string)
  default     = []
}

variable "subnet_id_agent" {
  description = "The subnet ID for agent network injection."
  type        = string
  default     = null
}


variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for diagnostics."
  type        = string
}

variable "disableLocalauth" {
  description = "Disable local authentication for the AI service."
  type        = bool
  default     = true

}

variable "rai_policy_name" {
  description = "The name of the Responsible AI policy to apply to the AI service."
  type        = string
  default     = "Microsoft.DefaultV2"

}
