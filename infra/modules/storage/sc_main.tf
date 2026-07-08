terraform {
  required_providers {
    azurerm = {
      version = "~>4.80.0"
      source  = "hashicorp/azurerm"
    }
  }
}
resource "azurerm_storage_account" "main" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  tags                            = var.tags
  account_tier                    = var.tier
  account_replication_type        = var.replication_type
  public_network_access_enabled   = var.public_network_access == "Enabled" ? true : false
  shared_access_key_enabled       = var.shared_access_key_enabled
  is_hns_enabled                  = var.is_hns_enabled
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public

  dynamic "blob_properties" {
    for_each = var.blob_delete_retention_days != null ? [1] : []
    content {
      delete_retention_policy {
        days                     = var.blob_delete_retention_days
        permanent_delete_enabled = false
      }
    }
  }

  network_rules {
    bypass                     = var.network_acls.bypass
    default_action             = var.network_acls.default_action
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = var.subnet_ids

    dynamic "private_link_access" {
      for_each = var.network_acls.private_link_access != null ? var.network_acls.private_link_access : []
      content {
        endpoint_resource_id = private_link_access.value.endpoint_resource_id
      }
    }
  }
}

# Blob サービスの診断設定
resource "azurerm_monitor_diagnostic_setting" "storage_blob_diagnostics" {
  name                       = "blob-diagnostics"
  target_resource_id         = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  enabled_metric { category = "Transaction" }

}

# Table サービスの診断設定
resource "azurerm_monitor_diagnostic_setting" "storage_table_diagnostics" {
  name                       = "table-diagnostics"
  target_resource_id         = "${azurerm_storage_account.main.id}/tableServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  enabled_metric { category = "Transaction" }
}

# Queue サービスの診断設定
resource "azurerm_monitor_diagnostic_setting" "storage_queue_diagnostics" {
  name                       = "queue-diagnostics"
  target_resource_id         = "${azurerm_storage_account.main.id}/queueServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  enabled_metric { category = "Transaction" }

}

# Files サービスの診断設定
resource "azurerm_monitor_diagnostic_setting" "storage_file_diagnostics" {
  name                       = "file-diagnostics"
  target_resource_id         = "${azurerm_storage_account.main.id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  enabled_metric { category = "Transaction" }
}


