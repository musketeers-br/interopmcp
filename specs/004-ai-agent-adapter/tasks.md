---

description: "Task list for the AI agent adapter: giving an existing IRIS Interoperability production agentic capability through a document"
---

# Tasks: AI Agent Adapter for Interoperability Productions

**Input**: Design documents from `/specs/004-ai-agent-adapter/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Test tasks are included. The project's quality gate requires ≥ 90 % line
coverage on the `br.musketeers.InteropMCP` package, and every user story in the
specification carries acceptance scenarios that must be executable.

**Organization**: Tasks are grouped by user story so each story can be
implemented, tested, and delivered independently. The published MCP surface is
protected by an executable contract that every gateway change must keep green.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- **ObjectScript**: `src/br/musketeers/InteropMCP/` for the shipped package;
  `src/br/musketeers/InteropMCP/Demo/` for the demonstration production (not
  shipped in the IPM module)
- **ObjectScript tests**: `tests/br/musketeers/InteropMCP/Test*.cls`
- **Python**: `python/tests/` for the HTTP-level and fixture tests
- **Fixtures**: `src/br/musketeers/InteropMCP/Demo/Invoices/`,
  `src/br/musketeers/InteropMCP/Demo/Policies/`
- **Scripts**: `scripts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies and the shared scaffolding the feature needs

- [X] T001 Add `pypdf==7.0.1` to `requirements.txt` so the embedded Python runtime can read supplier invoice documents
- [X] T002 Create the package directory `src/br/musketeers/InteropMCP/Agent/` and confirm it ships in the IPM module — add `<Resource Name="br.musketeers.InteropMCP.Agent.PKG"/>` to `module.xml` if the sub-package is not already covered by the existing `br.musketeers.InteropMCP.PKG` resource
- [X] T003 [P] Add a `DemoRoot` class parameter to `src/br/musketeers/InteropMCP/Demo/Setup.cls` holding the demonstration's asset root, defaulting to the in-container repository path `/home/irisowner/dev/src/br/musketeers/InteropMCP/Demo`, so the policies and the invoices are found without a hard-coded path — the invoice fixtures, the policy documents, their generator `scripts/generate-demo-invoices.py` and the fixture tests `python/tests/test_demo_invoices.py` are already committed and only need to be found
- [X] T004 [P] Record the published-surface gate in the operator's guide `docs/interop-mcp/operations-guide.md`: the catalogue rebuild is followed by a restart of the MCP server, because the server loads the published surface when it starts and keeps it — without the restart a new tool does not reach the callers and a dropped tool stays invisible
- [X] T005 Run the published-surface contract on the unmodified gateway and confirm it is green: `python -m pytest python/tests/test_mcp_tool_surface.py -v` — this is the gate every later gateway change is measured against

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shapes the gateway publishes and the protection of the surface it already publishes

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 [P] Create the agent request class `src/br/musketeers/InteropMCP/Agent/Request.cls` — `Ens.Request` subclass with `Property Goal As %String [ Required ]`, the caller's goal in plain language; the published input schema is derived from this class by the existing schema mapper, so no special-casing is needed anywhere
- [X] T007 [P] Create the agent response class `src/br/musketeers/InteropMCP/Agent/Response.cls` — `Ens.Response` subclass with `Answer As %String`, `CapabilitiesUsed As %DynamicArray`, `Retrievals As %DynamicArray`, and `Status As %String` whose value is one of `completed`, `failed`, `held`, `blocked`
- [X] T008 Extend the catalogue entry in `src/br/musketeers/InteropMCP/Registry.cls` with a `kind` field whose value is `capability` or `agent`, so the catalogue builder can tell an agent entry from a business capability and the agent's own entry can be kept out of the agent's reachable scope
- [X] T009 Extend the generator in `src/br/musketeers/InteropMCP/Registry.cls` so it emits a `///` docstring above each generated method carrying the catalogue's `description` — the description of a tool is taken from the docstring of its method, which is why `MetaTools.CreateWorkflowTask` and `InvocationStatusTools.GetInvocationStatus` are described to callers and the generated business-capability tools are not; this makes the `AIGATEWAYDESC` annotation reach the MCP endpoint, and it adds information to the published surface without removing any
- [X] T010 Rebuild the catalogue and restart the MCP server, then confirm the published-surface contract is still green and that the business-capability tools now carry their annotations' descriptions: `python -m pytest python/tests/test_mcp_tool_surface.py -v`

**Checkpoint**: The gateway can carry an agent entry, the published surface is protected, and the existing tools are described. User story implementation can begin.

---

## Phase 3: User Story 1 - Give an existing production agentic capability with a document (Priority: P1) 🎯 MVP

**Goal**: An operator attaches a configurable input adapter to a production that
already works, writes a plain-language document that dictates the agent's rules,
and the agent is published on the MCP endpoint beside the production's business
capabilities and operates the production when handed a goal.

**Independent Test**: Attach the adapter to a production with at least two
published capabilities, write the agent's document, submit one goal in plain
language through the MCP endpoint, and observe a final answer plus a record
naming which production capabilities were invoked — with none of the
production's business classes modified.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T011 [P] [US1] Unit test for the agent adapter's declaration and validation in `tests/br/musketeers/InteropMCP/TestAgentAdapter.cls` — covering: the settings the data model names (`Prompt`, `Description`, `Model`, `ProviderConfig`, `AgentTools`, `MaxIterations`, `Timeout`, `KnowledgeBase`, `BusinessHost`); `Prompt` must not be empty; `MaxIterations` and `Timeout` must be positive when present; `ProviderConfig` must not carry a credential value; `BusinessHost` must name an enabled Business Service of the same production
- [X] T012 [P] [US1] Unit test for the agent host's request-to-answer flow in `tests/br/musketeers/InteropMCP/TestAgentHost.cls` — covering that a goal produces an answer, that the run is bounded, and that a failure is reported as a failure
- [X] T013 [P] [US1] Unit test for the catalogue builder's agent branch in `tests/br/musketeers/InteropMCP/TestRegistryCatalog.cls` — covering that an agent adapter item is published with `kind=agent`, that it points at the agent's Business Service config item and at the agent request class, that a disabled adapter is not published, and that a production with no agent publishes exactly what it published before
- [X] T014 [P] [US1] Integration test for the published agent tool in `python/tests/test_agent_tool.py` — covering that the agent appears in the tool list beside the capabilities, that its input schema is the single `goal` argument, and that a capability published before is still published and still executes

### Implementation for User Story 1

- [X] T015 [US1] Create the custom inbound adapter `src/br/musketeers/InteropMCP/Agent/Adapter.cls` extending `Ens.InboundAdapter` — the component the operator attaches to the production; it owns the agent's configuration and is the external-trigger face of the agent; its `BusinessHost` setting names the agent host
- [X] T016 [US1] Create the agent host `src/br/musketeers/InteropMCP/Agent/Host.cls` extending `Ens.BusinessService` — the entry point the gateway calls by production config item name, so the existing invoker, guardrail, approval, and audit path apply unchanged; it resolves the adapter's settings from the production, builds the agent, runs it, and returns the answer
- [X] T017 [US1] Create the agent builder `src/br/musketeers/InteropMCP/Agent/Builder.cls` — assembles the `%AI.Agent` from the adapter's settings: the model, the provider (with credentials referenced from the governed configuration store, never inline), the system prompt taken from the adapter's document, the reachable capability scope, the effort and time bounds, and the knowledge binding
- [X] T018 [US1] Teach the catalogue builder in `src/br/musketeers/InteropMCP/Registry.cls` to recognise an agent adapter item — publishing an entry with `kind=agent`, the agent's Business Service config item as the service name, the agent request class as the request class, and the adapter's `Description` as the published description
- [X] T019 [US1] Add the agent's item to the demonstration production `src/br/musketeers/InteropMCP/Demo/Production.cls` — one adapter item and one host item, both enabled, with the adapter's `BusinessHost` naming the host; the seven existing items are not touched
- [X] T020 [US1] Create the demonstration's agent host `src/br/musketeers/InteropMCP/Demo/AgentHost.cls` extending `br.musketeers.InteropMCP.Agent.Host` — the demonstration's own host, resolving the demonstration adapter's settings
- [X] T021 [US1] Log the adapter's configuration, the run's start and end, and the capabilities the agent selected, through `src/br/musketeers/InteropMCP/Log.cls` at the levels it already supports, so a run can be reconstructed from the logs alone
- [X] T022 [US1] Rebuild the catalogue, restart the MCP server, and confirm the published-surface contract stays green and the agent tool appears: `python -m pytest python/tests/test_mcp_tool_surface.py -v` and `python -m pytest python/tests/test_agent_tool.py -v`

**Checkpoint**: User Story 1 is fully functional — a production with an attached adapter gains a published agent that operates it, and nothing that was published before has changed.

---

## Phase 4: User Story 2 - Configure the agent without touching production business logic (Priority: P1)

**Goal**: The agent is configured entirely through the adapter's settings — most
importantly its document — with no annotation, parameter, or change to the
production's existing business classes.

**Independent Test**: Take a production whose business classes carry no
agent-related configuration, attach the adapter, set a document, and confirm the
agent reaches the production's capabilities and that the behaviour changes when
the document changes — without editing any business class.

### Tests for User Story 2 ⚠️

- [X] T023 [P] [US2] Unit test for the configuration's validation rules in `tests/br/musketeers/InteropMCP/TestAgentAdapter.cls` — covering each rejection the data model names, and that each rejection reports a diagnosable reason rather than failing silently
- [X] T024 [P] [US2] Unit test for the reachable capability scope in `tests/br/musketeers/InteropMCP/TestAgentBuilder.cls` — covering that an empty scope means every published capability of the production, and that a capability outside the scope is not reachable by the agent even when the agent attempts it
- [ ] T025 [P] [US2] Integration test for the non-invasive guarantee in `python/tests/test_agent_tool.py` — covering that attaching the agent leaves the published names and descriptions of the production's existing capabilities untouched, and that changing the agent's document changes the agent's behaviour on the next run without the production's components being redeployed

### Implementation for User Story 2

- [X] T026 [US2] Implement the configuration validation in `src/br/musketeers/InteropMCP/Agent/Adapter.cls` — reject an empty `Prompt` (the agent has no rules), a non-positive `MaxIterations` or `Timeout` (the bound is not usable), a `ProviderConfig` that carries a credential value (the credential must be referenced, not stored), and a `BusinessHost` that names no enabled Business Service of the production (the agent has no entry point); each rejection reports a diagnosable reason
- [X] T027 [US2] Implement the reachable scope in `src/br/musketeers/InteropMCP/Agent/Builder.cls` — an empty `AgentTools` means every published capability of the production, and a named list narrows it; the agent's own entry is always excluded so the agent cannot call itself
- [X] T028 [US2] Implement the hot revision in `src/br/musketeers/InteropMCP/Agent/Adapter.cls` — the agent's document is read from the adapter's settings at the start of each run, so a revision takes effect on the next run with no redeployment of the production's components
- [X] T029 [US2] Implement the provider resolution in `src/br/musketeers/InteropMCP/Agent/Builder.cls` — resolve the provider from the platform's governed configuration and secret store; the adapter's configuration must never carry a credential value
- [X] T030 [US2] Document the configuration surface in `docs/interop-mcp/operations-guide.md` — the settings an operator sets, what each one means, and what the operator does **not** have to do: annotate a business service class, modify an existing component, rewrite an integration, provision a second credential for the retrieval, or deploy a separate service

**Checkpoint**: User Stories 1 and 2 both work independently. The agent is fully configurable from the adapter alone, and the production's business classes are untouched.

---

## Phase 5: User Story 3 - Apply the production's written policies, retrieved on demand (Priority: P2)

**Goal**: The rules that govern the agent's decisions live in the production's
own written policies, which the agent retrieves on demand — finding a clause by
meaning, not by wording — and acts on.

**Independent Test**: Index the production's policies, run a goal where the
agent must apply a rule it was not given, and verify the agent retrieves the
clause and cites it; then ask the same policy a question in different words and
verify it still finds the right clause; then run with no policies indexed and
verify the agent still works and never claims to have consulted one.

### Tests for User Story 3 ⚠️

- [ ] T031 [P] [US3] Unit test for the knowledge base in `tests/br/musketeers/InteropMCP/TestAgentKnowledge.cls` — covering: indexing with a stable source identity; re-indexing a changed source so it replaces its previous content rather than accumulating alongside it; retrieval filtered by metadata so results narrow to the production; a retrieval that returns nothing reporting no supporting content; and the citation carrying the source document and the score
- [ ] T032 [P] [US3] Unit test for the retrieval as an agent capability in `tests/br/musketeers/InteropMCP/TestAgentBuilder.cls` — covering that the retrieval is attached to the agent as a capability it can call, and that an agent with no knowledge attached starts, answers, and completes successfully
- [ ] T033 [P] [US3] Integration test for retrieval by meaning in `python/tests/test_agent_knowledge.py` — covering that a question sharing no literal wording with the clause that answers it still finds that clause, and that the agent's answer identifies the rule it retrieved and the document it came from

### Implementation for User Story 3

- [ ] T034 [US3] Create the knowledge class `src/br/musketeers/InteropMCP/Agent/Knowledge.cls` — build the `%AI.RAG.KnowledgeBase` over the production's policies using the platform's local embedding provider (no outbound call, no second credential), and index the policies with stable source identities and metadata identifying their production and category
- [ ] T035 [US3] Attach the retrieval to the agent in `src/br/musketeers/InteropMCP/Agent/Builder.cls` — the knowledge base becomes a capability the agent calls during a run, with the retrieval's argument named `query`
- [ ] T036 [US3] Make the knowledge attachment optional in `src/br/musketeers/InteropMCP/Agent/Builder.cls` — an empty `KnowledgeBase` means no retrieval; the agent still runs, and it never claims to have consulted documentation it did not retrieve
- [ ] T037 [US3] Allow an operator to attach, extend, or detach the indexed knowledge without changing the agent's configuration or restarting the production, in `src/br/musketeers/InteropMCP/Agent/Knowledge.cls`
- [ ] T038 [US3] Index the demonstration's policies in `src/br/musketeers/InteropMCP/Demo/Setup.cls` — the three documents in `src/br/musketeers/InteropMCP/Demo/Policies/`, each with a stable source identity, at the production's start-up
- [ ] T039 [US3] Report the retrievals performed in the run's result envelope, with the source document and the score, in `src/br/musketeers/InteropMCP/Agent/Response.cls`

**Checkpoint**: User Stories 1, 2 and 3 work independently. The agent applies the production's own rules, retrieved by meaning, and the retrieval is optional.

---

## Phase 6: User Story 4 - Read documents in Embedded Python, reachable by the agent (Priority: P2)

**Goal**: The production's application layer carries a capability implemented in
Embedded Python that reads a supplier invoice document — work the platform's
native language does not provide — and the agent reaches it like any other
capability.

**Independent Test**: Put one Embedded-Python-implemented component into the
demo production's application layer, have the production call it on its own
normal path, and separately have the agent invoke it during a run; then point it
at a document it cannot read and verify the run reports failure.

### Tests for User Story 4 ⚠️

- [ ] T040 [P] [US4] Unit test for the document extraction in `tests/br/musketeers/InteropMCP/TestDemoInvoiceDetails.cls` — covering: the supplier's company identifier, the invoice number and the amount are all extracted from the document; a document that cannot be read is rejected; a document without the expected details is rejected rather than half-extracted; and a failing extraction surfaces as a failed run with a diagnosable reason, never as a successful outcome
- [ ] T041 [P] [US4] Integration test for the application's own use of the extraction in `python/tests/test_demo_invoice_extraction.py` — covering that the demonstration production's ordinary path uses the extracted details, not only the agent's path

### Implementation for User Story 4

- [ ] T042 [US4] Create the document-reading capability `src/br/musketeers/InteropMCP/Demo/InvoiceDetailsBS.cls` — a Business Service whose extraction runs as Embedded Python inside the platform's managed runtime, under the production's identity, with no separately deployed service; it reads the document at the demonstration's `DemoRoot` and extracts the supplier's company identifier, the invoice number and the amount
- [ ] T043 [US4] Reject an unreadable or incomplete document in `src/br/musketeers/InteropMCP/Demo/InvoiceDetailsBS.cls` — a document that cannot be read, or that does not carry the expected details, is rejected; the capability never returns a partially extracted result, and its failure reaches the agent as a failed run
- [ ] T044 [US4] Create the demonstration's restricted-list check `src/br/musketeers/InteropMCP/Demo/RestrictedCheckBS.cls` — the production's own business rule, in the native language, over the list the production owns
- [ ] T045 [US4] Create the demonstration's company-registry lookup `src/br/musketeers/InteropMCP/Demo/RegistryLookupBS.cls` — the production's own call to the external registry, in the native language, using the platform's native HTTP client; it returns the registration situation, the state and the opening date, and it fails loudly when the service cannot be reached
- [ ] T046 [US4] Create the demonstration's agent tool set `src/br/musketeers/InteropMCP/Demo/AgentTools.cls` — the capabilities the agent may reach in the demonstration, excluding the agent's own entry so the agent cannot call itself
- [ ] T047 [US4] Rebuild the catalogue and restart the MCP server so the demonstration's new capabilities are published, then confirm the published-surface contract is green: `python -m pytest python/tests/test_mcp_tool_surface.py -v`

**Checkpoint**: User Stories 1 through 4 work independently. The production reads real documents through Embedded Python, and the agent reaches that capability like any other.

---

## Phase 7: User Story 5 - Review and govern what the agent did (Priority: P3)

**Goal**: An operator reviews the history of agent runs — what each run was
asked, which capabilities it used, what it retrieved, how it ended — and actions
classified as requiring a human decision still require one.

**Independent Test**: Run the agent against a production containing one action
that requires human approval, then confirm the action was held, appears in the
approval queue, and that refusing it produces a reported block rather than a
silent retry or a silent success.

### Tests for User Story 5 ⚠️

- [ ] T048 [P] [US5] Unit test for the run record in `tests/br/musketeers/InteropMCP/TestInvocations.cls` — covering that each run records the goal, the identity, the outcome, the timing, the capabilities used and the retrievals performed, and that the agent's individual capability calls appear as their own invocation records
- [ ] T049 [P] [US5] Unit test for the approval hold on an agent-initiated critical action in `tests/br/musketeers/InteropMCP/TestGuardrails.cls` — covering that a capability classified as `critical` is held for approval rather than executed, that the agent is informed the action is pending, that a refused approval is reported as a block, and that the action is never recorded as executed before the decision
- [ ] T050 [P] [US5] Unit test for the health snapshot in `tests/br/musketeers/InteropMCP/TestHealth.cls` — covering that the snapshot reports the adapter's configuration state and the agent's availability

### Implementation for User Story 5

- [ ] T051 [US5] Record the agent run in the existing invocation store, in `src/br/musketeers/InteropMCP/Agent/Host.cls` and `src/br/musketeers/InteropMCP/Invoker.cls` — the run is the invocation of the agent tool; the goal is its parameters, the identity is its agent identity, the outcome is its status, the timing is its start and end, and the capabilities used and the retrievals performed travel in the result envelope. No second audit entity is introduced
- [ ] T052 [US5] Expose the run's detail through the existing status surface, in `src/br/musketeers/InteropMCP/InvocationStatusTools.cls` — the capabilities used and the retrievals performed must be readable per run, so a run can be diagnosed without reproducing it
- [ ] T053 [US5] Record the acting identity of the agent's capability calls in the production's own trace, in `src/br/musketeers/InteropMCP/Agent/Builder.cls` — the agent's calls must go through the published tools, so the existing guardrail, approval and invocation path applies to them unchanged
- [ ] T054 [US5] Extend the health snapshot in `src/br/musketeers/InteropMCP/Health.cls` with the adapter's configuration state and the agent's availability
- [ ] T055 [US5] Log every event the specification names at every supported level, in `src/br/musketeers/InteropMCP/Log.cls`: adapter configuration, run start and end, capability selection, retrieval, approval hold, and failure

**Checkpoint**: All five user stories are independently functional, and the agent's actions are reviewable and governed.

---

## Phase 8: Demonstration scenario (integration — not a user story phase)

**Purpose**: The bundled demonstration production, exercising every story together

**Independent Test**: Run the three demonstration runs in the specification and
confirm each produces the documented outcome.

- [ ] T056 [P] Create the demonstration's agent document in `src/br/musketeers/InteropMCP/Demo/Policies/` — a plain-language document that says to apply the production's policies rather than restating them, kept separate from the policies because they change for different reasons and are revised by different people
- [ ] T057 Wire the demonstration's agent together in `src/br/musketeers/InteropMCP/Demo/Setup.cls` — the adapter with its document and scope, the host, the agent tool set, and the indexed policies
- [ ] T058 Run the demonstration's restricted-supplier run — the agent reads the invoice, finds the company on the restricted list, requests human approval instead of assessing, and the risk assessment does not run; verify against the wiring in `src/br/musketeers/InteropMCP/Demo/Setup.cls` and the workflow inbox
- [ ] T059 Run the demonstration's in-good-standing run — the agent reads the invoice, looks the registration up, and assesses it; the answer names the supplier, the registration situation and the assessment, as wired in `src/br/musketeers/InteropMCP/Demo/Setup.cls`
- [ ] T060 Run the demonstration's grounding run — the agent finds the clause about a cancelled registration by meaning, applies it, and escalates citing the clause; and the policy-question run, answered from the policies indexed in `src/br/musketeers/InteropMCP/Demo/Setup.cls` with the citation
- [ ] T061 Run the demonstration's failure run — point the extraction in `src/br/musketeers/InteropMCP/Demo/InvoiceDetailsBS.cls` at a document that cannot be read and verify the run fails loudly rather than reporting an assessment with no findings
- [ ] T062 Confirm the published-surface contract after the demonstration's capabilities are published: `python -m pytest python/tests/test_mcp_tool_surface.py -v`

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T063 [P] Update `docs/interop-mcp/operations-guide.md` with the operator's guide for the agent: attaching the adapter, writing the document, indexing the policies, rebuilding the catalogue, and restarting the MCP server so the change reaches the callers
- [ ] T064 [P] Update `docs/interop-mcp/architecture.md` with the agent's position in the request lifecycle and the two audit planes it writes to
- [ ] T065 [P] Update `README.md` with the agent's entry in the feature list and the requirement for a configured model provider
- [ ] T066 [P] Update `docs/TODO.md` — remove the item asking for a less invasive way to declare a tool's exposure, which this feature delivers
- [ ] T067 Measure the line coverage of the `br.musketeers.InteropMCP` package and confirm it is at or above the project's 90 % gate, in `tests/br/musketeers/InteropMCP/`
- [ ] T068 Run the full validation guide in `specs/004-ai-agent-adapter/quickstart.md` — every scenario V0 to V8, with the published-surface contract green at the end
- [ ] T069 Run the whole test suite — `python -m pytest python/tests/ -v` and the ObjectScript suite `##class(%UnitTest.Manager).RunTest("tests/br/musketeers/InteropMCP", "/noload")` — and confirm it is green
- [ ] T070 [P] Verify the IPM package still installs cleanly with the new agent package — build the image from `Dockerfile`, load `module.xml`, and confirm the agent's classes are present in a fresh instance

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Stories (Phases 3–7)**: All depend on the Foundational phase
  - User Story 1 (P1) is the MVP and has no dependency on the others
  - User Story 2 (P1) depends on User Story 1 — it configures the adapter that
    User Story 1 introduces
  - User Stories 3 and 4 (P2) depend only on the Foundational phase and on the
    agent existing; they attach to the published agent
  - User Story 5 (P3) depends only on the Foundational phase
- **Demonstration (Phase 8)**: Depends on User Stories 1, 3 and 4
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational — no dependency on other stories
- **User Story 2 (P1)**: Starts after User Story 1 — it configures the adapter and the
  agent that User Story 1 introduces
- **User Story 3 (P2)**: Can start after Foundational — attaches a capability to the
  published agent; needs no change to the adapter
- **User Story 4 (P2)**: Can start after Foundational — adds capabilities to the
  production; needs no change to the adapter
- **User Story 5 (P3)**: Can start after Foundational — observes the agent's runs

### Within Each User Story

- Tests MUST be written and FAIL before the implementation they cover
- Models before services, services before endpoints
- Core implementation before integration
- A catalogue rebuild is always followed by a restart of the MCP server, and by
  the published-surface contract, before the story is called done
- Story complete before moving to the next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Once the Foundational phase completes, User Stories 1, 3, 4 and 5 can start in
  parallel; User Story 2 follows User Story 1
- All tests for a user story marked [P] can run in parallel
- The demonstration's policy document, the restricted-list check, the registry
  lookup and the invoice-reading capability are four different files and can be
  built in parallel
- The three Polish documentation tasks marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch the User Story 1 tests together:
Task: "Unit test for the agent adapter's declaration and validation in tests/br/musketeers/InteropMCP/TestAgentAdapter.cls"
Task: "Unit test for the agent host's request-to-answer flow in tests/br/musketeers/InteropMCP/TestAgentHost.cls"
Task: "Unit test for the catalogue builder's agent branch in tests/br/musketeers/InteropMCP/TestRegistryCatalog.cls"
Task: "Integration test for the published agent tool in python/tests/test_agent_tool.py"

# Launch the two independent implementation pieces together:
Task: "Create the custom inbound adapter in src/br/musketeers/InteropMCP/Agent/Adapter.cls"
Task: "Create the agent builder in src/br/musketeers/InteropMCP/Agent/Builder.cls"
```

## Parallel Example: User Story 4

```bash
# Four different files, no shared dependency:
Task: "Create the document-reading capability in src/br/musketeers/InteropMCP/Demo/InvoiceDetailsBS.cls"
Task: "Create the demonstration's restricted-list check in src/br/musketeers/InteropMCP/Demo/RestrictedCheckBS.cls"
Task: "Create the demonstration's company-registry lookup in src/br/musketeers/InteropMCP/Demo/RegistryLookupBS.cls"
Task: "Create the demonstration's agent tool set in src/br/musketeers/InteropMCP/Demo/AgentTools.cls"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational — the agent's shapes and the protection of the
   published surface
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: run the published-surface contract and the agent's
   independent test
5. Deploy or demo if ready

### Incremental Delivery

1. Setup + Foundational → the foundation, with the existing MCP already protected
2. User Story 1 → validate → demo — an existing production gains an agent that
   operates it
3. User Story 2 → validate → demo — the agent is fully configurable from a
   document, with the production untouched
4. User Story 3 → validate → demo — the agent applies the production's own rules
5. User Story 4 → validate → demo — the production reads real documents
6. User Story 5 → validate → demo — the agent's actions are reviewable
7. The demonstration → the three runs, end to end

### Parallel Team Strategy

With multiple developers:

1. The team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1, then User Story 2
   - Developer B: User Story 3
   - Developer C: User Story 4
   - Developer D: User Story 5
3. The stories complete and integrate independently, and every one of them is
   gated by the published-surface contract

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps a task to a specific user story for traceability
- Each user story is independently completable and independently testable
- Verify the tests fail before implementing
- The published-surface contract is the gate for every change to the gateway:
  nothing that was published before may disappear, and no input schema may change
- A catalogue rebuild is followed by a restart of the MCP server — the server
  loads the published surface when it starts and keeps it
- Commit after each task or logical group
- Stop at any checkpoint to validate the story independently
- Avoid: vague tasks, same-file conflicts, cross-story dependencies that break
  independence

---

## State of delivery (2026-11-13)

The MVP increment is delivered and green: 29 tasks marked done, 41 still open.
What the increment delivers, and what it does not, is written here so that the
next one starts from the truth.

### Delivered in this increment

- **The agent is published** on the MCP endpoint beside the production's
  capabilities, with the gateway's own naming, description, classification and
  guardrail path (T001-T022, US1).
- **The configuration is validated** before the agent is published: a missing
  document, a bound that is not positive, and a credential written in the
  configuration are each rejected with a reason, and a misconfigured agent is
  not published at all (T023, T026; FR-025).
- **The reachable scope** narrows what the agent may reach, and the agent's own
  entry is never in its own surface (T024, T027; D-05).
- **The document is hot**: the settings are read from the production at the
  start of every run (T028), and the provider's credential is referenced from
  the governed store, never written (T029; FR-053).
- **The operator's surface** is documented: the settings, what each one means,
  what the operator does *not* have to do, and the worker-pool sizing the
  agent needs (T030; FR-060).
- **A long run no longer takes the endpoint down**: the agent's catalogue entry
  is asynchronous, the call answers immediately with the run's invocation id,
  and the answer is collected through the existing status surface (FR-031,
  SC-017, SC-018; D-16).
- **A run no longer starves the production's other capabilities**: the
  demonstration's worker pools were sized for it, and the requirement is now
  explicit (FR-060, SC-019; D-18).

### Still open

- **T025** — the integration test for the non-invasive guarantee is covered by
  the published-surface contract (`python/tests/test_mcp_tool_surface.py`) and
  by the agent's own test; the half that is not covered is the *hot revision*
  observed end to end, which the next increment should assert by changing the
  document and running again.
- **T031-T039 (US3)** — vector search grounding: no knowledge base, no
  retrieval tool, no citation in the answer.
- **T040-T047 (US4)** — the Embedded-Python capability of the demonstration:
  the fixture invoices and policies are in the repository, the business service
  that reads them is not.
- **T048-T055 (US5)** — the run's detail in the status surface, the health
  snapshot and the log coverage beyond what the run already records.
- **T056-T062 (US6)** — the demonstration's runs: the restricted supplier, the
  supplier in good standing, the grounding run and the failure run.

### The deployment's availability defect (resolved)

The bridge re-discovered the endpoint periodically, and the discovery request
carried no credential of its own. The endpoint's service listing therefore
answered 401 to that request, and the bridge dropped its registration until the
next refresh: a window of about a second, every five minutes, in which the
tools were unreachable. The refresh is now off
(`tool_refresh_interval_secs = 0` in `config_http.toml`): the surface is
discovered per client connection, and a registration is never dropped by a
credential-less background request. The deployment's procedure for making a
rebuilt catalogue visible to callers is in
`specs/004-ai-agent-adapter/quickstart.md`, step 5.

### Corrections found while validating the increment (2026-11-13)

The increment was validated against the running endpoint, and the validation
found four defects in code that the unit tests had not reached. All four are
fixed, and the suites are green again (63 ObjectScript tests, 13 python tests
plus 3 skipped for missing optional fixtures).

- **The reachable scope was not narrowed.** `Registry.ParseScope` and
  `Registry.SplitLines` read the scope with `$FIND`, whose position in this
  build is *after* the match — the first character of every element was lost,
  and an agent's scope named `RiskCheck` could not reach it. Both now read
  with `$L`/`$P` (`src/br/musketeers/InteropMCP/Registry.cls`).
- **`Registry.InScope` ended the scope test with `Quit 1` inside a loop**,
  which this build rejects with ERROR #12 (`<INVALID SUBSCRIPT>`); it now
  carries the answer out of the loop and quits once.
- **An asynchronous service never reported its outcome.** The gateway records
  the invocation as `executing` and stops there; a service that runs longer
  than the response window owns the outcome of its own invocation and reports
  it through the request's `GatewayInvocationId`. The demonstration's
  `BatchRunBS` does this now, and the contract is documented in
  `docs/interop-mcp/operations-guide.md`, section 2.
- **The web app's entitlement contradicted the gateway's own design.** The
  entitlement is checked in the service, so that a caller without it receives
  a JSON 403 and an audit record; the app was additionally bound to the
  resource, which made the app itself refuse the caller before the gateway
  could answer. The app carries no resource (`src/br/musketeers/InteropMCP/Setup.cls`).

The elapsed-time bound was also carried into the agent's own session, so that it
bounds the run itself and not only the gateway's wait for it
(`src/br/musketeers/InteropMCP/Agent/Builder.cls`).
