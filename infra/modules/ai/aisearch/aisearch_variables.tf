variable "public_network_access" {
  description = "Whether public network access is enabled for the storage account. Possible values: Enabled, Disabled"
  type        = string
  default     = "Disabled"
  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "Allowed values for public_network_access are: Enabled, Disabled"
  }
}

variable "location" {
  description = "The Azure location where the resources will be created."
  type        = string
}


variable "tags" {
  description = "A map of tags to assign to the resource."
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace to send diagnostics logs to."
  type        = string
}

variable "disableLocalauth" {
  description = "Disable local authentication for the AI service."
  type        = bool
  default     = true
}

variable "search_service_sku" {
  type        = string
  description = "SKU for Azure Cognitive Search service"
  default     = "standard"
  validation {
    condition     = contains(["basic", "free", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.search_service_sku)
    error_message = "search_service_sku は basic, free, standard, standard2, standard3, storage_optimized_l1, storage_optimized_l2 のいずれかを指定してください。"
  }
}

variable "search_service_replica_count" {
  type        = number
  description = "Number of replicas for the search service"
  default     = 1
}

variable "search_service_partition_count" {
  type        = number
  description = "Number of partitions for the search service"
  default     = 1
}

variable "name" {
  type        = string
  description = "Name of the Azure Cognitive Search service"
}

variable "rg_name" {
  type        = string
  description = "Resource group name for the search service"
}

variable "local_authentication_enabled" {
  type        = bool
  default     = false
  description = "Enable local authentication for the search service"
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = "Enable public network access for the search service"
}

variable "semantic_search_sku" {
  type        = string
  description = "Semantic search SKU: free or standard. Leave unset to disable."
  default     = null
  validation {
    condition     = var.semantic_search_sku == null || contains(["free", "standard"], var.semantic_search_sku)
    error_message = "semantic_search_sku must be null, free, or standard."
  }
}

variable "ip_rules" {
  description = "List of allowed IP addresses or CIDR ranges for the AI Search service firewall."
  type        = list(string)
  default     = []
}

variable "bypass_network_rule" {
  description = "network rule bypass options."
  type        = string
  default     = "AzureServices"
}
