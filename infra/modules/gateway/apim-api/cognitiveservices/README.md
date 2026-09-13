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
| [azapi_resource.backend_pool](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.cogni_backend](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_api.cognitiveservices](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_diagnostic.cognitiveservices](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_policy.cognitiveservices](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_named_value.cogni_backend_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.mi_client_ids](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.ops_group_ids](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_role_assignment.cognitiveservices](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | n/a | `string` | n/a | yes |
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | n/a | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | n/a | `any` | n/a | yes |
| <a name="input_apim_gateway_url"></a> [apim\_gateway\_url](#input\_apim\_gateway\_url) | n/a | `string` | n/a | yes |
| <a name="input_apim_principal_id"></a> [apim\_principal\_id](#input\_apim\_principal\_id) | Principal ID for role assignment (APIM managed identity) | `string` | n/a | yes |
| <a name="input_foundry_backend_ids"></a> [foundry\_backend\_ids](#input\_foundry\_backend\_ids) | Set of Foundry backend resource IDs for role assignment scope | `list(string)` | n/a | yes |
| <a name="input_foundry_backend_names"></a> [foundry\_backend\_names](#input\_foundry\_backend\_names) | List of Foundry backend names (e.g. ['aif-env-001', 'aif-env-002']) | `list(string)` | n/a | yes |
| <a name="input_mi_client_ids"></a> [mi\_client\_ids](#input\_mi\_client\_ids) | Managed identity client ID(s) allowed to call this API directly (e.g. the shared 'mcp' user-assigned identity used by toolbox / foundryiq-acl-mcp) | `list(string)` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | n/a | `any` | n/a | yes |
| <a name="input_diagnostic_sampling_percentage"></a> [diagnostic\_sampling\_percentage](#input\_diagnostic\_sampling\_percentage) | APIM診断のサンプリング率（0.0 〜 100.0）。本番環境では 20.0 〜 50.0 を推奨。 | `number` | `100` | no |
| <a name="input_ops_group_ids"></a> [ops\_group\_ids](#input\_ops\_group\_ids) | Entra ID group object ID(s) allowed to call this API directly (empty = no group allowed) | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | n/a |
| <a name="output_api_path"></a> [api\_path](#output\_api\_path) | n/a |
<!-- END_TF_DOCS -->