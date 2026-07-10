<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~>2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.80.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~>4.80.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_diagnostic_setting.ai_search](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_search_service.search](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/search_service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_location"></a> [location](#input\_location) | The Azure location where the resources will be created. | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | The ID of the Log Analytics Workspace to send diagnostics logs to. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Azure Cognitive Search service | `string` | n/a | yes |
| <a name="input_rg_name"></a> [rg\_name](#input\_rg\_name) | Resource group name for the search service | `string` | n/a | yes |
| <a name="input_bypass_network_rule"></a> [bypass\_network\_rule](#input\_bypass\_network\_rule) | network rule bypass options. | `string` | `"AzureServices"` | no |
| <a name="input_disableLocalauth"></a> [disableLocalauth](#input\_disableLocalauth) | Disable local authentication for the AI service. | `bool` | `true` | no |
| <a name="input_ip_rules"></a> [ip\_rules](#input\_ip\_rules) | List of allowed IP addresses or CIDR ranges for the AI Search service firewall. | `list(string)` | `[]` | no |
| <a name="input_local_authentication_enabled"></a> [local\_authentication\_enabled](#input\_local\_authentication\_enabled) | Enable local authentication for the search service | `bool` | `false` | no |
| <a name="input_public_network_access"></a> [public\_network\_access](#input\_public\_network\_access) | Whether public network access is enabled for the storage account. Possible values: Enabled, Disabled | `string` | `"Disabled"` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Enable public network access for the search service | `bool` | `false` | no |
| <a name="input_search_service_partition_count"></a> [search\_service\_partition\_count](#input\_search\_service\_partition\_count) | Number of partitions for the search service | `number` | `1` | no |
| <a name="input_search_service_replica_count"></a> [search\_service\_replica\_count](#input\_search\_service\_replica\_count) | Number of replicas for the search service | `number` | `1` | no |
| <a name="input_search_service_sku"></a> [search\_service\_sku](#input\_search\_service\_sku) | SKU for Azure Cognitive Search service | `string` | `"standard"` | no |
| <a name="input_semantic_search_sku"></a> [semantic\_search\_sku](#input\_semantic\_search\_sku) | Semantic search SKU: free or standard. Leave unset to disable. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to assign to the resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_search_service_id"></a> [search\_service\_id](#output\_search\_service\_id) | The resource ID of the Azure Cognitive Search service. |
| <a name="output_search_service_identity_principal_id"></a> [search\_service\_identity\_principal\_id](#output\_search\_service\_identity\_principal\_id) | The principal ID of the system-assigned managed identity for the Azure Cognitive Search service. |
| <a name="output_search_service_identity_tenant_id"></a> [search\_service\_identity\_tenant\_id](#output\_search\_service\_identity\_tenant\_id) | The tenant ID of the system-assigned managed identity for the Azure Cognitive Search service. |
| <a name="output_search_service_name"></a> [search\_service\_name](#output\_search\_service\_name) | The name of the Azure Cognitive Search service. |
<!-- END_TF_DOCS -->