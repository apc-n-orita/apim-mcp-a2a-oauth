<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~>2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.80.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | ~>2.0.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~>4.80.0 |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.a2a_api](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_api_diagnostic.a2a_api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_policy.a2a_api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_named_value.a2a_backends](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.a2a_oauth_app_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.ai_foundry_project](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.app_insights_ikey](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.app_insights_ingestion_endpoint](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_product.a2a](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.a2a](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_policy.a2a](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent_name"></a> [agent\_name](#input\_agent\_name) | Name of the A2A agent (used for the API name and the backend URL path) | `string` | n/a | yes |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the existing API Management instance | `string` | n/a | yes |
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | n/a | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | Name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_application_insights_ingestion_endpoint"></a> [application\_insights\_ingestion\_endpoint](#input\_application\_insights\_ingestion\_endpoint) | IngestionEndpoint of the existing Application Insights without trailing slash (app-insights-ingestion-endpoint named value) | `string` | n/a | yes |
| <a name="input_application_insights_instrumentation_key"></a> [application\_insights\_instrumentation\_key](#input\_application\_insights\_instrumentation\_key) | Instrumentation key of the existing Application Insights (app-insights-ikey named value) | `string` | n/a | yes |
| <a name="input_foundry_backend_names"></a> [foundry\_backend\_names](#input\_foundry\_backend\_names) | List of AI Foundry account names used as A2A backends (load-balanced by the a2a product policy via the a2a-backends named value) | `list(string)` | n/a | yes |
| <a name="input_oauth_app_client_id"></a> [oauth\_app\_client\_id](#input\_oauth\_app\_client\_id) | Client ID of the Entra ID application used for A2A client authorization (audience api://{client\_id}/) | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name of the AI Foundry project hosting the agent (referenced by the a2a product policy via the ai-foundry-project named value) | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_diagnostic_sampling_percentage"></a> [diagnostic\_sampling\_percentage](#input\_diagnostic\_sampling\_percentage) | APIM診断のサンプリング率（0.0 〜 100.0）。本番環境では 20.0 〜 50.0 を推奨。 | `number` | `100` | no |
| <a name="input_rate_limit_calls"></a> [rate\_limit\_calls](#input\_rate\_limit\_calls) | oid ごとのレートリミット回数 (renewal-period 60 秒あたりの許可リクエスト数) | `number` | `20` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | Resource ID of the tartaria-agent (a2a) API |
| <a name="output_api_path"></a> [api\_path](#output\_api\_path) | API path on the APIM gateway |
| <a name="output_logger_id"></a> [logger\_id](#output\_logger\_id) | Resource ID of the Application Insights logger used by the API diagnostics |
| <a name="output_product_id"></a> [product\_id](#output\_product\_id) | Product ID of the A2A product |
<!-- END_TF_DOCS -->