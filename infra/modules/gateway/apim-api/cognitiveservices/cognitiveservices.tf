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


resource "azurerm_api_management_api" "cognitiveservices" {
  name                  = "cognitiveservices"
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  display_name          = "cognitiveservices-api"
  path                  = "cognitiveservices"
  description           = "Azure Cognitive Services API (incl. Azure AI Language PII detection)"
  protocols             = ["https"]
  subscription_required = false

  subscription_key_parameter_names {
    header = "api-key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi"
    content_value = templatefile("${path.module}/files/api/cognitiveservices_openapi.yaml",
      {
        apim_gateway_url = var.apim_gateway_url
      }
    )
  }
}

# Foundryごとにバックエンドを生成
resource "azapi_resource" "cogni_backend" {
  for_each = {
    for idx, name in var.foundry_backend_names :
    idx => name
  }
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = "cognitiveservices-${each.value}"
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      protocol = "http"
      url      = "https://${each.value}.cognitiveservices.azure.com/"
      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com/"
        }
      }
      circuitBreaker = {
        rules = [
          {
            name             = "AIBreakerRule"
            acceptRetryAfter = true
            tripDuration     = "PT1M"
            failureCondition = {
              count    = 3
              interval = "PT5M"
              statusCodeRanges = [
                {
                  min = 429
                  max = 429
                },
                {
                  min = 500
                  max = 599
                }
              ]
            }
          }
        ]
      }
    }
  }
}

# バックエンドプール
resource "azapi_resource" "backend_pool" {
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = "cognibackendpool"
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "Pool"
      pool = {
        services = [
          for k, v in azapi_resource.cogni_backend : {
            id = v.id
          }
        ]
      }
    }
  }
}

resource "azurerm_api_management_named_value" "cogni_backend_pool" {
  name                = "CogniBackendPool"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "CogniBackendPool"
  value               = azapi_resource.backend_pool.name
  secret              = false
}

resource "azurerm_api_management_named_value" "mi_client_ids" {
  name                = "CogniMiClientIds"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "CogniMiClientIds"
  value               = join(",", var.mi_client_ids)
  secret              = true
}

resource "azurerm_api_management_named_value" "ops_group_ids" {
  name                = "CogniOpsGroupIds"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "CogniOpsGroupIds"
  value               = join(",", var.ops_group_ids)
  secret              = true
}

resource "azurerm_api_management_api_policy" "cognitiveservices" {
  api_name            = azurerm_api_management_api.cognitiveservices.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content = templatefile("${path.module}/files/policy/cognitiveservices_api_v2.xml", {
    CogniBackendPool = azurerm_api_management_named_value.cogni_backend_pool.name
    CogniMiClientIds = azurerm_api_management_named_value.mi_client_ids.name
    CogniOpsGroupIds = azurerm_api_management_named_value.ops_group_ids.name
  })
}

resource "azurerm_api_management_api_diagnostic" "cognitiveservices" {
  identifier                = "applicationinsights"
  api_name                  = azurerm_api_management_api.cognitiveservices.name
  api_management_name       = var.api_management_name
  resource_group_name       = var.resource_group_name
  api_management_logger_id  = var.api_management_logger_id
  sampling_percentage       = var.diagnostic_sampling_percentage
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = 0
  }

  frontend_response {
    body_bytes = 0
  }

  backend_request {
    body_bytes = 0
  }

  backend_response {
    body_bytes = 0
  }
}

resource "azurerm_role_assignment" "cognitiveservices" {
  for_each = {
    for idx, id in var.foundry_backend_ids :
    idx => id
  }
  scope                = each.value
  role_definition_name = "Cognitive Services User"
  principal_id         = var.apim_principal_id
}
