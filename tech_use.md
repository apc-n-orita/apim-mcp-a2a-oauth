# Technical Details

## APIM Policy Explanation

The `A2A` product policy ([a2a_product_policy.xml](infra/modules/gateway/apim-api/a2a-agent/files/policy/a2a_product_policy.xml)) implements three mechanisms in a single pipeline: OAuth authorization, sticky load balancing across Foundry backends, and JSON-RPC error telemetry. The `tartaria-agent` API policy ([a2a_api_policy.xml](infra/modules/gateway/apim-api/a2a-agent/files/policy/a2a_api_policy.xml)) adds a per-caller rate limit on top.

### Load Balancing (with Redis)

The list of Foundry backends is held in the `{{a2a-backends}}` named value — a comma-separated list of Foundry account names that Terraform builds automatically from the accounts created via `ai_locations`. The policy splits the list at runtime and assigns one backend per request:

| Request type | Caller identity available? | Assignment method |
|---|---|---|
| Agent card (`.../agent-card.json`) | No (discovery path, unauthenticated) | `MD5(request ID) % N` — uniform random per request |
| A2A JSON-RPC (`message/send` etc.) | Yes (`oid` claim from the validated JWT) | **Sticky per caller**: Redis lookup `a2a-backend-oid-{oid}` → on miss, `MD5(oid) % N` → stored in Redis for 24 h |

The sticky assignment is a **read-mostly** flow — the cache write happens only once per caller:

```xml
<!-- 1) Look up this caller's existing assignment in Redis -->
<cache-lookup-value key="@("a2a-backend-oid-" + (string)context.Variables["oid"])"
                    variable-name="assignedBackendId" default-value="" caching-type="external" />
<choose>
    <!-- 2) Cache MISS = first request from this caller (assignedBackendId is empty) -->
    <when condition="@(string.IsNullOrEmpty((string)context.Variables["assignedBackendId"]))">
        <!-- 2a) Compute the assignment deterministically: MD5(oid) % N -->
        <set-variable name="assignedBackendId" value="@{ /* MD5(oid) % backends.Length */ }" />
        <!-- 2b) Persist it for 24h — this store runs ONLY on the first request -->
        <cache-store-value key="@("a2a-backend-oid-" + (string)context.Variables["oid"])"
                           value="@((string)context.Variables["assignedBackendId"])"
                           duration="86400" caching-type="external" />
    </when>
    <!-- Cache HIT: assignedBackendId is already set from Redis — no store, same backend as before -->
</choose>
```

In other words: the **first** request from a caller computes `MD5(oid) % N` and writes the result to Redis; **every subsequent** request within 24 h finds the entry on lookup, skips the store, and goes to the same backend. That is what makes the assignment "sticky" — the caller's A2A conversation stays on one Foundry backend (conversation state is backend-local), while the deterministic hash spreads *different* callers across backends. Redis is written again only when the failover path reassigns the caller, described next.

**Retry and failover** (in the `<backend>` section): the retry condition is *no response / 429 / 5xx / JSON-RPC error in the body*. Attempts 1–4 retry the assigned backend at 2-second intervals; attempt 5 fails over to a deterministically chosen different backend and **rewrites the Redis sticky assignment**, so subsequent requests from that caller avoid the unhealthy backend for the next 24 h — a circuit-breaker effect implemented purely through the sticky map.

**External cache**: [`cache-lookup-value`](https://learn.microsoft.com/azure/api-management/cache-lookup-value-policy) / [`cache-store-value`](https://learn.microsoft.com/azure/api-management/cache-store-value-policy) with `caching-type="external"` require an [external Redis-compatible cache](https://learn.microsoft.com/azure/api-management/api-management-howto-cache-external) registered on APIM. The Terraform configuration is in [infra/main.tf](infra/main.tf) (`azurerm_managed_redis.a2a_cache` and `azurerm_api_management_redis_cache.a2a_external_cache`):

```hcl
resource "azurerm_managed_redis" "a2a_cache" {
  sku_name                  = "Balanced_B0"
  high_availability_enabled = false        # hands-on setting — enable in production (see below)

  default_database {
    access_keys_authentication_enabled = true
    clustering_policy                  = "EnterpriseCluster"
    ...
  }
}
```

- **Production: configure high availability.** This hands-on sets `high_availability_enabled = false` to minimize cost, but the official guidance is explicit: *"Don't run in non-HA mode outside of development and test scenarios"* — non-HA instances have **no availability SLA** ([Azure Managed Redis architecture](https://learn.microsoft.com/azure/redis/architecture#running-without-high-availability-mode-enabled)). The [reliability guide](https://learn.microsoft.com/azure/reliability/reliability-managed-redis) recommends that production instances **use high availability (multiple nodes)** and **zone redundancy** (applied automatically when an HA instance is deployed in a region with availability zones). Note that HA can be enabled later on a non-HA instance, but cannot be reversed once enabled.
- **Why `clustering_policy = "EnterpriseCluster"`.** Azure Managed Redis offers three [cluster policies](https://learn.microsoft.com/azure/redis/architecture#cluster-policies): OSS, Enterprise, and Non-clustered. The Enterprise policy *"uses a single endpoint for all client connections"* and *"routes all requests to a single Redis node that acts as a proxy. This node internally routes requests to the correct node in the cluster"* — i.e., **APIM sees one endpoint while sharding and load balancing happen behind the proxy**, and the client *"doesn't need to support Redis Clustering"*. APIM connects to the external cache with a plain connection string (`<name>:10000,password=<key>,ssl=True,abortConnect=False`) and is not a cluster-aware client, so the single-endpoint Enterprise policy is the appropriate choice here (the OSS policy requires cluster-aware clients that handle `MOVED`/`ASK` redirections).

### OAuth Authorization (validate-azure-ad-token + role-based access)

Every A2A request (the unauthenticated agent-card discovery path excluded) is validated in two steps.

**1. Token validation** — [`validate-azure-ad-token`](https://learn.microsoft.com/azure/api-management/validate-azure-ad-token-policy) verifies the signature (against the tenant JWKS), issuer, expiry, and audience:

```xml
<validate-azure-ad-token tenant-id="{{EntraIDTenantId}}" output-token-variable-name="jwt"
                         failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
    <audiences>
        <audience>api://{{a2a-oauth-app-id}}/</audience>
    </audiences>
</validate-azure-ad-token>
```

**2. Role-based authorization** — the agent name is extracted from the URL path (`/agents/{agentName}/`) and compared with the token's `roles` claim:

- **Exact match**: role `tartaria-agent` permits the `tartaria-agent` endpoint.
- **Wildcard prefix match**: role `S1-*` permits any agent whose name starts with `S1-`.

If no rule matches, APIM returns `403 Access denied: role does not match agent '{agentName}'`. Because the App Roles on the `a2a-agent` application allow both **Users/Groups and Applications** as members, the same authorization model covers human users and managed identities (e.g., Foundry project MIs) uniformly — the `verify-with-approle` / `verify-without-approle` projects in this hands-on demonstrate exactly this boundary.

After authorization, `authentication-managed-identity` (resource `https://ai.azure.com/`) replaces the `Authorization` header with the APIM managed identity token before forwarding — the Foundry backend never sees the caller's original token (APIM acts as the token broker).

### Why App Roles at APIM, Not Foundry Agent-Scope RBAC Directly

Microsoft Foundry itself supports assigning RBAC roles at the scope of an individual agent — a role such as **Foundry Agent Consumer** can be assigned directly at `.../projects/{project}/agents/{agentName}`, restricting endpoint access to that one agent without granting access to the rest of the project ([Role-based access control for Microsoft Foundry — agent-scope role assignments](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry#manage-role-assignments)). Assigning this role directly to a caller's identity is enough, on its own, for that caller to invoke the agent's endpoint straight from Foundry — no APIM involvement required.

This hands-on deliberately does **not** rely on that path for end-user access. The goal here is to demonstrate **end-to-end, token-level access control**: a single user token is validated and authorized against the `roles` claim baked into that token, and only after that check does APIM (as the token broker) mint a fresh Foundry-scoped token to forward the request. Combined with `disableLocalAuth` on every Foundry account (see below), this design has a second, load-bearing purpose: it forces every caller through APIM. If end users instead held Foundry agent-scope RBAC roles directly, they could call the Foundry endpoint directly and skip APIM's App Role check, load balancing, rate limiting, and JSON-RPC error telemetry entirely — the gateway would become optional rather than mandatory.

**Claim-based (APIM App Role) vs. live RBAC (Foundry agent scope)**

| | APIM App Role (`roles` claim) | Foundry Agent-Scope RBAC |
|---|---|---|
| What's checked | The `roles` claim inside the already-issued JWT (baked in at token issuance) | The live Azure RBAC role-assignment store, evaluated on each request — the same model used for every other Azure resource |
| Where the check happens | APIM policy, before ever reaching Foundry | Foundry's own data plane, at the scope of the agent |
| Propagation of a **new** grant (human user) | Only after the caller acquires a new token; App Role changes aren't retroactive to already-issued tokens, and an already-cached token stays valid for its normal lifetime (typically up to ~1 hour) before a refresh picks up the new claim | Near-immediate — the RBAC store is authoritative and re-evaluated per request |
| Propagation of a **new** grant (service principal / managed identity) | Managed identity token services cache per-resource for **up to ~24 hours**; an App Role assignment can take that long to take effect for a service principal ([Use managed identities for App Service and Azure Functions](https://learn.microsoft.com/azure/app-service/overview-managed-identity#configure-the-target-resource): *"back-end services for managed identities maintain a cache per resource URI for around 24 hours... you might need to wait up to around 24 hours for the Azure resource that's using the identity to have the correct access"*) | No comparable lag |
| Network path | Requires going through APIM (paired with `disableLocalAuth`, this is what makes APIM mandatory) | Calls the Foundry data-plane endpoint directly — APIM is bypassed entirely unless network access is also restricted |

This is the same class of tradeoff already noted for [PIM for Groups](#production-considerations-deploying-identity-and-jit-access) below: claims embedded in a token lag behind the authorization source of truth, while a live RBAC check does not.

**If you use Foundry agent-scope RBAC**, expose the Foundry account via a [private endpoint](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link), with APIM reaching it over that private link.

### JSON-RPC Error Telemetry to Application Insights

The A2A protocol is JSON-RPC: **a failed agent run still returns HTTP 200**, with the failure expressed only inside the body (`{"error": {"code": ..., "message": ...}}`). This creates a blind spot in standard APIM telemetry:

- In the APIM request logs, these calls are recorded as **successful (200) requests** — indistinguishable from healthy traffic.
- The API diagnostics are configured in Terraform ([a2a-agent.tf](infra/modules/gateway/apim-api/a2a-agent/a2a-agent.tf), `azurerm_api_management_api_diagnostic.a2a_api`) with `always_log_errors = true` and a configurable `sampling_percentage`. `alwaysLog: allErrors` is officially defined as *"Always log all **erroneous** request regardless of sampling settings"* ([Diagnostic REST reference](https://learn.microsoft.com/rest/api/apimanagement/diagnostic/create-or-update#alwayslog)) — i.e., HTTP errors are exempt from sampling and always recorded even when the sampling percentage is lowered. However, an HTTP 200 JSON-RPC failure is **not classified as an erroneous request**, so it remains subject to sampling and never surfaces as a failure signal.

To close this gap, the product policy parses the response body after every attempt (`preserveContent: true`), and when `error.message` is present it pushes an exception **directly to the Application Insights `exceptions` table** via the ingestion API (`{{app-insights-ingestion-endpoint}}/v2.1/track`), authenticated with the APIM managed identity (Entra ID token for `https://monitor.azure.com`):

```xml
<send-one-way-request>
    <set-url>{{app-insights-ingestion-endpoint}}/v2.1/track</set-url>
    <set-method>POST</set-method>
    <set-header name="Authorization" exists-action="override">
        <value>@("Bearer " + context.Variables.GetValueOrDefault<string>("appi-token", ""))</value>
    </set-header>
    ...
</send-one-way-request>
```

The exception is recorded as type `JsonRpcError` with `agentName`, `backend`, `attempt`, `errorCode`, and `errorMessage` properties, so backend-level A2A failures are queryable and alertable even though every HTTP status was 200. [`send-one-way-request`](https://learn.microsoft.com/azure/api-management/send-one-way-request-policy) *"sends the provided request to the specified URL without waiting for a response"* — fire-and-forget, so telemetry adds no latency to the client response (the tradeoff, per the docs, is that a failed telemetry send is not reported). The same body inspection also feeds the retry condition, which is why JSON-RPC failures trigger retry/failover as well.

> **Prerequisite**: the APIM managed identity must hold **Monitoring Metrics Publisher** on the Application Insights resource.

### Per-Caller Rate Limiting

The API-level policy applies `rate-limit-by-key` with the caller's `oid` as the counter key (default: 20 calls / 60 s, configurable via `a2a_rate_limit_calls` in `main.tfvars.json`). The unauthenticated agent-card path is excluded because no `oid` is available there. The routed backend is exposed to clients via the `X-Routed-Backend` response header for debugging.

## Foundry: API Keys Disabled (RBAC-Only Access)

All Foundry accounts created by this IaC disable API-key (local) authentication ([aiservice module](infra/modules/ai/aiservice/aiservice.tf)):

```hcl
properties = {
  # API keys disabled — data-plane access is Entra ID + RBAC only
  disableLocalAuth = var.disableLocalauth   # true
  ...
}
```

This removes API-key authentication from the account entirely ([Disable local authentication in Foundry Tools](https://learn.microsoft.com/azure/ai-services/disable-local-auth)) — **every data-plane call (agents API, A2A endpoint, model inference) requires a Microsoft Entra ID token**, and the token's identity must hold an appropriate RBAC role. Without the required role, direct access to the Foundry endpoint is impossible even with a valid tenant token.

The only identities granted data-plane access by this IaC are:

| Identity | Roles (scope) | Purpose |
|---|---|---|
| APIM managed identity | Foundry User (each Foundry project) | Forwarding A2A requests — the production traffic path |
| Foundry project MI | Foundry User (own project), Search Index Data Reader (AI Search), Monitoring Metrics Publisher / Reader (Application Insights) | Agent runtime, Foundry IQ knowledge base retrieval, telemetry |
| Deploying user | Foundry User (each project) | Agent provisioning (`deploy_prompt_agent.sh`), playground testing |

Consequences of this design:

- **Ordinary callers cannot bypass APIM.** Calling `https://{account}.services.ai.azure.com/...` directly requires a Foundry RBAC role on the project. Since only the identities above hold one, the APIM gateway — with its own App Role authorization, rate limiting, and telemetry — is the only available path for everyone else.
- **No secrets to leak or rotate** on the Foundry side. The same keyless principle is applied across the stack: AI Search has `local_authentication_enabled = false` (RBAC + Entra tokens only) and the storage account has `shared_access_key_enabled = false`.
- Authorization changes are managed purely through Azure RBAC role assignments — auditable via Activity Log, and revocable without touching the workload.

### Production Considerations: Deploying Identity and JIT Access

**Current hands-on setup**: the user who runs `azd up` holds standing **Foundry User** assignments (used for agent provisioning and playground testing).

**Production recommendation 1 — CI/CD service identity with workload identity federation**: provisioning (Terraform / `azd`, `deploy_prompt_agent.sh`) should run under a pipeline identity instead of a human account. For GitHub Actions, use [workload identity federation](https://learn.microsoft.com/entra/workload-id/workload-identity-federation): a [federated identity credential](https://learn.microsoft.com/entra/workload-id/workload-identity-federation-create-trust#github-actions) on an Entra ID app registration (or user-assigned managed identity) trusts the OIDC tokens that GitHub issues to your repository/workflow, and the pipeline exchanges them for Entra ID access tokens — **no client secret or certificate is stored anywhere**, which keeps the entire stack consistent with the keyless design above. Since this IaC creates resources (Foundry accounts, AI Search, Storage, Managed Redis) and RBAC role assignments across them, the simplest grant is **Owner at the subscription scope**.

**Production recommendation 2 — JIT access for developers/operators via PIM**: humans who occasionally need direct Foundry access (troubleshooting, playground) should not hold standing assignments. Use Microsoft Entra Privileged Identity Management (PIM) to grant **eligible** access that must be activated just-in-time.

> **Note**: PIM eligible assignments are for users (and groups of users) only — per the official docs, *"you can't create eligible role assignments for applications, service principals, or managed identities because they can't perform the activation steps."* The CI/CD service principal above is always an **active** (standing) assignment; PIM applies to the human operators, not the pipeline identity.

Two options exist for the human side:

| | [PIM for Azure resource roles](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-resource-roles-activate-your-roles) | [PIM for Groups](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/concept-pim-for-groups) |
|---|---|---|
| What is activated | The Azure RBAC role assignment itself (e.g., Foundry User at project scope) | Membership of a security group that holds the role assignments |
| Activation granularity | Per role × per scope | **One activation covers everything granted to the group** |
| Revocation on deactivation | Assignment removed within seconds; Azure RBAC evaluates the current assignment store on every request, so access ends almost immediately | Membership removed within seconds, **but see the token-caching caveat below** |
| License | Microsoft Entra ID P2 / Governance | Microsoft Entra ID P2 / Governance |

**Recommendation: PIM for Groups.** A single ops group can bundle the Foundry User roles from this repository *and* the `Mcp.Invoke` App Role from [apim-mcp-oauth](https://github.com/apc-n-orita/apim-mcp-oauth) (App Roles are assignable to groups), so one activation opens the whole hands-on estate — and one expiration closes it.

> **Caveat — group-based access can outlive deactivation.** Group membership is carried **as claims inside the access token**, not evaluated live like a direct RBAC role assignment. Per the official docs, *"if application previously cached the fact that user... is a member of the group — when [deactivation] happens, the user may still get access"* ([PIM for Groups](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/groups-activate-roles)). In practice this means a token issued during the activation window keeps its group claim — and therefore keeps granting access — **until that token itself expires** (typically up to ~1 hour). Direct role-assignment PIM doesn't have this gap, because Azure RBAC re-checks the live assignment store on every request rather than relying on a claim baked into the token. If near-instant revocation matters more than activation convenience, prefer PIM for Azure resource roles or keep group activation windows short.

## Enhanced Security

- By combining with **Entra ID Conditional Access**, multi-layered security policies can be applied based on device state, network location, and sign-in risk. Token issuance for the `a2a-agent` application (`api://{a2a-oauth-app-id}`) can be gated by Conditional Access before the APIM policy ever sees the request — authorization then happens at two independent layers (token issuance conditions + App Role check).
- For **Agent Identities** (each Foundry agent in this setup receives its own Entra ID identity and blueprint), applying policies at the blueprint level enables bulk protection of all agents of the same type.

---

[Back to README](./README.md)
