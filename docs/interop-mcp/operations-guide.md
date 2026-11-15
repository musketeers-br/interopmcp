# Operations Guide — IRIS InteropMCP

Day-2 operations: deployment, onboarding new Business Services, approval workflow,
monitoring, testing and IDE integration.

## 1. Deploy and lifecycle

```bash
docker compose up -d --build     # build + start (provisions everything)
docker compose down              # stop and remove
docker compose logs iris         # IRIS container logs
docker logs ai-hub-mcp-launcher  # bootstrap + bridge supervision logs
```

What `up --build` guarantees (idempotent at every level):

| Step | Where | Result |
|------|-------|--------|
| IPM module install | `iris.script` → `zpm load` | `br.musketeers.InteropMCP.PKG` compiled (gateway only) |
| Demo compile | `iris.script` → `LoadDir src/br/musketeers/InteropMCP/Demo` | Demo production + BS/BP/BO classes |
| Bootstrap | `iris.script` → `InteropMCPSetup.Run()` + `br.musketeers.InteropMCP.Setup.Run("dev")` | Web apps `/mcp/sample` + `/mcp/interopmcp`, production started, tool catalog generated |
| Autostart | `iris.script` → `prod.Autostart = 1` | Production auto-starts with IRIS |
| Bridge | `mcp-launcher` | `iris-mcp-server` started and supervised (30 s check) |

Manual (re)bootstrap — safe to re-run at any time:

```bash
docker exec -i ai-hub-dev-template-iris-1 sh -c \
  'iris session IRIS < /home/irisowner/dev/bootstrap-gateway.script'
```

Teardown:

```objectscript
Do ##class(br.musketeers.InteropMCP.Setup).TearDown()   // removes the /mcp/interopmcp web app
```

## 2. Onboarding a new Business Service

Any Business Service of a running production can be exposed by annotating its class and
rebuilding the catalog. Annotations are **class parameters**:

| Parameter | Values | Required | Purpose |
|-----------|--------|----------|---------|
| `AIGATEWAY` | `readonly` \| `write` \| `critical` | yes | Guardrail classification |
| `AIGATEWAYDESC` | free text | recommended | Agent-facing tool description |
| `REQUESTCLASS` | `Package.MyRequest` | recommended | `Ens.Request` subclass the tool accepts; fallback derives `<BS-without-BS-suffix>Request` |
| `AIGATEWAYASYNC` | `1` | no | Mark the tool as long-running (returns a processing reference) |
| `AIGATEWAYWAIT` | seconds | no | Per-tool wait-window override (default 30) |

Example:

```objectscript
Class MyApp.InvoiceIssueBS Extends Ens.BusinessService
{
    Parameter AIGATEWAY = "write";
    Parameter AIGATEWAYDESC = "Issue an invoice for an order";
    Parameter REQUESTCLASS = "MyApp.InvoiceIssueRequest";

    Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
    {
        // business logic; optionally forward to a BP/BO for native trace
        Quit $$$OK
    }
}
```

Publish it:

```objectscript
zn "IRISAPP"
Do ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("Your.ProductionName")
```

Rules the registry enforces:

- **Tool name** = configuration item name minus a trailing `BS` (`PayLookupBS` → `PayLookup`).
- **Duplicate tool names fail the build** with an error naming both services — an ambiguous
  catalog is never published.
- **Member naming must be CamelCase** — the UDL parser of this build rejects
  lowercase/underscore member names (`#5559`). Item names like `PayLookupBS` are fine;
  `pay_lookup` is not.
- Unannotated services are never exposed. `Registry.SetEnabled(tool, 0)` removes a tool
  from the published catalog without recompiling anything.

Downstream trace (recommended): within `OnProcessInput`, send the request to a Business
Process/Operation so the call produces native `Ens.MessageHeader` rows and a Visual Trace
chain — as the bundled demo does with `br.musketeers.InteropMCP.Demo.AuditProcess` → `br.musketeers.InteropMCP.Demo.AuditOperation`.

### A service that runs longer than the response window

`Parameter AIGATEWAYASYNC = "1"` marks a service as long-running: the gateway answers the
caller with a processing reference and the run continues in the background.

**The service then owns the outcome of its own invocation.** The gateway records the
invocation as `executing` and stops there — it cannot know how a background run ended.
A service that never reports its outcome leaves the invocation `executing` forever, and
the caller polling `GetInvocationStatus` waits for an answer that never comes.

The service reports it through the request's `GatewayInvocationId`:

```objectscript
Class MyApp.LongRunBS Extends Ens.BusinessService
{
    Parameter AIGATEWAY = "readonly";
    Parameter AIGATEWAYASYNC = "1";
    Parameter REQUESTCLASS = "MyApp.LongRunRequest";

    Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
    {
        // ... the long work ...
        Set tInvocationId = pRequest.GatewayInvocationId
        If tInvocationId = "" Quit $$$ERROR($$$GeneralError,"no invocation id to report to")

        Set tResult = ##class(br.musketeers.InteropMCP.Invocations).GetById(tInvocationId)
        // ... build the result object ...
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(tInvocationId, "completed", tResult, "", 0)
        Quit $$$OK
    }
}
```

`GatewayInvocationId` is an internal field: it is added to the request class by the
operator, and it is **not** part of the published tool's input schema — a caller cannot
see it, and cannot forge it.

The bundled demo carries the reference implementation in
`br.musketeers.InteropMCP.Demo.BatchRunBS` → `br.musketeers.InteropMCP.Demo.BatchRunRequest`.

## 3. Approval workflow (critical tools)

`critical` tools never execute on the agent's call. The call creates an invocation in
`pending-approval` plus an approval request; a human operator decides.

**Primary UI: IRIS User Portal Workflow inbox** (recommended for operators)

1. Open the DeepSee User Portal Workflow:
   ```
   http://localhost:52773/csp/irisapp/_DeepSee.UserPortal.Workflow.zen
   ```
2. Login as a user with the `Operators` role.
3. In the inbox, select the task with Subject `Approval: <ApprovalId>` (status `Unassigned`).
4. Click **Accept** to take ownership — the portal then shows **Relinquish** / **Approve** / **Reject**.
5. Click **Approve** or **Reject** and confirm.

The portal dispatches `EnsLib.Workflow.Engine.%ProcessAction` → `TaskResponse.OnAction` on the stored task class. InteropMCP provides `br.musketeers.InteropMCP.WorkflowTaskResponse`, whose `OnAction` records the decision in `Approvals` and **closes the task locally — no deferred response is needed** because the approval request was created outside a production message flow. This avoids `Ens.ErrProductionMismatchInDeferredResponse` (see `docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md` and `docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE_ANALYSIS.md`).

**Terminal fallback (headless operator / automation)**

```objectscript
zn "IRISAPP"
Set pend = ""
Do ##class(br.musketeers.InteropMCP.Approvals).ListPending(.pend)
Write pend.%ToJSON()          // {"pending":["<approvalId>", ...]}

Do ##class(br.musketeers.InteropMCP.Approvals).Approve("<approvalId>", "operator1")
// or
Do ##class(br.musketeers.InteropMCP.Approvals).Reject("<approvalId>", "operator1", "policy X")
// Cancel is an alias of Reject (stale items; never auto-expires)
```

This terminal path also **bypasses `Ens.Host.SendDeferredResponse` entirely** and is not subject to the deferred-response mismatch error.

The calling agent observes the outcome via `GetInvocationStatus` (poll) or the admin API.
Every decision is logged (`br.musketeers.InteropMCP.Log`, `approval` component). There is **no automatic
expiry**: pending items remain until decided or explicitly cancelled.

## 4. Monitoring and inspection

### Health snapshot

```objectscript
zn "IRISAPP"
Write ##class(br.musketeers.InteropMCP.Health).GetStatus().%ToJSON()
// {"production":"configured","productionName":"br.musketeers.InteropMCP.Demo.Production",
//  "catalogSize":4,"pendingApprovals":0,"lastInvocationAt":"","logLevel":"info"}
```

### Gateway logs

`br.musketeers.InteropMCP.Log` writes every component event (`registry`, `guardrail`, `invoker`,
`approval`, `mcp`) with levels `debug|info|warn|error` to the console **and** the persistent
global `^InteropMCP.LogD`:

```objectscript
// tail the log
Set id = "" For { Set id = $Order(^InteropMCP.LogD(id)) If id = "" Quit Write !, ^InteropMCP.LogD(id) }
```

SQL alternative: the invocation store doubles as an audit table.

```sql
SELECT ToolName, AgentIdentity, Status, StartedAt, EndedAt
FROM br.musketeers.InteropMCP.Invocations ORDER BY StartedAt DESC
SELECT ApprovalId, InvocationId, Decision, Approver, DecidedAt, Reason
FROM br.musketeers.InteropMCP.Approvals WHERE Decision = 'pending'
```

### Native production trace

For every AI-triggered tool call, check the production itself (nothing was written by the
gateway — the flow was produced by the BS→BP→BO components):

- **Portal** → Interoperability → *Message history*: expect ~4 `Ens.MessageHeader` rows per
  call (`<Tool>BS` → `AuditProcess` → `AuditOperation` + responses) with the request body
  stored; *Visual Trace* shows the 3 hops with timings.
- **Terminal/global**: `^InteropMCP.Demo.AuditD` holds one line per audited request:
  `<RequestClass>|<timestamp>|<json payload>`.

## 5. Testing

```text
# %UnitTest suites (tests/br/musketeers/InteropMCP) — from the IRIS terminal
zn "IRISAPP"
Set sc = ##class(%UnitTest.Manager).RunTest("tests/br/musketeers/InteropMCP", "/noload")
```

External protocol smoke test (list → call → poll):

```bash
python3 -m pip install -r python/smoke/requirements.txt
python3 python/smoke/mcp_client.py --endpoint http://localhost:8080/mcp/interopmcp \
    --tool PayLookup --params '{"OrderId":"88201","CustomerId":"C-1"}'
```

Coverage expectation per the project quality gate: ≥ 90 % line coverage on the
`br.musketeers.InteropMCP` package.

## 6. IDE integration (opencode)

`opencode.json` ships with the gateway pre-configured:

```json
"InteropMCP": {
  "type": "remote",
  "url": "http://localhost:8080/mcp/interopmcp",
  "headers": { "Authorization": "{env:INTEROPMCP_BASIC}" },
  "enabled": true
}
```

`INTEROPMCP_BASIC` is interpolated from the environment of the **process that launches
opencode**. Persist it in `~/.bashrc` (a transient `export` is lost on restart); see
`authentication.md` §13. MCP servers load at session start — **restart opencode** after
container rebuilds to refresh the tool list. Tool names are prefixed by the bridge
(`mcp_interopmcp_PayLookup`, ...).
Both `mcp-http` and `InteropMCP` servers in `opencode.json` reach the same bridge; the
bridge aggregates discovered tools and routes by name prefix, so the same gateway tools may
appear under either server.

## 7. Attaching an agent to a production

A production can carry an **agent**: an AI Hub agent that operates the
production's own capabilities. The agent is attached with a custom inbound
adapter, `br.musketeers.InteropMCP.Agent.Adapter`, and it is published on the
MCP endpoint beside the production's individual capabilities.

### What the operator does

1. **Add a business host to the production** whose adapter is the agent's
   adapter. The host is the production's entry point for the agent; the
   gateway calls it the way it calls every other business service.

   ```xml
   <Item Name="MyAgentHost" ClassName="my.production.AgentHost" PoolSize="5" Enabled="true">
     <Setting Target="Adapter" Name="Purpose">Assesses a supplier and says whether the order may proceed.</Setting>
     <Setting Target="Adapter" Name="Prompt">You are a risk analyst operating this production. ...</Setting>
     <Setting Target="Adapter" Name="Model">nvidia/nemotron-3.5-lightning-30b-a3b</Setting>
     <Setting Target="Adapter" Name="ProviderConfig">{"model_provider":"nim","base_url":"https://integrate.api.nvidia.com/v1","api_key":"@{env:NVIDIA_API_KEY}"}</Setting>
   </Item>
   ```

2. **Rebuild the catalogue** so the agent is published:

   ```objectscript
   zn "IRISAPP"
   do ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("my.production.Production")
   ```

3. **Restart the MCP server** (`iris-mcp-server`), which loads the published
   surface at start-up: a catalogue rebuild on its own does not change what
   callers see.

### The settings, and what each one means

| Setting | Meaning |
|---|---|
| `Prompt` | The agent's document: the plain-language rules that govern it. **Required** — an agent with no document has no rules, and is not published. |
| `Purpose` | One sentence, published as the agent tool's description so a caller can discover what it is for. |
| `Model` | The model the agent uses. Empty means the platform default. |
| `ProviderConfig` | The provider's settings as JSON. A credential is **referenced**, never written: `@{env:NAME}` or the governed store's own reference. A configuration that carries a credential value is rejected and the agent is not published. |
| `AgentTools` | The published capabilities the agent may reach, comma separated. Empty means every published capability of the production. The agent's own entry is never in its scope, so the agent cannot call itself. |
| `MaxIterations` | The effort bound for one run. A bound that is not positive bounds nothing and is rejected. |
| `Timeout` | The elapsed-time bound for one run, in seconds. The bound is carried into the agent's own session, so it bounds the run itself and not only the gateway's wait for it. A run that reaches the bound ends with a diagnosable outcome instead of holding the worker. |
| `KnowledgeBase` | The indexed knowledge the agent retrieves. Empty means no retrieval. |

The document is **hot**: the settings are read from the production at the start
of every run, so a revision takes effect on the next run, with no redeployment
of the production's components.

### What the operator does **not** have to do

- annotate a business service class with anything agent-related;
- modify an existing component of the production;
- rewrite an integration;
- provision a second credential for a retrieval;
- deploy a separate service for the agent.

### Sizing the worker pool

**A business service occupies its worker for the whole of `ProcessInput`**, and
an agent run holds its worker for the whole run. A production whose pools hold
one call at a time therefore has no worker left for the next caller while the
agent runs, and the endpoint stops serving the production's own capabilities.
Give every item of a production that carries an agent a pool of more than one
worker (`PoolSize="5"` in the demonstration).

### How a run is delivered

An agent run is longer than the response window of the path between the MCP
bridge and IRIS, so the agent tool answers the caller as soon as the run has
started:

```json
{ "_status": "pending", "invocationId": "<guid>",
  "message": "The run has started. Use GetInvocationStatus with invocationId to collect the result." }
```

The run continues in the background; the answer is collected with
`GetInvocationStatus` and that invocation id, in the same envelope every other
invocation returns. The run is recorded either way — a run that finishes after
the caller has given up still leaves its answer in the invocation record.

**The host reports the outcome of its own run.** The gateway records the
invocation as `executing` when it starts it, and it cannot know how a background
run ended. The host — the business service the gateway calls — reports it
through the request's `GatewayInvocationId`, in the same way any asynchronous
service reports it (see *A service that runs longer than the response window* in
section 2). A host that does not report leaves the invocation `executing`
forever, and the caller waits for an answer that never comes.

The published agent's own run does this for you: `br.musketeers.InteropMCP.Agent.Host`
records the run's outcome, so an operator attaching an agent to a production
writes a host that does the same.

### When the agent is not published

A misconfigured agent is not published at all: the gateway does not offer a
capability it cannot serve, and the reason is written to the gateway log
(`registry` component, `warning`):

```
The agent was not published: its configuration is not usable.
```

The reasons are the ones the settings table names: no document, a bound that
is not positive, a credential written in the configuration.
