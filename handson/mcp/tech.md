# Technical Details

## Authorization Policies

### `validate-azure-ad-token` per MCP server (audience-based)

Both MCP servers validate the inbound token with APIM's [`validate-azure-ad-token`](https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy) policy, checked against a fixed audience — not a scope, and not a role claim:

- `foundryiq-acl-mcp` — audience `https://search.azure.com/`
- `toolbox` — audience `https://ai.azure.com/`

### foundryiq-acl-mcp: ACL passthrough + Easy Auth via Managed Identity

Covered in the [Overview](README.md#foundry-iq-mcp-docsacl) and its sequence diagram — the caller's `search.azure.com` token is forwarded as `x-ms-query-source-authorization` for AI Search's ACL evaluation, while the backend Function itself is reached with a separate token minted by APIM's managed identity (Easy Auth, audience `api://{oauth-app-id}/`).

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

**Token usage is recorded as span attributes, not log lines.** After summing each retrieval activity entry, token counts are set directly as span attributes (`kb.llm_input_tokens`, `kb.llm_output_tokens`, `kb.llm_total_tokens`, `kb.reasoning_tokens`).

**Per-source retrieval failures are walked explicitly, because they don't raise.** When Azure AI Search fails to retrieve from one knowledge source among several, it returns that as an entry-level error inside the response's activity array — HTTP 206 Partial Content — not as an exception. Without explicitly inspecting each activity entry's `error` field and logging a warning, a partial failure ("some knowledge sources silently didn't return results") would go completely unnoticed.

**Error logs are exempted from trace-based sampling.** `shared/telemetry.py` sets `configure_azure_monitor(..., enable_trace_based_sampling_for_logs=False)` deliberately: with it enabled, log records attached to a trace that wasn't sampled are dropped along with it. Since the OpenTelemetry distro's rate-limited sampler drops proportionally *more* traces exactly when load is high, tying error-log survival to trace sampling would mean losing the most error visibility at the worst possible time.

**Noisy third-party SDK loggers are silenced to reduce log noise:**

```python
logging.getLogger("azure.core.pipeline.policies.http_logging_policy").setLevel(logging.WARNING)
logging.getLogger("azure.monitor.opentelemetry.exporter.export._base").setLevel(logging.WARNING)
logging.getLogger("azure.identity").setLevel(logging.WARNING)
```

## See also

- [Hands-On](README.md) — setup and walkthrough for both MCP servers
- [a2a Technical Details](../a2a/tech_use.md) — OAuth authorization and load-balancing mechanisms shared with `toolbox`

## Next

With the MCP track complete, continue to the [a2a hands-on](../a2a/README.md).
