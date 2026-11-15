# Quickstart — Validating the AI Agent Adapter

Feature: `004-ai-agent-adapter` | Date: 2026-11-12

A runnable validation guide. It proves the feature end to end without
containing the implementation.

---

## Prerequisites

- The container stack running, with the IRIS instance healthy and the MCP
  bridge listening:

  ```bash
  docker compose ps
  docker exec ai-hub-dev-template-iris-1 iris session IRIS <<< "zn \"IRISAPP\""
  ```

- A model provider configured in the platform's governed configuration store.
  The agent needs a model; the retrieval does not — the platform's local
  embedding provider is used, so there is no second credential.

- The demonstration production's fixture documents present:

  ```bash
  ls src/br/musketeers/InteropMCP/Demo/Invoices/
  ls src/br/musketeers/InteropMCP/Demo/Policies/
  ```

  Three invoices (`INV-2026-118`, `INV-2026-119`, `INV-2026-120`) and three
  policies (`politica-de-risco`, `politica-de-restricao`,
  `admissao-de-fornecedores`).

- An MCP client configured against the endpoint, as in the project's quick
  start (`opencode.json` already registers the `InteropMCP` server).

---

## Setup

1. Compile the new classes and the modified gateway classes.
2. Add the agent adapter and the agent's host to the demonstration
   production, and set the adapter's `Prompt` and `Description`.
3. Point the adapter's `BusinessHost` at the host.
4. Rebuild the catalogue so the agent is published:

   ```objectscript
   zn "IRISAPP"
   do ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
   ```

5. **Restart the MCP server.** The server discovers the published surface when
   a client connects and keeps it for that client's identity; a catalogue
   rebuild on its own does not change what callers see. The deployment already
   supervises the server, so stopping it is enough:

   ```bash
   docker exec ai-hub-demo-web-iris-1 pkill -f '[i]ris-mcp-server'
   # the supervisor brings it back within about 30 seconds; wait for the
   # endpoint to answer again before continuing
   ```

   The deployment's configuration keeps the background tool refresh off
   (`tool_refresh_interval_secs = 0`): a refresh that runs without a
   credential drops the registration, and the endpoint answers "tool cannot be
   reached" to every caller until the next client connects. With the refresh
   off, the surface is discovered per client connection and stays stable.

   Wait for the endpoint before continuing:

   ```bash
   # a new client connection re-runs the discovery and re-registers the tools
   curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/mcp/interopmcp
   ```

6. Index the demonstration's policies into the knowledge base the adapter names.

7. **Size the production's worker pools for a run in progress.** A business
   service occupies its worker for the whole of `ProcessInput`, and the
   agent's run holds its worker for the whole run. A production whose pools
   hold one call at a time therefore has no worker left for the next caller
   while the agent runs, and the endpoint stops serving the production's own
   capabilities (FR-060, SC-019). The demonstration production carries
   `PoolSize="5"` on every item:

   ```xml
   <Item Name="AgentHost" ClassName="br.musketeers.InteropMCP.Demo.AgentHost" PoolSize="5" Enabled="true">
   ```

   An operator attaching an agent to a production of their own must make the
   same adjustment.

---

## Validation scenarios

### V0 — Nothing that was published before has changed

**Run**:

```bash
python -m pytest python/tests/test_mcp_tool_surface.py -v
```

**Expected**: all three checks pass. Every tool that was published before the
agent existed is still published, with the same name and the same input schema;
no description was removed; and a capability published before still executes
through the endpoint.

**This is the check that must be run after every change to the catalogue
builder.** It has been seen to fail: with one tool omitted from the generated
class, it fails with the name of the missing tool.

### V1 — The agent is published, and nothing else changed

**Run**: list the tools on the endpoint.

**Expected**: the agent appears as one more entry; every previously published
capability is still present, with the same name and description. Compare the
published catalogue captured before step 4 with the one after — the only
difference is the agent's entry.

### V2 — The agent reaches the production's capabilities

**This scenario needs a model provider.** The demonstration uses NVIDIA NIM
(`nim`) with the credential referenced from the environment, so nothing is
stored in the production's configuration:

```
NGC_API_KEY / NVIDIA_API_KEY -> referenced by the adapter's ProviderConfig
model                       -> nvidia/nemotron-3.5-lightning-30b-a3b
```

**Restart the MCP server afterwards** — not for the agent's sake, but so the
rebuilt catalogue is visible to callers.

**Run**: call the agent tool.

```json
{ "goal": "assess the risk of the supplier on invoice INV-2026-119.pdf" }
```

**Expected**: `_status` is `pending` and the envelope carries the run's
`invocationId` — the call returns immediately, because an agent run outlasts
the response window of the path between the MCP bridge and IRIS (the bridge
waits 5 s, the run takes about 30 s). The answer is collected through the
status surface:

```json
{ "invocationId": "<the id the first call returned>" }
```

against `GetInvocationStatus`. Once the run has finished, the answer names
the supplier, its registration situation, and the assessment, and
`capabilitiesUsed` lists the capabilities the agent invoked, each with its own
invocation identifier.

### V3 — A restricted supplier is held for approval

**Run**:

```json
{ "goal": "assess the risk of the supplier on invoice INV-2026-118.pdf" }
```

**Expected**: the answer says the company is on the restricted list and that
the assessment is pending human approval; the risk assessment itself did not
run. A task appears in the operator's workflow inbox.

**Verify**: the production's trace shows the capabilities the agent did invoke,
under the identity the run was made under.

### V4 — The agent finds the rule it needs by meaning

**Run**:

```json
{ "goal": "assess the risk of the supplier on invoice INV-2026-120.pdf" }
```

**Expected**: the answer cites the clause it retrieved — the one about a
cancelled registration — and requests human approval because of it. The
retrieval is recorded with its source document and score.

**This is the scenario that distinguishes the retrieval from a keyword
search**: the question the agent asks shares no literal wording with the
clause it finds.

### V5 — The agent answers from the policies

**Run**:

```json
{ "goal": "what do I need from a new supplier before I can pay their invoices?" }
```

**Expected**: the answer lists the four documents, citing the supplier
admission policy.

### V6 — The agent works without knowledge

**Run**: detach the knowledge base from the adapter, then repeat V2.

**Expected**: the agent still answers V2 correctly, and never claims to have
consulted a policy.

### V7 — A document that cannot be read fails loudly

**Run**: point the extraction at a document that is not a readable invoice.

**Expected**: the run ends in failure with a diagnosable reason. It is never
reported as an assessment with no findings.

### V8 — The run history is complete

**Run**: query the invocation store for the agent tool's invocations.

**Expected**: each row carries the goal, the identity, the status, the timing,
and a result envelope holding the answer, the capabilities used, and the
retrievals performed.

---

## Automated checks

```bash
# The fixture documents are readable and their identifiers are valid
python -m pytest python/tests/test_demo_invoices.py -v

# The gateway's own configuration validator
python scripts/validate-mcp-config.py
```

```objectscript
zn "IRISAPP"
Set sc = ##class(%UnitTest.Manager).RunTest("tests/br/musketeers/InteropMCP", "/noload")
```

---

## Success criteria covered

| Criterion | Scenario |
|---|---|
| SC-001 | V1 — under 30 minutes from an unmodified production to a callable agent |
| SC-002 | V2 — the agent selects the right capability without being told |
| SC-003 | V2, V3 — every agent-initiated call appears in the production's trace |
| SC-004 | V4, V5 — the answer identifies the rule it retrieved and its source |
| SC-005 | V2, V4 — a bounded run ends with an explicit outcome |
| SC-006 | V8 — the run history is complete |
| SC-007 | V2, V7 — the embedded-Python extraction works, and a broken one fails the run |
| SC-008 | V1 — attaching the agent changes no existing published entry |
| SC-009 | V1 — an unentitled caller cannot reach the agent |
| SC-010 | any scenario against a production other than the demonstration |
| SC-011 | V6 — the agent works with no knowledge attached |
| SC-012 | V3 — a critical action is always held for a human decision |
| SC-014 | V0 — the published surface of a production without an agent is unchanged |
| SC-015 | V0 — a capability published before still executes |
| SC-016 | setup step 5 — a catalogue rebuild becomes visible to callers |
| SC-017 | V2 — a run that outlasts the transport leaves a processing reference, and the answer is retrievable |
| SC-018 | V2 — a realistic run completes and its answer is retrievable, whether or not the caller waited |
| SC-019 | V2 — while the run is in progress, the production's other capabilities still execute inside the window |
