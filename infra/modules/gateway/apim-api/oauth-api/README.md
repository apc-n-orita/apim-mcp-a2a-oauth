<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.80.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~>4.80.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_api_management_api.oauth](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_diagnostic.oauth](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_operation.oauth_protected_resource_get](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation) | resource |
| [azurerm_api_management_api_operation.oauth_protected_resource_options](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation) | resource |
| [azurerm_api_management_api_operation_policy.oauth_protected_resource_get_policy](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_operation_policy.oauth_protected_resource_options_policy](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_policy.oauth](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | Resource ID of the existing Application Insights logger on APIM | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | Name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_apim_gateway_url"></a> [apim\_gateway\_url](#input\_apim\_gateway\_url) | Gateway URL of the API Management instance (used as the "resource" field in the metadata response) | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_scope"></a> [scope](#input\_scope) | OAuth scope advertised in scopes\_supported (e.g. https://ai.azure.com/.default) | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Microsoft Entra tenant ID | `string` | n/a | yes |
| <a name="input_api_name"></a> [api\_name](#input\_api\_name) | Name of the API on APIM. Defaults to "oauth" to match/replace apim-mcp-oauth's existing oauth API (that one must be deleted first to avoid a name/path collision) | `string` | `"oauth"` | no |
| <a name="input_api_path"></a> [api\_path](#input\_api\_path) | Path of the API on APIM (root, matching apim-mcp-oauth's oauth API) | `string` | `""` | no |
| <a name="input_diagnostic_sampling_percentage"></a> [diagnostic\_sampling\_percentage](#input\_diagnostic\_sampling\_percentage) | Percentage of requests to log to Application Insights (0.0 to 100.0) | `number` | `100` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_name"></a> [api\_name](#output\_api\_name) | Name of the oauth API on APIM |
| <a name="output_oauth_api_id"></a> [oauth\_api\_id](#output\_oauth\_api\_id) | Resource ID of the oauth API |
<!-- END_TF_DOCS -->