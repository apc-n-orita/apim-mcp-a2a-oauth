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
az apim api list -g $MCP_RG --service-name $APIM_NAME --query "[?contains(path, 'la-mcp')].path | [0]" -o tsv        # -> logicmcp_api_name
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

## On Balance: Security and Developer Enablement as Separate Layers

This hands-on demonstrates a powerful architectural principle often misunderstood in practice: **security and developer experience are not opposing forces that demand compromise—they are distinct layers that can each operate at full capacity simultaneously.**

### The Myth of Trade-off

Many organizations approach security and developer experience as a zero-sum game. The result is a middle ground where both suffer:

- Security teams demand strict controls that slow development.
- Developers circumvent controls to maintain velocity.
- Neither team is satisfied, and the actual safety posture becomes ambiguous.

### The Principle of Layers

This architecture separates **authorization** and **resilience** into distinct operational layers:

1. **Authorization Layer (Security at 100%)**: The APIM policy enforces OAuth token validation and **App Role–based authorization**—a hard boundary. If your `roles` claim does not match the target agent name, you receive a `403 Forbidden` response. No compromise, no flexibility. This layer answers the question: _"Are you authorized?"_ The answer is binary: yes or no. (See [OAuth Authorization](handson/a2a/tech_use.md#oauth-authorization-validate-azure-ad-token--role-based-access) for implementation details.)

2. **Resilience Layer (Developer Experience at 100%)**: Once you have proven you belong, the system assumes success will happen—and **sticky load balancing with automatic failover** ensures you get a working backend with minimal latency. Requests route consistently to the same Foundry account for 24 hours; if that account fails, traffic transparently shifts to another, with Redis managing the state. The developer calling the agent never sees an outage; they experience a seamless, predictable response. (See [Sticky Load Balancing](handson/a2a/tech_use.md#load-balancing-with-redis) and [Retry and Failover](handson/a2a/tech_use.md#load-balancing-with-redis) for implementation details.)

These two layers do not compete for priority. Authorization answers _who_ can do what. Resilience answers _how the system behaves when that authorized person acts_. Both operate at full force, without compromise.

### How the Layers Work in This Lab

- **Security layer asks**: "Does your `roles` claim contain the agent name?" This is evaluated before any backend selection occurs—authorization is the outermost gate.
- **Resilience layer asks**: "Which backend should this caller use, and what happens if it becomes unavailable?" Redis sticky routing and APIM failover handle these concerns transparently, without requiring the caller to retry or change their code.

### The Spirit Behind This Design

This is not merely a technical pattern. It reflects a deeper principle: **protection and freedom are not opposed**. In the same way that a well-designed firewall does not slow legitimate traffic but rather clarifies boundaries, this architecture makes the rules clear—and then steps out of the way.

Security is not "a restriction on developers and users"—it is "a safety mechanism to prevent misuse." Once that mechanism is in place and understood, the developer's experience becomes smooth, fast, and predictable. The two goals do not balance through negotiation; they integrate through clarity.

When you design systems this way—layering concerns so each can be decisive and complete—you enable teams to move with confidence. Architects can enforce hard boundaries without apology. Developers can build fast without circumventing controls. Both sides win not through compromise, but through **structural clarity about which layer owns which decision**.

That is the architecture you see here—and it is both secure and enabling.

## A Note on Where This Sits

This repository is the second step in a three-part arc: [apim-mcp-oauth](https://github.com/apc-n-orita/apim-mcp-oauth) → **a2a-agent-foundry** → [APICenter](https://github.com/apc-n-orita/APICenter).

Where the first repository built from what was already documented — established OAuth patterns, existing guidance, public precedent — this one had no such map to follow. Wiring APIM, Foundry Agents, and the A2A protocol into a single authorization/resilience design wasn't something to look up; it had to be worked out from the inside, alone, before it could be written down here. In tarot terms, if the first repository is the **Hierophant** — learning the tradition — this one is the **Hermit**: stepping away from the crowd, holding up a single lantern, trusting the light that comes from within rather than one already lit by others.

That inward work doesn't stay inward. It carries forward into [APICenter](https://github.com/apc-n-orita/APICenter), where this repository's Agents and APIs, together with the first repository's security foundation, are gathered — each keeping its own shape — into a single circle: the **World**. See APICenter's [Closing Thoughts](https://github.com/apc-n-orita/APICenter#closing-thoughts) for that fuller picture.
