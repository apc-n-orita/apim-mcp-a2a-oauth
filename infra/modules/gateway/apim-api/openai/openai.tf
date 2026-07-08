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

locals {
  logsettings = ["remaining-tokens"]
}

resource "azurerm_api_management_api" "openai" {
  name                  = "openai"
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  display_name          = "openai-api"
  path                  = "openai"
  description           = "Azure Open AI API"
  protocols             = ["https"]
  subscription_required = false

  subscription_key_parameter_names {
    header = "api-key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi"
    content_value = templatefile("${path.module}/files/api/aif-openai.openapi.yaml",
      {
        apim_gateway_url = var.apim_gateway_url
      }
    )
  }
}

# Foundryごとにバックエンドを生成
resource "azapi_resource" "foundry_aoai_backend" {
  for_each = {
    for idx, name in var.foundry_backend_names :
    idx => name
  }
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = "openai-${each.value}"
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      protocol = "http"
      url      = "https://${each.value}.services.ai.azure.com/openai"
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
  name                      = "aifopenaibackendpool"
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "Pool"
      pool = {
        services = [
          for k, v in azapi_resource.foundry_aoai_backend : {
            id = v.id
          }
        ]
      }
    }
  }
}

# --- Named Values ---
resource "azurerm_api_management_named_value" "ais-mi-client-id" {
  name                = "AIS-MI-CLIENT-ID"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "AIS-MI-CLIENT-ID"
  value               = var.ais_mi_client_id
  secret              = true
}

resource "azurerm_api_management_named_value" "openai_backend_pool" {
  name                = "OpenAIBackendPool"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "OpenAIBackendPool"
  value               = azapi_resource.backend_pool.name
  secret              = false
}

resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content = templatefile("${path.module}/files/policy/aoai_api_v2.xml", {
    AIS-MI-CLIENT-ID = azurerm_api_management_named_value.ais-mi-client-id.name
  })

}


resource "azurerm_api_management_api_operation_policy" "openai_chat_operation" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  operation_id        = "ChatCompletions_Create"
  xml_content = templatefile("${path.module}/files/policy/aoai_operation_v2.xml", {
    AIS-MI-CLIENT-ID  = azurerm_api_management_named_value.ais-mi-client-id.name
    OpenAIBackendPool = azurerm_api_management_named_value.openai_backend_pool.name
    TokenLimit        = var.token_limit
  })
}

resource "azurerm_api_management_api_operation_policy" "openai_embedd_opration" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  operation_id        = "Embeddings_Create"
  xml_content = templatefile("${path.module}/files/policy/aoai_operation_v2.xml", {
    AIS-MI-CLIENT-ID  = azurerm_api_management_named_value.ais-mi-client-id.name
    OpenAIBackendPool = azurerm_api_management_named_value.openai_backend_pool.name
    TokenLimit        = var.token_limit
  })
}


resource "azurerm_api_management_api_diagnostic" "openai" {
  identifier                = "applicationinsights"
  api_name                  = azurerm_api_management_api.openai.name
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

resource "azapi_update_resource" "apim_openai_api_diagnostic" {
  type        = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  resource_id = azurerm_api_management_api_diagnostic.openai.id
  body = {
    properties = {
      metrics = true
    }
  }
}

resource "azapi_resource" "apim_openai_api_diagnostic_monitor" {
  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "azuremonitor"
  parent_id                 = azurerm_api_management_api.openai.id
  schema_validation_enabled = false
  body = {
    properties = {
      alwaysLog   = "allErrors"
      logClientIp = true
      verbosity   = "information"
      loggerId    = "${var.api_management_id}/loggers/azuremonitor"

      sampling = {
        percentage   = var.diagnostic_sampling_percentage
        samplingType = "fixed"
      }

      frontend = {
        request = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
        response = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
      }

      backend = {
        request = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
        response = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
      }

      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 32768
          messages       = "all"
        }
        responses = {
          maxSizeInBytes = 32768
          messages       = "all"
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "openai" {
  for_each = {
    for idx, id in var.foundry_backend_ids :
    idx => id
  }
  scope                = each.value
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.apim_principal_id
}


