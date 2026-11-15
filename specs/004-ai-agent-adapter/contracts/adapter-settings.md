# Contract: The agent adapter's configuration

Feature: `004-ai-agent-adapter` | Date: 2026-11-12

The configuration an operator sets when attaching an agent to a production.
This is the surface that makes the feature non-invasive: an operator adds two
items to a production and writes a document; no existing component of the
production is touched.

---

## What the operator adds to the production

**One item**: a Business Service — the agent's *host* — whose `ADAPTER`
parameter names the custom inbound adapter that carries the agent's
configuration. The framework creates the adapter for the host.

```text
production
└── AgentHost   (Ens.BusinessService, Parameter ADAPTER = "...Agent.Adapter")
    ├── Purpose, Prompt, ProviderConfig, ...   <- the adapter's own settings
    └── the custom inbound adapter, created by the framework
```

An inbound adapter cannot be a production item in its own right: the platform
recognises business services, processes and operations, and nothing else. An
adapter is referenced *by* a business host, through that host's `ADAPTER`
parameter — which is how every adapter in the platform works.

The agent's published tool name is the item's name, which keeps the gateway's
naming convention intact: a business service loses its trailing "BS"
(`PayLookupBS` → `PayLookup`), and the agent's host is published as it is
named.

## The adapter's settings

The settings live on the production item's **Adapter** target — they belong to
the adapter, not to the host.

| Setting | Type | Required | Meaning |
|---|---|---|---|
| `Prompt` | text | yes | The agent's document. The plain-language instructions that govern the agent's role, its conduct, and what it must never do |
| `Description` | text | yes | What the agent is for. Published as the agent tool's description so a caller can discover it without reading the document |
| `Model` | text | no | The language model. Empty means the platform default |
| `ProviderConfig` | JSON | no | Provider settings. Credentials are **referenced** from the governed configuration store, never written here |
| `AgentTools` | list of published capability names | no | The capabilities the agent may reach. Empty means every published capability of the production |
| `MaxIterations` | integer | no | The effort bound for one run |
| `Timeout` | integer | no | The elapsed-time bound for one run, in seconds |
| `KnowledgeBase` | name | no | The indexed knowledge the agent retrieves. Empty means no retrieval |

### The agent's document

The document is plain language, and it says what the agent should do and what
it must not do. It is **not** the rules themselves: it points at the
production's policies, which the agent retrieves.

An example from the demonstration:

> You are a risk analyst operating this production. When you are given a supplier
> invoice, read it and identify the supplier. Before assessing any company, check
> whether it appears on the restricted list. If it does, request human approval
> for the risk assessment instead of running it, and report that the request is
> pending. If it does not, look up the company's registration and assess it.
> Never rely on remembered identifiers - always read the document and check the
> list.

**Changing the document is hot**: a revision takes effect on the next run,
without any component of the production being redeployed.

### The provider configuration

Credentials are never written into the adapter's configuration. They are
referenced from the platform's governed configuration and secret store, so the
adapter's configuration can be read, copied, and versioned without carrying a
secret with it.

---

## Validation

The configuration is validated when the adapter starts. An invalid or
incomplete configuration is reported with a diagnosable reason rather than
failing silently at run time:

| Condition | Reported as |
|---|---|
| `Prompt` is empty | the agent has no rules |
| `MaxIterations` or `Timeout` is not positive | the bound is not usable |
| `ProviderConfig` carries a credential value | the credential must be referenced, not stored |
| `BusinessHost` names no enabled Business Service of the production | the agent has no entry point |

---

## What the operator does not have to do

- Annotate a business service class to make it reachable by the agent.
- Modify an existing business service class, business process, or operation.
- Rewrite an integration, or add a new one.
- Provision a second credential for the retrieval, when the platform's local
  embedding provider is used.
- Deploy a separate service to host the agent: it runs inside the production.
