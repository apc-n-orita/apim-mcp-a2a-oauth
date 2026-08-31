# End-to-End A2A / MCP Agent Protection with API Management × Microsoft Foundry

This repository is a hands-on lab for securely exposing and calling Microsoft Foundry capabilities — a **prompt agent** over the **A2A (Agent2Agent) protocol**, and **MCP (Model Context Protocol)** servers — all fronted by **Azure API Management (APIM)**.

It builds on top of an existing [apim-mcp-oauth](https://github.com/apc-n-orita/apim-mcp-oauth) deployment, reusing its shared APIM instance, Application Insights, and Log Analytics Workspace, and layers two hands-on tracks on top of it.

The whole environment is provisioned as IaC with Terraform / `azd up`. See [infra/README.md](infra/README.md) for the IaC details.

## Hands-On Overview

See [handson/README.md](handson/README.md) for the full hands-on flow. It covers two tracks:

- **[MCP](handson/mcp/README.md)** — exposing and protecting MCP servers through APIM: [foundry iq mcp (docsacl)](handson/mcp/README.md#foundry-iq-mcp-docsacl) (an ACL-protected Foundry IQ knowledge base search tool) and [toolbox](handson/mcp/README.md#toolbox) (a Foundry Toolbox MCP endpoint bundling multiple tool connections)
- **[A2A](handson/a2a/README.md)** — securely calling a Foundry prompt agent (`tartaria-agent`) over the A2A protocol through APIM, with Entra ID / App Role–based authorization, sticky load balancing with failover, and JSON-RPC error telemetry.

## Deploy Hands-On Environment

A single deployment provisions the environment for both the A2A and MCP hands-on tracks.

### Prerequisites

- Terraform (v1.5 or later recommended)
- Azure Developer CLI (`azd`, v1.9 or later recommended)
- Azure CLI (`az`), logged in with `az login`
- An existing **apim-mcp-oauth** deployment ([apc-n-orita/apim-mcp-oauth](https://github.com/apc-n-orita/apim-mcp-oauth)) — this lab adds its configuration to that APIM instance and reuses its Application Insights / Log Analytics Workspace

### Prepare the Hands-On Document

The hands-on requires a sample PDF to be indexed into AI Search.

> **Disclaimer**: Follow the download steps below at your own discretion and responsibility.

**Steps**

1. Open [https://archive.org/details/one-world-tartarians_202304](https://archive.org/details/one-world-tartarians_202304) in your browser.
2. Open the PDF and confirm that around **page 4** it contains the following statement:
   > _"This Book is Open Sourced to Download, Copy and Share / No copyrights reserved"_
3. Click **PDF** under **DOWNLOAD OPTIONS** on the right side of the page to download it.
4. Place the downloaded PDF in `infra/docs/` (any file name).

```bash
mv /path/to/<downloaded-file>.pdf infra/docs/
```

### Deployment Steps

**1. Fill in `infra/main.tfvars.json`**

Set the five existing-resource values to those of your **apim-mcp-oauth** deployment. You can look them up with one command each:

```bash
# Resource group of the apim-mcp-oauth deployment (adjust the env name)
export MCP_RG=$(az group list --tag azd-env-name=<apim-mcp-oauth-env-name> --query '[0].name' -o tsv)
export APIM_NAME=$(az apim list -g $MCP_RG --query '[0].name' -o tsv)

echo $APIM_NAME                                                                                                       # -> apim_name
az resource list -g $MCP_RG --resource-type Microsoft.Insights/components --query '[0].name' -o tsv                  # -> application_insights_name
az resource list -g $MCP_RG --resource-type Microsoft.OperationalInsights/workspaces --query '[0].name' -o tsv       # -> log_analytics_workspace_name
az rest --method get --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$MCP_RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis?api-version=2025-09-01-preview" \
  --query "value[?contains(properties.path, 'la-mcp')].properties.path | [0]" -o tsv                                # -> logicmcp_api_name
```

```jsonc
// infra/main.tfvars.json (excerpt)
{
  "resource_group_name": "<MCP_RG>",
  "apim_name": "<apim name>",
  "application_insights_name": "<application insights name>",
  "log_analytics_workspace_name": "<log analytics workspace name>",
  // logicmcp_api_name: the API name/path on APIM for apim-mcp-oauth's logicappmcp (Logic App MCP),
  // used as the target of the toolbox's logicmcp connection
  "logicmcp_api_name": "<logicmcp api name/path>",
  ...
}
```

**2. Deploy**

```bash
azd up
```

> **Important:** When prompted, select the **same subscription and location as the apim-mcp-oauth deployment**.

All new resources (Foundry accounts/projects, prompt agents, MCP server backends, AI Search + knowledge base, storage, Managed Redis, Entra ID `a2a-agent-*` application) are created in the same resource group as the APIM instance.

### Delete Resources

```bash
azd down
```

> The APIM / Application Insights / Log Analytics Workspace are existing resources referenced by `data` sources and are **not** deleted. Note that APIM sub-resources created by this lab (the `tartaria-agent`/MCP APIs, products, named values, external cache) are removed.

## Hands-On

With the environment deployed, work through the hands-on steps for each track:

- **[MCP](handson/mcp/README.md)** (foundry iq mcp / toolbox)
- **[A2A](handson/a2a/README.md#hands-on)**

## A Note on Where This Sits

Having just wired up an A2A agent and two MCP servers behind one gateway, this repository is the second step in a three-part arc: [apim-mcp-oauth](https://github.com/apc-n-orita/apim-mcp-oauth) → **apim-mcp-a2a-oauth** → [APICenter](https://github.com/apc-n-orita/APICenter).

Just like the first repository, this one holds both the **Hierophant** and the **Hermit** at once — the mixture simply carries a heavier inward weight here. The same `validate-azure-ad-token` policy and App Role pattern carried over from the first repository, Easy Auth is Azure Functions' own built-in feature, and Foundry IQ's per-request ACL header is Microsoft's own documented pattern — that's the Hierophant, still present here, none of these individual pieces invented from scratch. But wiring APIM's authorization layer, Easy Auth, and that ACL pattern together, across Foundry Agents over A2A and MCP servers (`foundryiq-acl-mcp`, `toolbox`) alike, into one coherent authorization/resilience design, wasn't written down anywhere; it had to be found inward, by the team itself, before it could be written down here. That's the Hermit, turning inward together rather than outward to the crowd, trusting the light that comes from within the team rather than one already lit by others.

That inward work doesn't stay inward. It carries forward into [APICenter](https://github.com/apc-n-orita/APICenter), where this repository's Agent and MCP servers, together with the first repository's security foundation, are gathered — each keeping its own shape — into a single circle: the **World**. See APICenter's [Closing Thoughts](https://github.com/apc-n-orita/APICenter#closing-thoughts) for that fuller picture.
