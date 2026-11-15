# Data Model — AI Agent Adapter

Feature: `004-ai-agent-adapter` | Date: 2026-11-12

Entities are described without prescribing implementation. Storage location is
given where it matters for the gateway's audit rules.

---

## Agent Adapter — new

The configuration that attaches an agent to a production. A production item of
class `br.musketeers.InteropMCP.Agent.Adapter` (`Ens.InboundAdapter`).

| Field | Type | Required | Meaning |
|---|---|---|---|
| `Name` | config item name | yes | Identity of the adapter in the production |
| `Prompt` | text | yes | The agent's document: the plain-language instructions that govern the agent's role and conduct |
| `Description` | text | yes | What the agent is for, published as the agent tool's description so a caller can discover it |
| `Model` | text | no | The language model to use; empty means the platform default |
| `ProviderConfig` | JSON | no | Provider settings, with secrets referenced from the governed configuration store, never inline |
| `AgentTools` | list of names | no | The published capabilities the agent may reach; empty means every published capability of the production |
| `MaxIterations` | integer | no | The effort bound for one run |
| `Timeout` | integer | no | The elapsed-time bound for one run, in seconds |
| `KnowledgeBase` | name | no | The indexed knowledge the agent retrieves; empty means no retrieval |
| `BusinessHost` | config item name | yes | The Business Service that runs the agent, and the entry point the gateway calls |

**Validation rules** (FR-007):
- `Prompt` must not be empty — an agent with no document has no rules.
- `MaxIterations` and `Timeout` must be positive when present.
- `ProviderConfig` must not carry a credential value; a credential is referenced
  from the governed store.
- `BusinessHost` must name an enabled Business Service item of the same
  production.

**Relationships**: one adapter belongs to one production. The adapter's
`BusinessHost` names the Business Service that serves it. Both are production
items, so they are enabled, disabled, and started with the production.

---

## Agent Request — new

The request the MCP caller sends to the agent tool. An `Ens.Request` subclass
whose single property is the caller's goal.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `Goal` | text | yes | What the caller wants, in plain language |

The published input schema is derived from this class by the existing schema
mapper, so the agent tool is published with a one-argument schema and needs no
special-casing in the gateway.

---

## Agent Response — new

The response the agent's Business Service returns. An `Ens.Response` subclass.

| Field | Type | Meaning |
|---|---|---|
| `Answer` | text | The agent's final answer to the caller |
| `CapabilitiesUsed` | list | The published capabilities the agent invoked, with the invocation identifier of each |
| `Retrievals` | list | The passages the agent retrieved, with the source document and the score |
| `Status` | text | `completed`, `failed`, `held`, or `blocked` |

The caller-facing envelope is the gateway's existing one — the generated tool
wraps this response with `_status`, `invocationId`, and `message` — so the
agent tool is indistinguishable in shape from every other published tool.

---

## Agent Run — derived, not a new entity

One execution of the agent against one goal. It is **not** a new record: it is
an invocation of the agent tool in the existing invocation store, extended.

| Field | Where it lives | Meaning |
|---|---|---|
| Goal | invocation parameters | What the caller asked for |
| Adapter and production | invocation's tool name, resolved through the catalogue | Which agent ran |
| Identity | invocation's agent identity | Who asked |
| Outcome | invocation status | `completed`, `failed`, `held`, `blocked` |
| Timing | invocation started-at and ended-at | How long it took |
| Capabilities used | agent response, inside the invocation result | What the agent did |
| Retrievals performed | agent response, inside the invocation result | What the agent consulted |

The agent's individual capability calls are **separate invocation rows**,
exactly as a direct caller's would be, and they carry the classification and
approval decision that were applied. A reader therefore sees both the run and
the actions it caused, in the same audit plane.

---

## Capability — existing, unchanged

A callable business capability of the production as published to clients.

| Field | Meaning |
|---|---|
| Published name | How a caller and the agent refer to it |
| Description | What it does |
| Action classification | `readonly`, `write`, or `critical` — the authority the gateway applies |
| Owning production | Which production it belongs to |

The agent reaches capabilities through this same concept that clients call
directly, and an agent-initiated call is classified as the equivalent direct
call would be.

---

## Tool Entry — existing, extended

A published entry in the MCP catalogue.

| Field | Meaning |
|---|---|
| Name | The published tool name |
| Description | What the tool does |
| Classification | The authority applied |
| Kind | **new**: `capability` or `agent` |
| Request class | The request class the arguments are bound to |
| Service name | The production config item the tool fires |
| Enabled | Whether the tool is published at all |

`kind` is the only new field. It is what tells the catalogue builder that an
entry points at an agent rather than at a business capability, and it is what
keeps the agent's own entry out of the agent's reachable scope.

---

## Knowledge Source — new

A document made available to the agent for retrieval.

| Field | Meaning |
|---|---|
| Source identity | Stable identifier; the basis of deterministic chunk identity and safe re-indexing |
| Content | The text that is embedded |
| Metadata | The production and category the passage belongs to, used to narrow retrieval |
| Indexed at | When it was indexed |

Knowledge is optional: a production may have none, and an agent with none
attached is fully functional.

---

## Registration Record — new, external

What an external company registry reports about a company.

| Field | Meaning |
|---|---|
| Company identifier | The identifier that was looked up |
| Registration situation | `ATIVA`, `BAIXADA`, `INAPTA`, `SUSPENDIDA` |
| State | The federative unit |
| Retrieved at | When the record was fetched |

Obtained by the production's own native-language call; the rules that judge it
are the production's.

---

## Invoice Document — new, external

A supplier invoice the production reads.

| Field | Meaning |
|---|---|
| Document identity | The file the invoice came from |
| Supplier company identifier | Extracted from the document |
| Invoice number | Extracted from the document |
| Amount | Extracted from the document |
| Extraction outcome | Whether the details were extracted, or the document was rejected |

---

## Approval — existing, unchanged

A pending human decision that an agent-initiated action triggered. The agent
does not get a mechanism of its own: it reaches the same approval store and the
same workflow inbox a direct caller reaches.

---

## State transitions

**Agent run** (the invocation's status):

```
received → executing → completed
                   → failed
        → pending-approval → executing
                          → rejected
```

**Capability call made by the agent**: identical to a direct caller's —
`readonly` proceeds, `write` proceeds and is logged, `critical` is held for
approval and the agent is told the action is pending.

**Document extraction**: `read → extracted | rejected`. A document that cannot
be read, or that does not carry the expected details, is rejected; it never
yields a partially extracted result.
