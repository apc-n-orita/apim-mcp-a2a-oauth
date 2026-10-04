# Technical Details

## Authorization Policies

### `validate-azure-ad-token` per MCP server (audience-based)

Both MCP servers validate the inbound token with APIM's [`validate-azure-ad-token`](https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy) policy, checked against a fixed audience — not a scope, and not a role claim:

- `foundryiq-acl-mcp` — audience `https://search.azure.com/`
- `toolbox` — audience `https://ai.azure.com/`

### foundryiq-acl-mcp: ACL passthrough + Easy Auth via Managed Identity

Covered in the [Overview](README.md#foundry-iq-mcp-docsacl) and its sequence diagram — the caller's `search.azure.com` token is forwarded as `x-ms-query-source-authorization` for AI Search's ACL evaluation, while the backend Function itself is reached with a separate token minted by APIM's managed identity (Easy Auth, audience `api://{oauth-app-id}/`).

**`x-ms-query-source-authorization` isn't limited to the plain document-ACL case used here.** Per [Enforce permissions at query time](https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-retrieve#enforce-permissions-at-query-time-preview), *every* non–Work IQ knowledge source uses the same `https://search.azure.com/.default`-scoped token in this header to carry the end user's identity — this repo's own `foundryiq-acl-mcp` (audience `https://search.azure.com/`) is one instance of that same general rule, not a special case. What differs per knowledge source is only what happens with that identity on the other side:

- **POSIX-like ACLs and RBAC scopes** on Azure Data Lake Storage Gen2 / Blob containers ([Query-time ACL and RBAC enforcement](https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement))
- **Microsoft Purview sensitivity labels** — sourced from Azure Blob Storage, ADLS Gen2, SharePoint in Microsoft 365, **or Microsoft Fabric OneLake** — evaluated against the organization's Purview policies at query time ([Query-time enforcement of Microsoft Purview sensitivity labels](https://learn.microsoft.com/azure/search/search-query-sensitivity-labels)). Note: Fabric items that carry sensitivity labels at the item level (e.g. a whole lakehouse) aren't indexable this way; only labels applied to individual documents inside OneLake are ([OneLake indexer limitations](https://learn.microsoft.com/azure/search/search-how-to-index-onelake-files#limitations)).
- **SharePoint in Microsoft 365 ACLs**, including SharePoint site-group membership (`spg:`-prefixed group IDs), for indexed SharePoint content ([SharePoint access control lists](https://learn.microsoft.com/azure/search/search-indexer-sharepoint-access-control-lists))
- **Remote SharePoint knowledge sources**, where nothing is indexed at all — the header instead lets SharePoint enforce permissions live, via the Copilot Retrieval API ([Remote SharePoint knowledge source](https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-sharepoint-remote))
- **Fabric Data Agent / Fabric IQ (remote, preview)** — also nothing indexed, but the mechanism is a genuine OBO exchange rather than metadata matching: the `x-ms-query-source-authorization` token (scoped to `https://search.azure.com/.default`) is exchanged by the retrieval engine for a Fabric-scoped token, which is then used to query the Fabric Data Agent as that end user ([Fabric Data Agent knowledge source — enforce permissions at query time](https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-fabric-data-agent#enforce-permissions-at-query-time)) — the same shape as `toolbox`'s `foundryiqmcp` OBO connection in this repo, just one layer further out (Foundry IQ → Fabric, instead of Foundry Toolbox → Foundry IQ)

`foundryiq-acl-mcp`'s index (`infra/scripts/ais_set_acl_index.sh`) uses the native POSIX-like ACL/RBAC-scope permission filter (`permissionFilterOption: "enabled"` with `UserIds` / `GroupIds` / `RbacScope` fields), but the same `x-ms-query-source-authorization` header is how the Purview-, SharePoint-, or Fabric-based variants above would plug into the same MCP-server shape instead.

### toolbox: why the caller's own token is passed straight through

Unlike `foundryiq-acl-mcp` and a2a, the `toolbox` product policy does **not** swap the caller's token for APIM's managed identity before forwarding to Foundry. The policy comment explains why:

> Backend authentication: pass the client's original token straight through (do not swap it for the MI). The `foundryiqmcp` connection's UserEntraToken (OBO) assumes the `Authorization` header Foundry receives is "the actual calling user's own token," so overwriting it with APIM's MI token — as done for a2a — would break OBO.

In short: the `foundryiqmcp` connection's OBO exchange only works if the `Authorization` header really is the calling user's own token, so it can't be swapped for APIM's managed identity the way a2a and foundryiq-acl-mcp do it.

**The consequence**: APIM only checks the token's audience, so anyone holding a valid `ai.azure.com` token can call the `toolbox` MCP endpoint directly.

Two ways to close that gap, not mutually exclusive:

**1. Network-level lock-down.** Restrict who can reach the backend at all, or restrict which MCP servers a given client is allowed to add:
- **Foundry private endpoint + public network access disabled** — expose the Foundry account only over a private endpoint ([Configure private link for Foundry](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)) and disable its public network access, so the `toolbox-project` backend itself is unreachable except through APIM's own network path. This requires APIM to reach it privately in turn — i.e., APIM integrated into (or peered with) that same virtual network, which itself requires a VNet-capable APIM SKU ([Standard v2/Premium v2 for outbound VNet integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)).
- **Client-side allow-lists** — e.g., Claude requires a **Team or Enterprise** plan to centrally restrict which MCP servers users may connect to ([Control MCP server access for your organization](https://code.claude.com/docs/en/managed-mcp)); for GitHub Copilot, publish an approved MCP server list through **Azure API Center's MCP registry** instead (see [Register and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server) — API Center can even auto-sync from this APIM instance). For a worked example, see the [API Center hands-on](https://github.com/apc-n-orita/APICenter).

**2. Shrink the blast radius instead.** Accept that direct access is possible, and make sure it can't do anything beyond invoking tools. This repo already isolates the Toolbox in its own Foundry project (`toolbox-project`, separate from `ai-foundry-project` and the verification projects — project-scoped RBAC, not resource-group-wide grants, is the existing pattern here). The current Terraform assigns end users the **Foundry User** role on `toolbox-project`. Microsoft Foundry also has a narrower, purpose-built role for this exact scenario:

> **Foundry Agent Consumer** — Grants access to interact with agent endpoints in a Foundry project. Least-privilege access role for principals that only need to interact with agents.

Per the [Foundry RBAC guidance](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry#minimum-role-assignments-to-get-started): *"If a user or service principal only needs to interact with agents ... without creating or modifying them, assign Foundry Agent Consumer instead of Foundry User."* Assigning **Foundry Agent Consumer** instead of Foundry User on `toolbox-project` means a valid token — however it was obtained — can only invoke agents/tools, not manage the project, deployments, or other resources.

## Load Balancing (with Redis)

`toolbox` uses the same per-caller sticky routing and retry/failover mechanism described in [a2a's Technical Details](../a2a/tech_use.md#load-balancing-with-redis) — `oid` → Redis-backed backend assignment, TTL 24h, failover on repeated 5xx/429/JSON-RPC-shaped errors. The only differences are the Redis key prefix (`toolbox-backend-oid-{oid}` instead of `a2a-backend-oid-{oid}`) and that failover never swaps the passthrough authentication described above, even on a retry to a different backend.

## src/foundryiq-acl-mcp: Implementation Notes

### Functional: tunable cost/latency for retrieval

The knowledge base retrieval request (`shared/kb_client.py`, `_build_request`) is built so its cost and latency can be tuned:

```python
return KnowledgeBaseRetrievalRequest(
    intents=[KnowledgeRetrievalSemanticIntent(search=query)],
    output_mode=KnowledgeRetrievalOutputMode.EXTRACTIVE_DATA,
    retrieval_reasoning_effort=_REASONING_EFFORT_CLASSES[SEARCH_RETRIEVAL_REASONING_EFFORT](),
    include_activity=True,
    max_runtime_in_seconds=SEARCH_MAX_RUNTIME,
)
```

- **`output_mode=EXTRACTIVE_DATA`** is fixed, not configurable — the MCP caller (the agent) composes the final answer from the returned grounding data, so the knowledge base itself must not perform answer synthesis.
- **The query intent is passed through as-is**, "without model-based decomposition" (per the function's docstring) — the knowledge base does not rewrite or expand the query itself.
- **`retrieval_reasoning_effort` is always explicit, defaulting to `low`** — omitting it falls back to the server default (roughly `medium`), which increases agentic `reasoning_tokens` (billed on the Azure AI Search side) without a bound.
- **`max_runtime_in_seconds`** caps the server-side retrieval budget, sized to account for an LLM call happening inside the knowledge base pipeline (e.g., when answer synthesis is enabled elsewhere).

### Secure coding

**Exceptions never surface verbatim to the MCP caller.** `tools/knowledge_retrieve.py` catches failures at each stage and returns a fixed, generic string while the full detail (exception, stack, context) goes only to logs/spans:

- Authorization failure → `"Forbidden"`
- Missing configuration → `"Missing configuration."`
- Retrieval failure → `"Knowledge retrieval failed"`

**Token/credential facts are logger-only, and excluded from tracing.** `shared/auth.py` documents this explicitly: authorization-derived information (whether a token was present, whether it passed) is never set as a span attribute, and is logged only on failure; the success path logs nothing. The reason is simply that authorization tokens themselves must never be recorded — wherever the ACL token needs to be referenced in logs, only a boolean (`acl_header_present`) is recorded, never the token value itself.

### Observability

**Token usage is recorded as span attributes, not log lines.** After summing each retrieval activity entry, token counts are set directly as span attributes (`kb.llm_input_tokens`, `kb.llm_output_tokens`, `kb.llm_total_tokens`, `kb.reasoning_tokens`). Use them to see the breakdown of a single request.

**Token usage is also recorded as metrics, so cost totals aren't lost to trace sampling.** Token consumption drives this tool's cost, so the totals must be accurate. A span that's sampled out takes its token counts with it, but OpenTelemetry metrics are [preaggregated in the SDK and unaffected by sampling](https://learn.microsoft.com/azure/azure-monitor/app/metrics-overview#metrics-preaggregation). `_log_activity` therefore also adds the same values to counters: `kb.llm_input_tokens`, `kb.llm_output_tokens` and `kb.llm_total_tokens` (billed by Azure OpenAI), and `kb.reasoning_tokens` (billed by Azure AI Search, so kept separate).

- The only dimension is `kb.name` — never user IDs or query text.
- Use the metrics for totals and alerts, and the span attributes for a single request's breakdown. With `APPLICATIONINSIGHTS_METRIC_NAMESPACE_OPT_IN=true` (set in `infra/main.tf`), Metrics Explorer groups them under the `foundryiq_acl_mcp.kb_client` namespace; the raw points are in the `customMetrics` table.

```kusto
// Tokens per knowledge base per hour (rows are preaggregated, so sum valueSum)
customMetrics
| where name in ("kb.llm_total_tokens", "kb.reasoning_tokens")
| summarize tokens = sum(valueSum) by name, kb = tostring(customDimensions["kb.name"]), bin(timestamp, 1h)
| order by timestamp desc
```

**Per-source retrieval failures are walked explicitly, because they don't raise.** When Azure AI Search fails to retrieve from one knowledge source among several, it returns that as an entry-level error inside the response's activity array — HTTP 206 Partial Content — not as an exception. Without explicitly inspecting each activity entry's `error` field and logging a warning, a partial failure ("some knowledge sources silently didn't return results") would go completely unnoticed.

**Error logs are exempted from trace-based sampling.** `shared/telemetry.py` sets `configure_azure_monitor(..., enable_trace_based_sampling_for_logs=False)` deliberately: with it enabled, log records attached to a trace that wasn't sampled are dropped along with it. Since the OpenTelemetry distro's rate-limited sampler drops proportionally *more* traces exactly when load is high, tying error-log survival to trace sampling would mean losing the most error visibility at the worst possible time.

**Noisy third-party SDK loggers are silenced to reduce log noise:**

```python
logging.getLogger("azure.core.pipeline.policies.http_logging_policy").setLevel(logging.WARNING)
logging.getLogger("azure.monitor.opentelemetry.exporter.export._base").setLevel(logging.WARNING)
logging.getLogger("azure.identity").setLevel(logging.WARNING)
```

## Enhanced Security

### Foundry Guardrails

A `toolbox` version can carry its own Microsoft Foundry **Guardrails and controls** ([overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview)). The RAI policy itself is configured in the Foundry portal, via the RAI Policies REST API, or as Terraform (`Microsoft.CognitiveServices/accounts/raiPolicies` via the `azapi` provider); the toolbox version then references that policy by name via `policies.rai_config.rai_policy_name` when it's created or updated.

Only a subset of guardrails can be assigned this way: a guardrail is offered as an option for a toolbox only when it has at least one content filter whose intervention point is one of these two:

| Intervention point      | What is scanned                                      |
| ----------------------- | ---------------------------------------------------- |
| Tool call (Preview)     | The action/data `toolbox` proposes to send to a tool |
| Tool response (Preview) | The content returned from a tool back to `toolbox`   |

Besides the usual harmful-content and prompt-injection checks, guardrails include a **PII detection (Preview)** category that can block or annotate personal information passing through.

The role is different from the access control above: `validate-azure-ad-token` and token passthrough decide _who_ may call `toolbox`, while the toolbox's guardrail checks _what content_ crosses the tool boundary afterward (harmful content, PII, etc.). Combining both — access control at the gateway and a guardrail on the toolbox version — covers both sides.

### Masking only part of the PII

Guardrails only block (or annotate) the _entire_ output when PII is detected — they can't redact just the PII portion and let the rest of the text through. For that finer-grained case, Azure AI Language's PII detection (`recognize_pii_entities`) is the tool for the job.

#### Trying it out

[`samplecodes/test_language-service-pii.py`](../../samplecodes/test_language-service-pii.py) shows a minimal, standalone call to it via `LANGUAGE_ENDPOINT`, pointed at this repo's `cognitiveservices` APIM API:

```bash
export LANGUAGE_ENDPOINT="$(azd env get-value LANGUAGE_ENDPOINT)"
python samplecodes/test_language-service-pii.py
```

#### Using it inside `foundryiq-acl-mcp`

The toolbox's guardrail sits at the boundary between `toolbox` and the MCP server it forwards to — it doesn't reach into `foundryiq-acl-mcp`'s own code. For partial masking there, the same call shown in that sample script can be added directly inside the Function MCP's existing request flow (`tools/knowledge_retrieve.py` → `shared/kb_client.py`), at either of two points:

- **Input**: the `query` string, before it's sent to Foundry IQ's `retrieve()` call — masks PII typed by the caller before it ever reaches the knowledge base or gets logged in Azure AI Search's own telemetry.
- **Output**: the grounding text extracted from Foundry IQ's response, before it's returned to the MCP caller — masks PII that lives in the indexed source documents themselves, which would otherwise surface verbatim in the tool's result.

The two points are independent — mask the query alone, the output alone, or both, depending on which side the risk is judged to matter more.

### Conditional Access

Entra ID **Conditional Access** adds a second, independent layer in front of the audience check described above: it is evaluated when Entra ID issues or refreshes an access token, so it can gate _who obtains a token_ for each MCP server's audience (`https://search.azure.com/` for `foundryiq-acl-mcp`, `https://ai.azure.com/` for `toolbox`) before APIM's `validate-azure-ad-token` ever sees the request. Policies can use conditions such as **Microsoft Entra ID Protection** risk (sign-in risk and user risk; requires Entra ID P2) and **network restrictions** (trusted locations) ([risk-based access policies](https://learn.microsoft.com/entra/id-protection/concept-identity-protection-policies), [network assignment](https://learn.microsoft.com/entra/identity/conditional-access/concept-assignment-network)).

- **Policies target the resource (the token's audience), not the client.** Conditional Access applies to the service being called, so the policy is set on the resource behind each audience, not on Claude, GitHub Copilot, or any other MCP client ([target resources](https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps)). Some resources don't appear in the policy's app picker; in that case the service principal has to be added to the tenant, or the policy has to target **All resources**.
- **It is evaluated at token issuance, not on every call.** Conditional Access doesn't close the `toolbox` gap by itself: a token that was already issued keeps working until it expires (60 to 90 minutes by default), unless the resource supports [Continuous Access Evaluation](https://learn.microsoft.com/entra/identity/conditional-access/concept-continuous-access-evaluation). Treat it as a complement to the network lock-down and the **Foundry Agent Consumer** role above, not a replacement.

## See also

- [Hands-On](README.md) — setup and walkthrough for both MCP servers
- [a2a Technical Details](../a2a/tech_use.md) — OAuth authorization and load-balancing mechanisms shared with `toolbox`

## Next

With the MCP track complete, continue to the [a2a hands-on](../a2a/README.md).
