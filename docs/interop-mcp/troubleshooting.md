# Troubleshooting — IRIS InteropMCP

Runbook: symptom → diagnosis → fix, plus the ObjectScript/UDL dialect rules of this build
(IRIS 2026.3 AI) and ready-to-run diagnostic queries.

## 1. Symptom runbook

### `tools/list` returns nothing / misses tools

| Check | How |
|-------|-----|
| Production running? | `Write ##class(Ens.Director).IsProductionRunning("br.musketeers.InteropMCP.Demo.Production")` — if 0, `Do ##class(Ens.Director).StartProduction("br.musketeers.InteropMCP.Demo.Production")` (or re-run the bootstrap) |
| Catalog built? | `Write ##class(br.musketeers.InteropMCP.Health).GetStatus().%ToJSON()` → `catalogSize` |
| Services annotated? | Class parameters `AIGATEWAY`/`AIGATEWAYDESC`/`REQUESTCLASS` present on the BS classes |
| Build errors? | Look for `registry`-component entries in `^InteropMCP.LogD`; duplicate tool names fail the build naming both services |
| Bridge discovery cached? | Restart the bridge (the launcher supervisor does this; manual: `pkill -f iris-mcp-server` inside the container, then re-run the launcher start line) |

### Tool call returns `"0 ⟨binary bytes⟩..."` (serialized object garbage)

A `%Status` **error** object serialized raw. Decode it in the IRIS terminal:

```objectscript
Set sc = ...   // reproduce the failing call
Write $SYSTEM.Status.GetErrorText(sc)
```

Historic root cause on this build: `%String` properties default to `MAXLEN = 50` in
persistent classes — JSON payloads overflowed (`ERROR #7201`). All gateway stores now use
explicit `MAXLEN`s; if you add new `%String` properties, **always set `MAXLEN`**.

### `<Ens>ErrBusinessDispatchNameNotRegistered`

`Ens.Director.CreateBusinessService` expects the **configuration item name**
(e.g. `PayLookupBS`), not the class name. The catalog stores `serviceName = item.Name` —
make sure the BS is an enabled item of the running production.

### `<INVALID OREF>` when opening records by property

`%OpenId` opens by **row ID**, not by a unique-indexed property (like `InvocationId` or
`ApprovalId`). Gateway stores resolve the row first:

```objectscript
Set rid = ""
&sql(SELECT ID INTO :rid FROM br.musketeers.InteropMCP.Invocations WHERE InvocationId = :pId)
Set inv = ..%OpenId(rid)
```

### First `tools/call` after a bridge restart fails with `WgProto ... Broken pipe`

Transitory connection-pool warm-up on `iris-mcp-server`. Retry on the same or a new
session — subsequent calls are stable. The launcher supervisor keeps the bridge alive.

### Bootstrap did not run / production stopped after container recreation

The launcher supervises the bridge, but the first bootstrap needs IRIS fully started (a
session launched too early prints `Sign-on inhibited`). Re-run the idempotent bootstrap:

```bash
docker exec -i ai-hub-dev-template-iris-1 sh -c \
  'iris session IRIS < /home/irisowner/dev/bootstrap-demo.script'
```

Build-time provisioning (web apps + catalog + `Autostart`) is baked into the image, so a
fresh container autostarts the production; only bridge hiccups should need the step above.

### `<CLASS NOT FOUND>` / tools missing after editing gateway classes

Classes compile on save in the dev loop via `iris_compile`, but the **running bridge
discovery** may be stale: restart `iris-mcp-server` after regenerating the tools class.
For a clean state, rebuild: `docker compose up -d --build`.

### `Production not found` / `Invalid Production`

Production registration uses the **full class name** (`br.musketeers.InteropMCP.Demo.Production`), and the
production XData block **must** be named `ProductionDefinition` (not `Production`).

## 2. UDL / ObjectScript dialect rules (IRIS 2026.3 AI build)

Rules learned the hard way — apply to all gateway code:

| Rule | Wrong | Right |
|------|-------|-------|
| No inline JSON object literals | `Set x = {"a": 1}` | `Set x = ##class(%DynamicObject).%New()` `Do x.%Set("a", 1)` |
| No `{%DynamicObject}` form | `{%DynamicObject}.%FromJSON(raw)` | `##class(%DynamicObject).%FromJSON(raw)` |
| No `$ZUUID` | `$ZUUID()` | `$SYSTEM.Util.CreateGUID()` |
| No `$Uppercase` / avoid `$Justify` nesting | `$Justify($Uppercase(s),5)` | `$ZConvert(s, "U")` |
| Logical OR is `!`, not `Or` | `If a = 1 Or b = 2` | `If (a = 1) ! (b = 2)` |
| No `$IsData` | `$IsData(x(y))` | `$Data(x(y))` |
| `##class()#Param` invalid in expressions | `##class(C)#Param` | `..#Param` (inside the class) or pass as literal |
| `##class(var)` invalid | `##class(requestClass).%New()` | `$CLASSMETHOD(requestClass, "%New")` |
| `Quit <arg>` only in one-line `If` (never inside `{}` blocks) | `If x { Do ... Quit sc }` | `If x Quit sc` (one-liner) or nested `If/Else` |
| `&sql(...)` OK in class methods | — | Use embedded SQL for index lookups |
| List collections: no `$Order`/name-`GetAt` | `cd.Parameters.GetAt("NAME")` | `For i = 1:1:cd.Parameters.Count()` + `GetAt(i)` + compare `.Name` |
| `%Dictionary.ParameterDefinition` value column | `p.Value` | `p.Default` (unquoted text) |
| `%DynamicArray` iterator | `iter.%GetNext(.name, .val)` gives **index** in first arg | `iter.%GetNext(.idx, .entry)` → use `entry.name` |
| Persistent `%String` default MAXLEN = 50 | `Property P As %String;` | `Property P As %String(MAXLEN = 10000);` |
| Dynamic property set | — | `Set $PROPERTY(oref, propName) = value` |
| Member names | `get_invocation_status`, `{...}` braces in methods confuse parse | CamelCase members; braces balanced (`#5559` otherwise) |
| `Ens.Production` XData block name | `XData Production` | `XData ProductionDefinition` |
| `$$$Trace` undefined in non-interop classes | `Do $$$Trace(...)` in `%RegisteredObject` | Persist to a global; console via `Write` |
| `$XECUTE` must end in an expression | `$XECUTE("Set x = 1")` | `$XECUTE("##class(C).%New()")` — or prefer `$CLASSMETHOD` |
| Class braces must balance (incl. generated files) | missing final `}` → `#5559` | always close the class block |

Dev-loop tip: compile single classes with full error display (the Atelier-based
`iris_compile` tool prints errors; the `ck-d` qualifier **suppresses** them).

## 3. Diagnostic queries

```sql
-- Native trace: headers produced by tool calls (BS→BP→BO flow)
SELECT ID, TimeCreated, SourceConfigName, MessageBodyClassName
FROM Ens.MessageHeader ORDER BY TimeCreated DESC

-- Gateway audit: invocation lifecycle
SELECT ToolName, AgentIdentity, Status, StartedAt, EndedAt, ErrorMessage
FROM br.musketeers.InteropMCP.Invocations ORDER BY StartedAt DESC

-- Pending approvals
SELECT ApprovalId, InvocationId, RequestedAt FROM br.musketeers.InteropMCP.Approvals
WHERE Decision = 'pending'

-- Catalog (compiled annotations)
SELECT Name, Parent, "Default" FROM %Dictionary.ParameterDefinition
WHERE Name LIKE 'AIGATEWAY%'
```

## 4. Globals map

| Global | Owner | Content |
|--------|-------|---------|
| `^InteropMCP.Catalog` | Registry | Published tool definitions (JSON per tool) |
| `^InteropMCP.InvocationsD` | Invocations | Invocation rows (audit backbone) |
| `^InteropMCP.ApprovalsD` | Approvals | Approval requests/decisions |
| `^InteropMCP.LogD` | Log | Leveled log lines (id-incremented) |
| `^InteropMCP.Demo.AuditD` | AuditOperation | Per-call request payload dumps (native audit chain) |

## 5. Endpoints and ports

| Port | Service |
|------|---------|
| `1972` | IRIS superserver (used by `iris-mcp-server`) |
| `52773` | IRIS web server (Management Portal; web apps `/mcp/interopmcp`, `/mcp/sample`) |
| `8080` | `iris-mcp-server` bridge (MCP clients connect here) |

Bridge config: `config_http.toml` — declares the exposed endpoints (`/mcp/sample`,
`/mcp/interopmcp`) and `allow_anonymous = true` (dev). For production deployments, provision
with `br.musketeers.InteropMCP.Setup.Run("prod")` and restrict the bridge per your network policy.
