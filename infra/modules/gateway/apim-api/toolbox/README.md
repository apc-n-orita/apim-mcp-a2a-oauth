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
| [azapi_resource.toolbox_api](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_api_diagnostic.toolbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_policy.toolbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_backend.toolbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_backend) | resource |
| [azurerm_api_management_named_value.toolbox_backends](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.toolbox_project_name](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_product.toolbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.toolbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_policy.toolbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the existing API Management instance | `string` | n/a | yes |
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | n/a | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | Name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_foundry_backend_names"></a> [foundry\_backend\_names](#input\_foundry\_backend\_names) | List of AI Foundry account names used as toolbox backends (load-balanced by the toolbox product policy via the toolbox-backends named value) | `list(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name of the AI Foundry project hosting the toolbox (used in the mcp uriTemplate) | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Microsoft Entra tenant ID used to validate the inbound Authorization token | `string` | n/a | yes |
| <a name="input_diagnostic_sampling_percentage"></a> [diagnostic\_sampling\_percentage](#input\_diagnostic\_sampling\_percentage) | APIM診断のサンプリング率（0.0 〜 100.0）。本番環境では 20.0 〜 50.0 を推奨。 | `number` | `100` | no |
| <a name="input_toolbox_name"></a> [toolbox\_name](#input\_toolbox\_name) | Name of the Foundry toolbox (used for the API name/path and the mcp uriTemplate) | `string` | `"toolbox"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | Resource ID of the toolbox API |
| <a name="output_api_path"></a> [api\_path](#output\_api\_path) | API path on the APIM gateway |
| <a name="output_logger_id"></a> [logger\_id](#output\_logger\_id) | Resource ID of the Application Insights logger used by the API diagnostics |
| <a name="output_mcp_uri_template"></a> [mcp\_uri\_template](#output\_mcp\_uri\_template) | URI template of the toolbox mcp endpoint, appended after api\_path on the gateway URL |
| <a name="output_product_id"></a> [product\_id](#output\_product\_id) | Product ID of the Toolbox product |
<!-- END_TF_DOCS -->