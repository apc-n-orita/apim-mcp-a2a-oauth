variable "blob_delete_retention_days" {
  description = "Number of days to retain deleted blobs (soft delete). If not set or null, soft delete is disabled."
  type        = number
  default     = null
}
variable "name" {
  description = "The name of the storage account."
  type        = string
}

variable "location" {
  description = "The Azure region where the storage account will be created."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the storage account."
  type        = string
}

variable "tags" {
  description = "A mapping of tags to assign to the resource."
  type        = map(string)
  default     = {}
}

variable "shared_access_key_enabled" {
  description = "Whether shared access key authentication is enabled for the storage account."
  type        = bool
  default     = false
}
variable "tier" {
  description = "The performance tier of the storage account. Possible values: Standard, Premium"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.tier)
    error_message = "Allowed values for tier are: Standard, Premium"
  }
}

variable "replication_type" {
  description = "The replication type of the storage account. Possible values: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Allowed values for replication_type are: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS"
  }
}


variable "network_acls" {
  description = "Network rules for the storage account."
  type = object({
    bypass         = optional(list(string), ["AzureServices"])
    default_action = optional(string, "Deny")
    private_link_access = optional(list(object({
      endpoint_resource_id = string
    })))
  })
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


variable "ip_rules" {
  description = "A list of IP addresses or CIDR ranges to allow access to the storage account."
  type        = list(string)
  default     = []

}

variable "subnet_ids" {
  description = "A list of subnet IDs to allow access to the storage account."
  type        = list(string)
  default     = []

}

variable "log_analytics_workspace_id" {
  description = "診断設定用のLog Analytics WorkspaceのID"
  type        = string
}

variable "is_hns_enabled" {
  description = "階層型名前空間（Hierarchical Namespace）を有効化するかどうか。Data Lake Storage Gen2機能に必要。一度有効にすると無効化できないので注意。"
  type        = bool
  default     = false
}

variable "allow_nested_items_to_be_public" {
  description = "Allow nested items (blobs and directories) within containers and directories to be set as public."
  type        = bool
  default     = false
}
