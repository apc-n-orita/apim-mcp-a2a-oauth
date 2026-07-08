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

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "azapi_resource" "ai_foundry" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name                      = var.name
  parent_id                 = data.azurerm_resource_group.rg.id
  location                  = var.location
  schema_validation_enabled = false
  tags                      = var.tags
  body = {
    kind = "AIServices",
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }

    properties = {
      # Support both Entra ID and API Key authentication for underlining Cognitive Services account
      disableLocalAuth = var.disableLocalauth

      # Specifies that this is an AI Foundry resource
      allowProjectManagement = true

      # Set custom subdomain name for DNS names created for this Foundry resource
      customSubDomainName = var.name

      # Network-related controls
      # Disable public access but allow Trusted Azure Services exception
      publicNetworkAccess = var.public_network_access
      networkAcls = {
        defaultAction = var.network_acls.default_action
        bypass        = var.network_acls.bypass
        ipRules = [
          for ip in var.ip_rules : {
            value = ip
          }
        ]
      }

      # Enable VNet injection for Standard Agents (only if subnet_id_agent is set)
      #networkInjections = var.subnet_id_agent != null ? [
      #  {
      #    scenario                   = "agent"
      #    subnetArmId                = var.subnet_id_agent
      #    useMicrosoftManagedNetwork = false
      #  }
      #] : []
    }
  }
  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}


resource "azurerm_cognitive_deployment" "deployment" {
  for_each                   = { for mdl in var.ai_model : mdl.model => mdl }
  name                       = each.value.model
  cognitive_account_id       = azapi_resource.ai_foundry.id
  rai_policy_name            = var.rai_policy_name
  dynamic_throttling_enabled = each.value.dynamic_throttling_enabled

  model {
    format  = each.value.format
    name    = each.value.model
    version = each.value.version
  }

  sku {
    name     = each.value.deploytype
    capacity = each.value.capacity
  }
  version_upgrade_option = each.value.version_upgrade_option

  depends_on = [
    azapi_resource.ai_foundry,
  ]
}

resource "azurerm_monitor_diagnostic_setting" "ai_foundry" {
  name                       = "send-to-law"
  target_resource_id         = azapi_resource.ai_foundry.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
