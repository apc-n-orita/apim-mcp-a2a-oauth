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
| [azapi_resource.mcp_api](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_api_diagnostic.mcp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_policy.mcp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_backend.mcp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_backend) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | Resource ID of the existing API Management instance (parent for the azapi API resource) | `string` | n/a | yes |
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | Resource ID of the existing Application Insights logger on APIM | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | Name of the existing API Management instance | `string` | n/a | yes |
| <a name="input_mcp_url"></a> [mcp\_url](#input\_mcp\_url) | Base URL of the backend (the foundryiq-acl-mcp Function App, e.g. https://<host>) | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group of the existing API Management instance | `string` | n/a | yes |
| <a name="input_api_description"></a> [api\_description](#input\_api\_description) | Description of the MCP API | `string` | `"MCP tool that searches the ACL-protected Foundry IQ knowledge base"` | no |
| <a name="input_api_name"></a> [api\_name](#input\_api\_name) | Name/path of the MCP API on APIM | `string` | `"foundryiq-acl-mcp"` | no |
| <a name="input_diagnostic_sampling_percentage"></a> [diagnostic\_sampling\_percentage](#input\_diagnostic\_sampling\_percentage) | Sampling percentage for the API diagnostic setting | `number` | `100` | no |
| <a name="input_mcp_api_uri_template"></a> [mcp\_api\_uri\_template](#input\_mcp\_api\_uri\_template) | URI template of the Function's native MCP endpoint | `string` | `"/runtime/webhooks/mcp"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | Resource ID of the foundryiq-acl-mcp API |
| <a name="output_api_path"></a> [api\_path](#output\_api\_path) | API path on the APIM gateway |
| <a name="output_logger_id"></a> [logger\_id](#output\_logger\_id) | Resource ID of the Application Insights logger used by the API diagnostics |
<!-- END_TF_DOCS -->