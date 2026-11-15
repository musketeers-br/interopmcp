# Phase 0: Research — AI Agent Adapter

Feature: `004-ai-agent-adapter` | Date: 2026-11-12

Every decision below was checked against the running instance
(IRIS 2027.1.0AI, build 109U, namespace IRISAPP) rather than assumed.

---

## D-01: The agent executes inside the production, driven by the adapter

**Decision**: The custom adapter is an `Ens.InboundAdapter` that owns the agent's
configuration. The agent runs inside the production it is attached to, in the
production's own namespace and runtime.

**Rationale**: The user chose this explicitly ("o agente runs inside the
production, cause it's implemented by the custom inbound adapter (mandatory)").
It also keeps the agent under the production's lifecycle, routing, and trace, so
an agent-initiated action is indistinguishable from a production-native one in
the Visual Trace.

**Alternatives considered**:
- *Agent hosted by the MCP gateway* — rejected: the production would no longer
  contain the agent, and the adapter would shrink to a metadata carrier.
- *Both production and gateway* — rejected for the first release: two
  execution paths to build, test, and govern.

---

## D-02: The gateway reaches the agent through a Business Service

**Decision**: The production gains a Business Service (the agent's *host*) that
the existing `Invoker` reaches by config item name, exactly as it reaches every
other business service. The custom inbound adapter is the external-trigger face
of the same agent and the owner of its configuration.

**Rationale**: `Invoker.Invoke` (`src/br/musketeers/InteropMCP/Invoker.cls:48`)
does exactly one thing:

```objectscript
Set sc = ##class(Ens.Director).CreateBusinessService(serviceName, .bs)
Set sc = bs.ProcessInput(request, .response)
```

`serviceName` is the **production config item name**. If the agent's entry
point is a Business Service, that path works **unchanged** — the guardrail, the
invocation record, the approval hold, and the audit trail are all reused
verbatim, with no new execution backend and no second audit plane.

This is also the platform's own shape. The AI Hub ships
`EnsLib.AI.Agent.PassthroughOperation` (an `Ens.BusinessOperation`) whose
`Parameter ADAPTER = "EnsLib.AI.Agent.OutboundAdapter"` — a business service
reaching an adapter. The mirror image for the inbound direction is what this
feature builds.

**Alternatives considered**:
- *Extend `Invoker` with an agent branch* — rejected: unnecessary. A Business
  Service entry point needs no new execution path.
- *Have the gateway call the inbound adapter directly* — rejected:
  `Ens.Director.CreateBusinessService` only creates business services; an
  inbound adapter has no `ProcessInput(request, response)` to call.

**Verified**: `Ens.InboundAdapter` exposes `BusinessHost As Ens.BusinessService`
and its default `OnTask()` delegates with
`..BusinessHost.ProcessInput($$$NULLOREF)`. The adapter therefore feeds the
business host, and the same business host is what the gateway calls.

---

## D-03: The adapter owns the configuration; the host resolves it

**Decision**: The agent's document (prompt), model, provider reference,
reachable capability scope, effort and time limits, and knowledge binding are
**properties of the adapter**. The Business Service resolves them from the
production's configuration at run time and builds the agent.

**Rationale**: The user chose this ("o adapter é o dono da configuração … e o
AgentBS apenas injeta o goal"), and it is the only arrangement in which the
same configuration genuinely serves both callers: an external trigger reaching
the adapter and an MCP caller reaching the host get the same agent, because
both end up resolving the same adapter settings.

**Verified**: production items expose their settings as a dynamic object.
Reading the running demonstration production's items:

```
1) PayLookupBS     | br.musketeers.InteropMCP.Demo.PayLookupBS | enabled=1 | settings=<none>
…
7) AuditOperation  | br.musketeers.InteropMCP.Demo.AuditOperation | enabled=1 | settings=<none>
```

`prod.Items.GetAt(i)` yields `Name`, `ClassName`, `Enabled`, and `Settings`;
an item with configured settings carries them there.

**Alternatives considered**:
- *Configuration on the Business Service, adapter as a thin shell* — rejected:
  two places to configure for one agent, and the component the operator
  configures would not be the component the feature is named after.
- *A dedicated configuration global* — rejected: it moves the agent's
  configuration out of the production, where an operator expects to find it.

**Open item**: with one adapter per production in the first release, the host
resolves "the enabled item whose class is the agent adapter class". Supporting
several agents in one production would need an explicit item reference
instead; recorded as a documented extension point, not a first-release
requirement.

---

## D-04: The agent reaches the production's capabilities through the published tools

**Decision**: The agent is given the production's **published tools** as its
tool surface, so every capability the agent calls goes through
`Guardrails.Check` and `Invoker.Invoke` exactly as a direct call would.

**Rationale**: This is what makes the governance story free rather than
duplicated. The generated tool class (`Registry.GenerateToolsClass`,
`src/br/musketeers/InteropMCP/Registry.cls:134-208`) emits, per capability:

```objectscript
Set sc = ##class(...Guardrails).Check("RiskCheck", params, ..., .proceed, .holdId, .invId, .gsc)
If 'proceed { ... _status = "held" ... }
Set sc = ##class(...Invoker).Invoke("RiskCheck", params, ..., .invId, .resp)
```

So when the agent calls `RiskCheck`, the read-only / write / critical
classification and the human-approval hold are applied by the same code, and
the call produces its own `Invocations` row. No second governance path, no
second audit plane — which is also what the constitution's dual-plane rule and
the project's "the gateway only fires business services" rule require.

**Alternatives considered**:
- *Give the agent its own tool classes that call the business services
  directly* — rejected: it would bypass the guardrail, the invocation record,
  and the approval gate, which is precisely what FR-016 and FR-055 forbid.
- *Let the agent call only the capabilities it was told to* — rejected as the
  primary mechanism: the model already selects tools; the scope is a
  restriction applied on top, not a substitute for selection.

---

## D-05: The reachable scope is materialised when the catalogue is built

**Decision**: The agent's reachable capability scope (FR-004) is applied when
`Registry.BuildCatalog` builds the catalogue, in the same pass that generates
the tool class today.

**Rationale**: The AI Hub's tool set surface is declarative: `<Include
Class="...">`, `<Exclude Tool="...">`, `<Exclude Match="...">` (see
`skills/ai-hub-toolsets/references/toolsets-reference.md`). A per-adapter
restriction that changes without a rebuild is not expressible that way, and
the alternative — building a tool manager per run from individual tool
instances — needs per-method tool instances the platform does not obviously
offer.

Splitting the two change frequencies is therefore deliberate: **the agent's
document is hot** (FR-009 — a revision takes effect on the next run), while
**the scope takes effect on the next catalogue build**. Nothing in the spec
requires the scope to be hot.

**Alternatives considered**:
- *Runtime tool manager built per run* — still viable, and is the natural
  route to a hot scope. Recorded as the extension point for finer-grained
  authority (FR-019).
- *Enforce the scope at call time in the guardrail* — rejected: it would put
  an agent-specific rule into the shared guardrail, which every direct caller
  also passes through.

---

## D-06: The run is recorded in the existing invocation store

**Decision**: An agent run is an `Invocations` row — the invocation of the
agent tool itself — carrying the run's detail in its result envelope. The
agent's individual capability calls are, as today, separate `Invocations` rows.

**Rationale**: The gateway already has exactly one audit store for everything
it fires. A run record is therefore not a new entity but the existing one,
extended: the goal is the invocation's parameters, the identity is
`AgentIdentity`, the outcome is `Status`, the timing is `StartedAt`/`EndedAt`,
and the capabilities used and retrievals performed travel in the result
envelope alongside the answer. The child invocations are already separate rows
that a reader can correlate.

**Alternatives considered**:
- *A new `AgentRuns` persistent class* — rejected: a second audit entity for
  the same event, with the duplication and the reconciliation that follows.
- *No record of the capabilities used* — rejected: FR-059 requires it.

---

## D-07: Embedded Python is limited to reading documents

**Decision**: The application's Embedded-Python component reads supplier
invoice documents. The production's own calls to the external company
registry stay in the native language.

**Rationale**: Two earlier proposals were rejected after investigation. The
platform's native language handles string manipulation, file reading, and
arithmetic comfortably, so a component doing those would demonstrate nothing.
It also provides a complete HTTP client natively, so routing the registry
lookup through Python would demonstrate nothing either.

What the native language does **not** provide is reading text and structure
out of a document. A scan of the entire namespace's class list found only
`ChartPDF`, `MDXPDF`, and `WorksheetPDF` — report *generators*, not readers.

**Verified**: the AI Hub's Python runtime in this instance is 3.12.3, with
`requests`, `httpx`, and `cryptography` already installed. `pypdf` installs
cleanly and extracts the demonstration fixtures exactly as intended:

```
PDF-READ-OK | pages= 1 | text= 'Invoice INV-2026-118 CNPJ 12.345.678/0001-95 Amount 412.75'
```

**Verified**: the platform's native HTTP client in this build is
`%Net.HttpRequest` — used by the project's own `iris.script:9-13` — and it
performs a successful HTTPS GET from ObjectScript. `%SYSTEM.Net.HTTPRequest`
does **not** exist in this build; an implementation that assumes it will fail
at compile time.

**Constitution**: the split also matches the constitution, which assigns IRIS
business logic to the native language and services and integration to Python.

---

## D-08: Vector search grounds the agent in the production's own written rules

**Decision**: The retrieved corpus is the production's **written policies** —
the rules that govern the agent's decisions. The agent's own document says to
apply the production's policies; it does not restate them.

**Rationale**: Grounding over a corpus of documentation the demonstration does
not otherwise have would demonstrate nothing — there would be no reason for
the retrieval to exist. The rules are exactly what the agent has to find, and
a question that shares no literal wording with the rule it needs is the case
that only matching by meaning serves.

**Verified**: the whole stack works on this instance — local embeddings, the
vector store, indexing with deterministic chunk identifiers and metadata, and
retrieval exposed as a tool:

```
vs.Build sc=1 | kb.Build sc=1 | AddDocuments chunks=3 | AddToManager sc=1
Q1 (score 0.599) -> policy.md  "A politica de risco exige aprovacao humana
                                  quando o registro cadastral da empresa esta
                                  cancelado ou BAIXADA"
```

Two queries with **no literal word in common** with the passage they retrieve:

| Query | Retrieved | Score |
|---|---|---|
| "fornecedor de **material** de **construcao**" | "MATERIAIS DE **CONSTRUÇÃO** ALFA" | 0.599 |
| "quem **transporta mercadoria**" | "DORIO **TRANSPORTE** E LOGISTICA" | 0.639 |

A keyword search would match neither.

**Also verified**: `FastEmbed` runs **locally** (384 dimensions,
`AllMiniLML6V2`, model already present in the image), so the demonstration
needs no second credential and makes no outbound call to embed or retrieve.

**Alternatives considered**:
- *Semantic routing of goals onto capabilities* — rejected: redundant with the
  model's own tool selection, and explicitly out of scope (FR-038).
- *Retrieval over the audit trail* — rejected: the trail holds structured
  fields, and an exact match on the company identifier is better than a
  similarity match.

---

## D-09: The published surface needs three changes, not a new execution path

**Decision**: Publishing an agent needs, in the gateway:

1. `Registry.BuildCatalog` recognises an agent adapter item and publishes an
   entry for it, pointing at the agent's Business Service config item and at
   the agent request class.
2. The agent request class carries the goal as a property, so `SchemaMapper`
   derives the published input schema with no change.
3. The generated tool for the agent entry is emitted by the existing generator
   like any other tool.
4. `Registry.GenerateToolsClass` emits a `///` docstring for each generated
   method, carrying the catalogue's description.

**Rationale**: `Registry.BuildCatalog` currently discovers items by reading the
`AIGATEWAY` class parameter off the item's class and then deriving the
request class from the item's class name. An adapter is neither a business
service nor a request-bearing class, so it needs a second discovery branch —
but a branch in the catalogue builder, not a new invoker, not a new schema
mapper, and not a new tool dispatcher.

**Verified**: the guardrail, the invoker, the tool set, the generated-tools
class, and the invocation store all work unchanged for an agent entry whose
`serviceName` is a business service config item and whose `requestClass` is an
`Ens.Request` subclass with the goal as a property.

**The docstring is not cosmetic.** A tool's published description comes from the
**docstring of its method**. That is why `MetaTools.CreateWorkflowTask` and
`InvocationStatusTools.GetInvocationStatus` are described to callers, and why
**the generated business-capability tools are published with an empty
description today**: the generator emits no docstrings, so the `AIGATEWAYDESC`
annotation never reaches the MCP endpoint. Captured from the running gateway:

```
mcp_interopmcp_RiskCheck   description: "[Remote Service: local_mcp_interopmcp] "
mcp_interopmcp_PayLookup   description: "[Remote Service: local_mcp_interopmcp] "
mcp_interopmcp_MetaTools   description: "[Remote Service: local_mcp_interopmcp] Requests a human-approval workflow ..."
```

Emitting the docstring from the catalogue's description is what makes the
agent's own description discoverable (FR-023), and in the same change it gives
the existing capabilities the descriptions their annotations already carry. It
adds information to the published surface and removes none — which is exactly
what the regression contract allows.

---

## D-10: The MCP server caches the published surface

**Decision**: A catalogue rebuild does not by itself change what the endpoint
publishes. The procedure that makes a catalogue rebuild visible to callers —
restarting the MCP server — MUST be part of the operator's guide and part of
the feature's validation.

**Rationale**: This was found by breaking the catalogue deliberately and
watching the endpoint. The `iris-mcp-server` process loads the tool set when it
starts and keeps the published surface from then on. Rebuilding the catalogue
rewrites the catalogue global and recompiles the generated tool class, but a
running server keeps advertising what it loaded at start-up.

The sequence observed on the running stack:

```
catalogue rebuilt with one tool omitted  ->  catalogue global has 5 entries
                                           ->  endpoint still publishes 7 tools
MCP server restarted                     ->  endpoint publishes 6 tools
```

For the feature this matters twice over. First, an agent that is attached to a
production and published in the catalogue would **not appear to callers** until
the server is restarted — the feature would look broken. Second, and more
importantly for the user's requirement, a catalogue build that accidentally
drops an existing capability would **not be visible** to the endpoint until the
server restarted, which means the regression is invisible exactly when it is
most dangerous.

**Alternatives considered**:
- *Have the gateway signal the server* — rejected for the first release: the
  deployment already supervises the server and restarts it when it is not
  running, so the procedure fits the existing operational model.

---

## D-11: The published surface is protected by an executable contract

**Decision**: The tools published before this feature existed are recorded in
the repository, together with their input schemas, and checked automatically
against the running endpoint.

**Rationale**: The catalogue builder is the path **every** published tool goes
through, so a change that teaches it about agents can break the discovery of
the capabilities that were already served. The failure is silent — the endpoint
simply stops advertising a tool — and it breaks every caller at once.

A baseline was captured from the running gateway before any change
(`python/tests/baselines/mcp-tools.json`), covering the seven tools published
today, with their names and their input schemas. The check enforces three
rules: every baseline tool is still published; every baseline input schema is
exactly what it was; and a description is never removed, only added.

**Verified by deliberately breaking it.** A one-line change to the generator
that omitted one tool from the generated class was compiled into the running
instance, the catalogue was rebuilt, and the server restarted:

```
FAILED test_published_tool_surface_is_preserved
       "these tools were published before the agent adapter and are no longer
        published: ['mcp_interopmcp_PayLookup']"
FAILED test_published_tool_count_does_not_shrink
FAILED test_a_capability_still_executes
       "Tool not found: mcp_interopmcp_PayLookup"
3 failed
```

The change was then reverted, the catalogue rebuilt, the server restarted, and
all three tests passed again. The guard is not a claim; it is a check that has
been seen to fail.

**Alternatives considered**:
- *Assert in the unit tests only* — rejected: the unit tests exercise the
  catalogue builder in isolation; the failure mode that matters is at the
  endpoint, where the surface is assembled from the catalogue, the generated
  class, the tool set, and the server's cache.
- *Compare the whole tool list for equality* — rejected: the agent is expected
  to add a tool, so an equality assertion would have to be edited on every
  feature that publishes something. The contract is "nothing may disappear",
  which is stable.

---

## D-13: The production item is a business host; the adapter is its adapter

**Decision**: The production gains **one** item: a Business Service — the agent's
*host* — whose `ADAPTER` parameter names the custom inbound adapter that carries
the agent's configuration. The adapter's own settings live on that item's
"Adapter" target.

**Rationale**: The first attempt made the inbound adapter a production item in
its own right. The platform refused it, and the refusal is instructive:

```
ERROR <Ens>ErrGeneral: Config Item AgentAdapter cannot run because it has
unknown BusinessType
```

`Ens.Config.Item.BusinessType()` recognises a business service, a business
process and a business operation — and nothing else. An inbound adapter is
none of them. In Ensemble an inbound adapter is referenced **by** a business
host, through that host's `ADAPTER` parameter; the framework creates the
adapter for it. This is the platform's own shape: `EnsLib.HTTP.InboundAdapter`
and its siblings are always referenced from a host, never installed as items.

So the shape is:

```text
production
└── AgentHost   (Ens.BusinessService, Parameter ADAPTER = "...Agent.Adapter")
    ├── Purpose, Prompt, ProviderConfig, ...   <- the adapter's own settings
    └── the custom inbound adapter, created by the framework
```

The agent's published name is the item's name, which keeps the gateway's
naming convention intact: a business service loses its trailing "BS"
(`PayLookupBS` → `PayLookup`), and the agent's host is published as it is
named (`AgentHost`).

**Alternatives considered**:
- *The adapter as a direct production item* — rejected: the platform refuses it.
- *The gateway calling the adapter directly* — rejected: the gateway reaches
  business services by config item name, and an inbound adapter is not one.

## D-14: Three latent defects in the shared path, found and closed

**Decision**: The implementation closed three defects that predate this
feature but that the agent's arrival exposed.

**Rationale**:

1. **The generated tools published no description.** A tool's description is
   taken from the **docstring of its method**, and the generator emitted none.
   The `AIGATEWAYDESC` annotation every business service already carries never
   reached the caller: `mcp_interopmcp_RiskCheck` was published as
   *"[Remote Service: local_mcp_interopmcp] "* — empty. The generator now emits
   the docstring, so the descriptions exist. This is what makes the agent's own
   description discoverable, and it adds information to the published surface
   without removing any.

2. **A failed invocation was never recorded as failed.** The invoker logged the
   error and moved on, leaving the invocation in `received` for ever. It now
   records `failed` with the reason, and the reason reaches the audit record
   because the agent's host throws it rather than returning it: a business host
   that fails does not hand its response back.

3. **`Guardrails.Check` was used as a function but declared no return type.**
   Every generated tool does `Set sc = ...Check(...)`. On the error path the
   method quit without a value, so an unknown tool crashed the caller with
   "Function must return a value" instead of reporting the error. The method now
   declares its return type and returns the status on every path.

**Alternatives considered**:
- *Leaving them for a later iteration* — rejected: the first two make the
  feature's central promise — that a run which cannot complete is reported as
  a failure, never as a clean result — untrue.

## D-15: Platform facts worth keeping

These cost real time to discover and are not in the documentation:

| Fact | Consequence |
|---|---|
| A production's XData requires its items **grouped by type** — services, then processes, then operations. A service placed after a process fails to parse with a misleading "class definition could not be parsed" error. | The agent's item goes in with the services. |
| `%DynamicArray` is **0-based**: `%Get(0)` is the first item and `%Get(%Size())` is out of range with `<INVALID OREF>`. | Index loops start at zero. |
| `$Length` has no delimiter form; `$Pieces` and `$Trim` are SQL, not ObjectScript; `$ZTRIM` does not exist. | Splitting uses `$Find` and `$Extract`. |
| `$$$StatusDisplayString` does not exist in this build, and neither does `$SYSTEM.Status.DisplayString`. | A reason travels as an exception, not as a rendered status. |
| `%SYSTEM.Net.HTTPRequest` does not exist in this build; the native client is `%Net.HttpRequest`, used as `Set r.Server = ...` + `Do r.Get(path)` + `r.HttpResponse.Data`. | The production's own HTTP calls use it. |
| `$$$OK` is **1**. A status of `1` is success. | Reading `sc` as a failure sent this investigation down a false path. |
| `QUIT` inside a loop ends the **loop**, not the method. | "Not found" assertions after a loop need `BREAK`, not `QUIT`. |
| `$$$AssertTrue(...)` cannot take an expression containing a comma — the macro parser reads the comma as the end of the argument. | The value is computed into a local first. |
| `%DynamicObject` exposes **`%Get`**, not `Get`. `Get` does not exist on it and the failure is `METHOD DOES NOT EXIST`, which reads like a missing method rather than a typo. | Every read of a dynamic object's property is `%Get`. |
| A business host that fails does **not** hand its response back, and `ProcessInput` swallows a thrown exception. | The reason of a failed run survives only in the gateway's log; the log write therefore happens before the failure is raised. |

## D-16: An agent run outlasts the transport that carries it

**Decision**: The agent's run is longer than the response window of the path
between the MCP bridge and IRIS, so the first release delivers the answer
through the gateway's existing **processing reference** contract rather than
inline, and the requirement is recorded as FR-031.

**Rationale**: Measured on the running stack:

| | |
|---|---|
| The agent's run (a reasoning model, several tool calls) | **29 s** |
| The bridge's wait for the REST tool call | **5 s** |

```
REST tool call to /mcp/interopmcp/v1/tool_call hit a transient wgproto error
(I/O error: Timed out waiting for HTTP response after backchannel-only sequence
(waited 5s)) after 5.000614733s -- not retrying automatically since the request
may already have reached IRIS
```

The bridge answers the caller with `BACKEND_UNAVAILABLE`, `retry_after_seconds:
30`. **The run nevertheless completes inside IRIS**, and its answer is recorded
in the invocation — read back over MCP with the gateway's existing status tool.
So the capability works; the *delivery* of a long result does not.

**And the consequence is wider than the agent's own call.** The bridge holds a
single connection to IRIS (`pool = { min = 1, max = 1 }`), and the agent's run
occupies it for the whole run. When the wait times out, the bridge declares the
server unhealthy and replaces the client:

```
INFO  IRIS server local has been unhealthy for 36.706619161s -- replacing client
INFO  Connected to IRIS at localhost:1972 with pool size 1
```

Until it reconnects, **every** tool fails — not just the agent's. The
regression suite caught it: `test_a_capability_still_executes` and the identity
and authorisation tests failed with `BACKEND_UNAVAILABLE` while the agent's run
was in flight.

So the agent's run must not hold the caller's connection. The gateway already
anticipated this: a catalogue entry carries `async` and `wait`, and the
operations guide says that a tool expected to exceed the window "should be
flagged async so agents receive a processing reference instead of blocking the
tool call". **The flag is recorded but never acted on** — the generated tool
always calls the business service synchronously. The agent is the first tool in
this project that genuinely needs it, and it is the first tool that can take
the endpoint down with it.

So the requirement is now explicit (FR-031, SC-017, SC-018) rather than
implicit, and the increment that satisfies it is clear: make the generated tool
honour the flag for an agent entry, and run the agent in the production's own
queue so that the request that carries it returns immediately.

**Alternatives considered**:
- *A smaller or faster model* — rejected as the answer: it only moves the
  problem, and the agent's value is precisely that it reasons over several
  calls. It remains the operator's lever for a deployment with a tight window.
- *Raise the transport's window* — not available: the bridge exposes no
  request-timeout option, and the wait belongs to IRIS's superserver HTTP
  transport rather than to the bridge's configuration.

**Resolution (implemented and verified)**: The generated tool now honours
`async`/`wait` for an agent entry. `Invoker.Invoke` fires the business service
through `Ens.BusinessService.CallProcessInputAsync`, the tool answers the
caller immediately with `_status: "pending"` and the run's invocation id, and
the run completes in the background; `Agent.Host` then records the answer
against that invocation, which the caller reads back with
`GetInvocationStatus`. Measured: the agent's call returns in **0.0 s** with
HTTP 200, the answer is readable afterwards, and the caller is never left
holding the connection.

## D-17: Operational notes for the implementation phase

**`$$$OK` is 1.** In InterSystems a successful status is `1`, not `0`. A probe
that reported `sc=1` as a failure sent this investigation down a false path;
the status display macro `$$$StatusDisplayString` does not exist in this build
either (`$$$StatusDisplayString` is not a defined macro — the compiler reports
"Referenced macro not defined"). Use `$$$ISOK(sc)` / `$$$ISERR(sc)` and read
the exception's `DisplayString()` inside a `Catch` block.

**`Include %AI` is a file-level include.** The RAG and agent macros live in
the `%AI` include, which sits **above** the class declaration, not inside the
class body. Code that uses `$$$IrisLLMLibrary` or `$$$LLMRAGBUILDVECTORSTORE`
must be written in a class that carries `Include %AI`; in a scratch routine the
macros do not resolve and the compiler reports a syntax error.

**The retrieval tool's argument is named `query`.** `ExecuteTool` on the tool
manager rejects anything else with "Invalid tool arguments: missing 'query'
argument".

**ObjectScript HTTP is `r.Get(path)` with `r.Server` set**, and the body is
`r.HttpResponse.Data` — the idiom already used in `iris.script`.

---

## D-18: A long run must not occupy the capacity the production's other callers need

**Decision**: The demonstration production's worker pool is sized so that an
agent run in progress and the production's ordinary capabilities are served at
the same time. The requirement is recorded as FR-060 and SC-019.

**Rationale**: The asynchronous delivery of D-16 fixed the *caller's*
connection, but the regression suite still failed — and the failure was not in
the agent's call. The bridge's log showed the timeout on a different tool
entirely:

```
ERROR Error executing tool local_mcp_interopmcp.PayLookup: WgProto error:
I/O error: Timed out waiting for HTTP response after backchannel-only sequence
(waited 5s)
```

`GetInvocationStatus` — a plain SQL read — kept working throughout, while
`PayLookup` — which enters the production — timed out. That localised the
contention to the production's own execution capacity rather than to the
bridge or to IRIS as a whole.

The cause is the pool: every item of the demonstration production carried
`PoolSize="1"`, and **a business service occupies its worker for the whole of
`ProcessInput`**. The agent's run holds its worker for the whole run — 29 s
of model calls — so while it runs, the production has no worker left for the
capability the next caller asks for.

Two measurements closed it:

| | |
|---|---|
| The container runs a single IRIS process (`iris-main`) | the run is not isolated from the rest of the traffic |
| The production's items at `PoolSize="1"` | the run holds the only worker the other capabilities need |

Raising the demonstration's pools to `PoolSize="5"` makes the whole regression
suite green **while the agent's run is in flight** — the agent's call, a
capability call, the identity test and the authorisation test all complete
inside the transport's window. The endpoint stayed available; nothing else had
to change.

This is why the requirement is written about the pool and not about the
adapter: attaching an agent to a production must not narrow the capacity that
production already offered its callers. An operator who attaches an agent to a
production whose pools are sized for one call at a time must raise them, and
the operations guide says so.

**Alternatives considered**:
- *Give the agent its own production* — rejected: it would put the agent
  outside the production it is meant to operate, which FR-020 forbids, and it
  would not remove the contention on the capabilities the agent itself calls.
- *Run the agent in a separate IRIS process* — rejected as out of the
  project's reach: the deployment runs one `iris-main`, and the platform
  decides how work is placed on it.
- *Shorten the run so it fits the window* — rejected as the answer for the
  same reason as in D-16: it moves the problem instead of solving it, and it
  is the operator's lever rather than the design's.

---

## Summary of resolved clarifications

No `NEEDS CLARIFICATION` markers remain in the specification. All three
clarification sessions of 2026-11-12 are recorded in `spec.md`. The
specification additionally fixes the execution locus (D-01), the reachability
mechanism (D-02), the configuration owner (D-03), the governance path (D-04),
the audit record (D-06), and the boundaries of both required technologies
(D-07, D-08). The implementation phase fixed the delivery of a long run
(D-16) and the capacity an agent run must not take from the production's
other callers (D-18); D-17 records the platform facts the implementation
depends on.
