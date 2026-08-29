variable "resource_group_name" {
  description = "Resource group name of the existing API Management instance"
  type        = string
}

variable "api_management_name" {
  description = "Name of the existing API Management instance"
  type        = string
}

variable "prm_api_name" {
  description = "Name of the shared PRM discovery API (oauth-api module's api_name output) that this operation attaches to"
  type        = string
}

variable "mcp_server_id" {
  description = "Short identifier for the MCP server (e.g. \"foundryiq-acl-mcp\", \"toolbox\"), used to build the operation_id/display_name. Must contain only alphanumeric characters, underscores and dashes."
  type        = string
}

variable "mcp_endpoint_path" {
  description = "Full path suffix of the actual MCP client-facing endpoint, i.e. everything after the APIM gateway URL and before any query string (e.g. \"foundryiq-acl-mcp/runtime/webhooks/mcp\" or \"toolbox/api/projects/toolbox-project/toolboxes/toolbox/mcp\"). No leading/trailing slash."
  type        = string
}

variable "mcp_endpoint_query" {
  description = "Query string suffix (including leading \"?\") to append to the \"resource\" field, matching the actual MCP client URL when it requires a query parameter (e.g. \"?api-version=v1\"). Empty if the endpoint takes no query string."
  type        = string
  default     = ""
}

variable "apim_gateway_url" {
  description = "Gateway URL of the API Management instance (used as the \"resource\" field in the metadata response)"
  type        = string
}

variable "scope" {
  description = "OAuth scope advertised in scopes_supported for this MCP server (e.g. https://search.azure.com/.default)"
  type        = string
}
