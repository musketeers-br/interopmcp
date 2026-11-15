# Implementation Plan: AI Agent Adapter for Interoperability Productions

**Branch**: `004-ai-agent-adapter` | **Date**: 2026-11-12 | **Spec**: `specs/004-ai-agent-adapter/spec.md`

**Input**: Feature specification from `specs/004-ai-agent-adapter/spec.md`

## Summary

Give an existing IRIS Interoperability production agentic capability without
rewriting it. The operator attaches a custom inbound adapter to the
production, writes a plain-language document that dictates the agent's rules,
and the agent is published on the MCP endpoint beside the production's own
business capabilities. A caller hands the agent a goal in plain language; the
agent decides which of the production's capabilities to use, acts through them
— so the existing classification, approval, and audit path applies to the
agent's actions exactly as it applies to a direct caller's — and answers with
what it did.

Three technologies are demonstrated for real in the bundled demonstration
production: an application-layer capability implemented in **Embedded Python**
that reads supplier invoice documents, work the platform's native language does
not provide; the production's own registry lookup left in the native language,
where the platform provides it natively; and **vector search** over the
production's own written policies, so the rules that govern the agent's
decisions live outside the agent and the agent has to find them.

## Technical Context

**Language/Version**: ObjectScript (InterSystems IRIS 2027.1.0AI, build 109U);
Embedded Python 3.12.3 inside the same IRIS runtime

**Primary Dependencies**: `%AI.Agent`, `%AI.Agent.Session`, `%AI.Provider`,
`%AI.ToolSet`, `%AI.Tool`, `%AI.ToolMgr`, `%AI.RAG.Embedding.FastEmbed`,
`%AI.RAG.VectorStore.IRIS`, `%AI.RAG.KnowledgeBase`, `Ens.InboundAdapter`,
`Ens.BusinessService`, `pypdf` (embedded Python), and the gateway's own
`br.musketeers.InteropMCP.{Registry,Invoker,Guardrails,ToolSet,Invocations,Log}`

**Storage**: IRIS globals (`^InteropMCP.Catalog`, `^InteropMCP.InvocationsD`,
`^InteropMCP.LogD`); a SQL table with a `VECTOR` column and an HNSW index for
the retrieval store; the demonstration's documents on disk, mounted read-only
from the repository into the container

**Testing**: IRIS `%UnitTest` for the gateway and the new classes; `pytest`
for the fixtures and the HTTP-level protocol; manual MCP client runs for the
end-to-end scenarios

**Target Platform**: The IRIS Interoperability namespace of the existing
container stack; the same image and compose topology as today, plus one
Python package in the embedded runtime

**Project Type**: An extension to an existing IRIS Interoperability module
that ships inside the IPM package, with a demonstration production that stays
outside it

**Performance Goals**: Agent tool call within the gateway's existing wait
window for the enqueueing call; retrieval under one second on a corpus of
policy documents; no measurable overhead on the publication path for
productions that do not attach an agent

**Constraints**: The gateway still only fires business services and never
writes production structures; the guardrail, approval, and audit path are
reused rather than duplicated; the agent runs inside the production; no
credential is stored in configuration; the retrieval needs no outbound call
when the platform's local embedding provider is used; the agent's document is
revisable without redeploying the production's components

**Scale/Scope**: One agent per production in the first release; one document
corpus per production; one agent run at a time per adapter; no high-volume
automation — the demonstration is a handful of runs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Constitution Principle | Status | Evidence |
|---|---|---|
| Container-Oriented Architecture | PASS | No new infrastructure: the agent runs in the existing IRIS container, the documents are mounted with the repository, and the only new artefact is one Python package installed into the embedded runtime by the existing Dockerfile step. No new service, port, or compose service |
| Comprehensive Logging | PASS | Adapter configuration, run start and end, capability selection, retrieval, approval hold, and failure are all logged through the gateway's existing `br.musketeers.InteropMCP.Log` at the levels it already supports; the agent's own capability calls are logged by the same path as a direct caller's |
| Monitoring and Observability | PASS | Per-run detail (capabilities used, retrievals performed) is carried in the invocation record the gateway already exposes through its status tool; adapter configuration state and agent availability extend the existing `Health` snapshot; retrieval is queryable through the same audit plane |
| Security by Design | PASS | The agent's actions pass through the existing per-tool classification and approval gate, so an agent cannot bypass a control a direct caller faces (FR-016, FR-055); provider credentials are referenced from the governed secret store and never written in configuration (FR-053); the agent's calls are attributed to the run's identity and audited (FR-055); the agent cannot reach capabilities outside its scope (FR-056) |
| Technology Stack | PASS | ObjectScript for the IRIS business logic, the gateway changes, and the production's registry lookup; Python for the one thing the native language does not provide — reading documents — and for the retrieval tooling, as the constitution assigns services and integration to Python. No alternative stack, no frontend |

All gates pass. No violations → Complexity Tracking section not required.

## No-regression guarantee

The catalogue builder is the path **every** published tool goes through. A
change that teaches it about agents can therefore break the discovery of the
capabilities that were already served — silently, because the endpoint simply
stops advertising a tool, and fatally for every caller at once. This feature
takes that risk explicitly rather than hoping for it.

**The contract.** The tools published before this feature existed were captured
from the running gateway and recorded in the repository, with their names and
their input schemas (`python/tests/baselines/mcp-tools.json`). An automated
check (`python/tests/test_mcp_tool_surface.py`) enforces three rules against
the live endpoint:

- every baseline tool is still published;
- every baseline input schema is exactly what it was;
- a description is never removed — only added or enriched.

A tool the baseline does not know about is allowed: that is the agent being
published alongside the capabilities. A capability published before must still
execute, not merely be advertised.

**The contract has been seen to fail.** A one-line change to the generator that
omitted one tool from the generated class was compiled into the running
instance, the catalogue rebuilt, and the server restarted. All three checks
failed, naming the missing tool; the change was then reverted and they passed
again. A guard that has never been observed failing is a claim, not a check.

**The operational requirement this uncovered.** The MCP server loads the
published surface when it starts and keeps it; a catalogue rebuild on its own
does not change what callers see. Two consequences, both of which the
operator's guide must state:

1. An agent that is attached and published does not reach callers until the
   server is restarted — otherwise the feature looks broken.
2. A catalogue build that accidentally drops a capability stays invisible to
   the endpoint until the server restarts, which is exactly when the
   regression is most dangerous. The regression check therefore runs against
   the endpoint **after** a restart, and the deployment's existing supervisor
   makes the restart a one-line operation.

**The one published-surface change this feature makes is additive.** The
generator starts emitting a `///` docstring for each generated method, so the
`AIGATEWAYDESC` annotation and the adapter's `Description` finally reach the
MCP endpoint. Today the generated business-capability tools are published with
an empty description, because the generator emits no docstrings. This adds
information to the published surface and removes none, which is exactly what
the contract allows — and it is what makes the agent discoverable (FR-023).

## Project Structure

### Documentation (this feature)

```text
specs/004-ai-agent-adapter/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── agent-tool.md          # the published MCP surface of the agent
│   └── adapter-settings.md    # the configuration an operator sets
├── checklists/
│   └── requirements.md  # from /speckit.specify
└── tasks.md             # Phase 2 output (created by /speckit.tasks — NOT by this command)
```

### Source Code (repository root)

The project follows a single-package ObjectScript structure under
`src/br/musketeers/InteropMCP/` (existing layout). The agent's classes are
production-agnostic and belong in the IPM package, alongside the gateway core;
the demonstration's production-specific classes stay in `Demo/`, outside the
package, as the existing arrangement already does.

```text
src/br/musketeers/InteropMCP/
├── Agent/
│   ├── Adapter.cls          # New: Ens.InboundAdapter. Carries the agent's configuration
│   │                        #   (Prompt, Purpose, Model, ProviderConfig, AgentTools,
│   │                        #   MaxIterations, Timeout, KnowledgeBase) and resolves it from
│   │                        #   the production at run time.
│   ├── Host.cls             # New: Ens.BusinessService, Parameter ADAPTER = the adapter
│   │                        #   above. The entry point the gateway calls by config item
│   │                        #   name; resolves the configuration, builds the agent, runs
│   │                        #   it, and returns the answer.
│   ├── Request.cls          # New: Ens.Request. Carries the caller's goal; the published
│   │                        #   input schema is derived from it by the existing mapper.
│   ├── Response.cls         # New: Ens.Response. Carries the answer, the capabilities used,
│   │                        #   and the retrievals performed.
│   ├── Builder.cls          # New: assembles the %AI.Agent from the adapter's settings —
│   │                        #   model, provider, document, tool surface, effort bound.
│   ├── Knowledge.cls        # New: builds the %AI.RAG.KnowledgeBase over the production's
│   │                        #   policies, with the local embedding provider, and indexes
│   │                        #   them with stable source identities.
│   └── ToolSet.cls          # New: the tool surface the agent is given.
├── AgentTools.cls           # New: generated at catalogue build; the capabilities the agent
│                            #   may reach, excluding the agent's own entry. The stub is
│                            #   checked in so ToolSet.cls compiles before the first build.
├── Registry.cls             # Modified: recognise an agent adapter item and publish an
│                            #   agent entry (kind=agent) pointing at the host config item
│                            #   and the agent request class; emit a /// docstring per
│                            #   generated method so descriptions reach the MCP endpoint.
├── Invoker.cls              # Modified: record a failed invocation as failed, with the reason.
├── Guardrails.cls           # Modified: declare Check's return type, so its error paths
│                            #   report the error instead of crashing the caller.
├── Invocations.cls          # Unchanged: the run is an invocation row; the run detail
│                            #   travels in the result envelope.
├── Health.cls               # Modified: report adapter configuration state and agent
│                            #   availability.
└── Demo/
    ├── Production.cls       # Modified: add the agent's item, with the adapter's settings
    │                        #   on the Adapter target. Items stay grouped by type: the
    │                        #   parser refuses a service placed after a process.
    ├── AgentHost.cls        # New: the demonstration's agent host.
    ├── AgentTools.cls       # New: the demonstration's agent tool set — the published
    │                        #   capabilities the agent may reach, excluding the agent's
    │                        #   own entry.
    ├── InvoiceDetailsBS.cls # New: the application-layer capability that reads a supplier
    │                        #   invoice through Embedded Python.
    ├── RestrictedCheckBS.cls# New: the production's own restricted-list check.
    ├── RegistryLookupBS.cls # New: the production's own company-registry lookup, in the
    │                        #   native language.
    ├── Invoices/            # New: the demonstration's invoice fixtures (generated).
    └── Policies/            # New: the demonstration's policy corpus (indexed).

scripts/
├── generate-demo-invoices.py  # New: generates the invoice fixtures, refusing to emit a
│                              #   document whose identifier or total is wrong.
└── requirements-dev.txt       # New: development-only dependencies for the generator.

python/tests/
├── test_demo_invoices.py      # New: guards the fixtures — readable, correct details,
│                               #   valid check digits, and in step with the generator.
├── test_mcp_tool_surface.py   # New: the no-regression contract over the published MCP
│                               #   surface — nothing that was published may disappear.
└── baselines/
    └── mcp-tools.json         # New: the published surface captured before this feature
                                #   existed; the contract the check enforces.

requirements.txt                # Modified: add pypdf for the embedded runtime.
```

**Structure Decision**: The project keeps its single ObjectScript package. The
agent's classes go in a new `Agent/` sub-package of that package, because they
are production-agnostic and must ship in the IPM module alongside the gateway
core — the same split the project already draws between `br.musketeers.InteropMCP`
(shipped) and `Demo/` (not shipped). The demonstration's production-specific
classes stay in `Demo/`. No new top-level directory, no frontend, no new
service. The contracts directory is **not** empty: the feature publishes a tool
on an existing external interface, so the published shape of the agent tool and
the operator-facing configuration are both documented.

## Phase 0: Outline & Research

No `NEEDS CLARIFICATION` markers remain in the specification — all three
clarification sessions of 2026-11-12 are recorded there. The research phase
resolved the design questions the specification deliberately left to it.

**Output**: `research.md` — ten decisions (D-01 … D-10), each with the decision,
the rationale, the alternatives considered, and the evidence gathered against
the running instance. The decisions that matter most: the gateway reaches the
agent through a Business Service, so the existing invoker, guardrail, approval,
and audit path are reused unchanged (D-02); the adapter owns the configuration
and the host resolves it from the production (D-03); the agent reaches the
production's capabilities through the published tools, so the governance path
applies to the agent's actions for free (D-04); the run is an invocation row
rather than a new audit entity (D-06); Embedded Python is limited to reading
documents (D-07); and vector search grounds the agent in the production's
written rules (D-08).

One open item is recorded rather than resolved: whether the per-agent tool
surface is best realised as a second generated class — extending the registry's
existing generation pattern — or as a runtime tool manager built from
per-method tool instances. The first is the plan's assumption; the second is
the route to a hot scope and to the finer-grained authority deferred by FR-019.

## Phase 1: Design & Contracts

### data-model.md

Entities extracted from the feature specification: the **Agent Adapter** (the
configuration the operator sets, with its validation rules), the **Agent
Request** and **Agent Response** (the published input and output), the **Agent
Run** (derived, not a new entity — an invocation row extended), and the
existing **Capability**, **Tool Entry** (extended with a `kind`), **Approval**,
plus the new **Knowledge Source**, **Registration Record**, and **Invoice
Document**. State transitions for the run, for a capability the agent calls, and
for a document extraction.

### contracts/

- `agent-tool.md` — the published MCP surface: how the agent appears beside the
  production's capabilities, the input shape, the three output shapes (success,
  held, error), and the behaviour a caller can rely on (authority, trace,
  optional knowledge, bounds).
- `adapter-settings.md` — the configuration an operator sets: the two items
  added to the production, the adapter's settings and their meanings, the
  validation rules, and — explicitly — what the operator does **not** have to
  do.

### quickstart.md

A runnable validation guide: the prerequisites, the setup, and eight
validation scenarios (V1–V8) covering publication, capability selection, the
restricted-supplier hold, retrieval by meaning, answering from the policies,
running without knowledge, failing loudly on an unreadable document, and the
run history — each mapped to the success criteria it proves.

**Re-evaluate Constitution Check post-design**: all gates still pass. The design
introduces no new service, no new credential, no new language, and no second
audit plane; the agent's actions traverse the guardrail, the approval gate, and
the invocation store that already exist. The one change to an existing
component, the catalogue builder recognising an agent item, adds a branch
inside the builder and changes no behaviour for productions that attach no
agent — a property the published-surface contract now enforces automatically
rather than merely asserting.

---

**Done When**: Phase 1 artifacts generated (`research.md`, `data-model.md`,
`quickstart.md`, `contracts/`), Constitution Check passes both before Phase 0
and after Phase 1.

**Next command**: `/speckit.tasks` to generate the implementation task list.
