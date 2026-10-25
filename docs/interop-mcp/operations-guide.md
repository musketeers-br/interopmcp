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
  'iris session IRIS < /home/irisowner/dev/bootstrap-demo.script'
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

## 3. Approval workflow (critical tools)

`critical` tools never execute on the agent's call. The call creates an invocation in
`pending-approval` plus an approval request; a human operator decides:

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
"InteropMCP": { "type": "remote", "url": "http://localhost:8080/mcp/interopmcp", "enabled": true }
```

MCP servers load at session start — **restart opencode** after container rebuilds to
refresh the tool list. Tool names are prefixed by the bridge (`mcp_interopmcp_PayLookup`, ...).
Both `mcp-http` and `InteropMCP` servers in `opencode.json` reach the same bridge; the
bridge aggregates discovered tools and routes by name prefix, so the same gateway tools may
appear under either server.
