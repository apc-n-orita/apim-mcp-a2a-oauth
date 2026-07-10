terraform {
  required_providers {
    azurerm = {
      version = "~>4.80.0"
      source  = "hashicorp/azurerm"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~>2.0.0"
    }
  }
}

resource "azurerm_search_service" "search" {
  name                          = var.name
  resource_group_name           = var.rg_name
  location                      = var.location
  sku                           = var.search_service_sku
  replica_count                 = var.search_service_replica_count
  partition_count               = var.search_service_partition_count
  local_authentication_enabled  = var.local_authentication_enabled
  semantic_search_sku           = var.semantic_search_sku
  authentication_failure_mode   = var.local_authentication_enabled ? "http403" : null
  public_network_access_enabled = var.public_network_access_enabled
  #network_rule_bypass_option    = var.bypass_network_rule
  identity { type = "SystemAssigned" }

  #allowed_ips = var.ip_rules == [] ? null : var.ip_rules

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "ai_search" {
  name                       = "send-to-law"
  target_resource_id         = azurerm_search_service.search.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

