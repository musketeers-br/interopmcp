# Contract: The agent tool on the MCP endpoint

Feature: `004-ai-agent-adapter` | Date: 2026-11-12

The agent is published on the MCP endpoint as one more tool, beside the
production's individual capabilities. This contract describes what a caller
sees.

---

## Publication

| Aspect | Contract |
|---|---|
| Discovery | The agent appears in the tool catalogue alongside the production's capabilities |
| Naming | The published name follows the gateway's existing naming conventions, derived from the adapter's config item name, and MUST NOT collide with an existing published tool |
| Description | The adapter's `Description` setting, so a caller can tell what the agent is for without reading its document |
| Classification | The adapter's own action classification — `readonly`, `write`, or `critical` — applied to the agent tool exactly as it is applied to every other tool |
| Presence | The agent is published only when its adapter is enabled, its configuration validates, and its production is running |

**Additive guarantee**: attaching an agent MUST NOT remove, rename, or alter
the published entries of the production's individual capabilities. The
published catalogue before and after attaching an agent differs only by the
agent's own entry.

**The guarantee is executable.** The tools published before this feature
existed are recorded in `python/tests/baselines/mcp-tools.json` with their
names and their input schemas, and checked automatically against the live
endpoint: nothing that was published may disappear, an input schema may not
change, and a description may only be added or enriched. A tool the baseline
does not know about is allowed.

**A published description may grow.** The generator emits a docstring for each
generated method, so the annotation a business service carries — and the
adapter's `Description` — reaches the MCP endpoint. Tools that were published
with an empty description gain one; no tool loses information.

---

## Input

The agent tool takes the caller's goal.

```json
{ "goal": "assess the risk of the supplier on invoice INV-2026-120.pdf" }
```

| Property | Type | Required | Meaning |
|---|---|---|---|
| `goal` | string | yes | What the caller wants, in plain language |

The schema is derived from the agent request class by the gateway's existing
schema mapper; the agent tool is published with the same one-argument shape as
any other tool.

---

## Output

The caller receives the gateway's standard tool envelope.

### Successful run

```json
{
  "_status": "ok",
  "invocationId": "<guid>",
  "message": "Tool executed successfully.",
  "answer": "Invoice 2026-120 is from company 12.345.678/0001-95, which is not on the restricted list, but whose registration is cancelled. Clause 3.2 of the risk policy requires human approval in this case, so the assessment is pending.",
  "capabilitiesUsed": [
    { "name": "ReadInvoiceDetails", "invocationId": "<guid>" },
    { "name": "RiskCheck",             "invocationId": "<guid>" }
  ],
  "retrievals": [
    { "source": "politica-de-risco.md", "score": 0.599, "category": "policy" }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `_status` | string | `ok`, `held`, `pending`, or `error` — the gateway's existing values |
| `invocationId` | string | The run's identifier, usable with the gateway's status tool |
| `answer` | string | The agent's final answer |
| `capabilitiesUsed` | array | The capabilities the agent invoked, each with its own invocation identifier |
| `retrievals` | array | The passages the agent retrieved, each with its source and score |

### Run accepted, answer to be collected

The agent's run outlasts the response window of the path between the MCP bridge
and IRIS, so the agent tool answers the caller as soon as the run has started
and the answer is collected through the status surface:

```json
{
  "_status": "pending",
  "invocationId": "<guid>",
  "message": "The run has started. Use GetInvocationStatus with invocationId to collect the result."
}
```

The caller is not left holding the connection, and the run continues in the
background. `GetInvocationStatus` with that `invocationId` returns the answer
once the run has finished, in the same envelope the gateway already returns
for any other invocation.

### Held for approval

When the agent's own classification requires a human decision, the envelope is
the gateway's existing held shape:

```json
{
  "_status": "held",
  "invocationId": "<guid>",
  "approvalId": "<guid>",
  "message": "Critical call held for approval. Use GetInvocationStatus with invocationId to check progress."
}
```

### Error

```json
{ "_status": "error", "message": "<diagnosable reason>" }
```

An error carries a reason an operator can act on: an invalid configuration, an
unreachable model provider, a document that could not be read, or a run that
reached its effort or time bound. A failure is never reported as a clean
result.

---

## Behaviour under the caller's hands

### The agent's authority

An agent-initiated capability call is classified exactly as the equivalent
direct call would be. A capability classified as `critical` is held for a human
decision, and the agent is told the action is pending. A capability outside the
agent's scope is not reachable by the agent even if it attempts it.

### The run's identity

Every capability the agent invokes appears in the production's own trace under
the identity the run was made under, and as its own invocation record with the
classification and approval decision that were applied.

### Optional knowledge

An agent with no knowledge attached starts, answers, and completes successfully.
It never claims to have consulted documentation it did not retrieve, and when
retrieval returns nothing it says it has no documented basis rather than
inventing one.

### A run that outlasts the transport

An agent run is longer than the response window of the path between the MCP
bridge and IRIS. When that happens the caller receives a **processing
reference** rather than the answer inline, and the answer is retrieved through
the status surface once the run completes. The run is recorded either way: a
run that completes after the caller has given up still leaves its answer in
the invocation record.

This is the agent tool's normal path, not an exceptional one: the agent's
catalogue entry carries `async` and `wait`, and the generated tool honours
them — the run is dispatched to the production's own queue and the tool
returns immediately.

### A run does not narrow the production's capacity

While an agent run is in progress, the production's other capabilities remain
callable through the same endpoint and complete within the transport's
response window. An operator who attaches an agent to a production whose
worker pools are sized for one call at a time must raise them; the operations
guide says so.

### Bounds

A run that reaches its effort or time bound ends with an explicit recorded
outcome within two minutes of the bound, and is never left in progress.
