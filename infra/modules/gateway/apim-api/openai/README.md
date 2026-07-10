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
| [azapi_resource.apim_openai_api_diagnostic_monitor](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.backend_pool](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.foundry_aoai_backend](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_update_resource.apim_openai_api_diagnostic](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_api_management_api.openai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_diagnostic.openai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_operation_policy.openai_chat_operation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_operation_policy.openai_embedd_opration](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation_policy) | resource |
| [azurerm_api_management_api_policy.openai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_named_value.ais-mi-client-id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.openai_backend_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_role_assignment.openai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ais_mi_client_id"></a> [ais\_mi\_client\_id](#input\_ais\_mi\_client\_id) | AI Services Managed Identity Client ID for APIM named value | `string` | n/a | yes |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | API Management resource ID (for backend parent\_id) | `string` | n/a | yes |
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | n/a | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | n/a | `any` | n/a | yes |
| <a name="input_apim_gateway_url"></a> [apim\_gateway\_url](#input\_apim\_gateway\_url) | API Management Gateway URL (for OpenAPI template) | `string` | n/a | yes |
| <a name="input_apim_principal_id"></a> [apim\_principal\_id](#input\_apim\_principal\_id) | Principal ID for role assignment (APIM managed identity) | `string` | n/a | yes |
| <a name="input_foundry_backend_ids"></a> [foundry\_backend\_ids](#input\_foundry\_backend\_ids) | Set of Foundry backend resource IDs for role assignment scope | `list(string)` | n/a | yes |
| <a name="input_foundry_backend_names"></a> [foundry\_backend\_names](#input\_foundry\_backend\_names) | List of Foundry backend names (e.g. ['aif-env-001', 'aif-env-002']) | `list(string)` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | n/a | `any` | n/a | yes |
| <a name="input_token_limit"></a> [token\_limit](#input\_token\_limit) | Tokens per minute limit for OpenAI API (used in llm-token-limit policy) | `number` | n/a | yes |
| <a name="input_diagnostic_sampling_percentage"></a> [diagnostic\_sampling\_percentage](#input\_diagnostic\_sampling\_percentage) | APIM診断のサンプリング率（0.0 〜 100.0）。本番環境では 20.0 〜 50.0 を推奨。 | `number` | `100` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | n/a |
<!-- END_TF_DOCS -->