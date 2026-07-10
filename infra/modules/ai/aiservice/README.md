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
| [azapi_resource.ai_foundry](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_cognitive_deployment.deployment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cognitive_deployment) | resource |
| [azurerm_monitor_diagnostic_setting.ai_foundry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ai_model"></a> [ai\_model](#input\_ai\_model) | AI model deployment configurations (複数モデル対応). | <pre>list(object({<br/>    model                      = string<br/>    version                    = string<br/>    format                     = string<br/>    deploytype                 = string<br/>    capacity                   = number<br/>    version_upgrade_option     = optional(string)<br/>    dynamic_throttling_enabled = optional(bool)<br/>  }))</pre> | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The Azure region where resources will be deployed. | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | The ID of the Log Analytics workspace for diagnostics. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name of the AI service. | `string` | n/a | yes |
| <a name="input_network_acls"></a> [network\_acls](#input\_network\_acls) | Network ACLs for the AI service. | <pre>object({<br/>    default_action = optional(string, "Deny")<br/>    bypass         = optional(string, "AzureServices")<br/>  })</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group. | `string` | n/a | yes |
| <a name="input_disableLocalauth"></a> [disableLocalauth](#input\_disableLocalauth) | Disable local authentication for the AI service. | `bool` | `true` | no |
| <a name="input_ip_rules"></a> [ip\_rules](#input\_ip\_rules) | List of allowed IP addresses or CIDR ranges for the AI Foundry service firewall. | `list(string)` | `[]` | no |
| <a name="input_public_network_access"></a> [public\_network\_access](#input\_public\_network\_access) | Whether public network access is enabled for the storage account. Possible values: Enabled, Disabled | `string` | `"Disabled"` | no |
| <a name="input_rai_policy_name"></a> [rai\_policy\_name](#input\_rai\_policy\_name) | The name of the Responsible AI policy to apply to the AI service. | `string` | `"Microsoft.DefaultV2"` | no |
| <a name="input_subnet_id_agent"></a> [subnet\_id\_agent](#input\_subnet\_id\_agent) | The subnet ID for agent network injection. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to assign to the resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ai_foundry_id"></a> [ai\_foundry\_id](#output\_ai\_foundry\_id) | The resource ID of the AI foundry. |
| <a name="output_internal_id"></a> [internal\_id](#output\_internal\_id) | The internal ID of the AI foundry |
| <a name="output_location"></a> [location](#output\_location) | The location of the AI foundry. |
| <a name="output_name"></a> [name](#output\_name) | The name of the AI foundry. |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | The principal ID of the AI foundry's managed identity. |
<!-- END_TF_DOCS -->