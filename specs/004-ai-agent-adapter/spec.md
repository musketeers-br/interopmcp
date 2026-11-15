# Feature Specification: AI Agent Adapter for Interoperability Productions

**Feature Branch**: `004-ai-agent-adapter`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "quero criar um custom adapter para ser adicionado a uma iris interoperabiliry production e usar as capacidades agenticas do ai hub para disponibilizar um agente para operar a produção. seria um complemento ao uso atual do projeto que é para publicar productions em MCP. esse extensão iria tbm publicar um agente de IA para a produção no MCP, além de seus BS. esse adapter seria de entrada (acredito), com pelo menos um campo para o usuario especificar o prompt do agente. esse agente teria acesso a tudo da produção (analise governança mas precisamos entregar muito rapido, entao trabalhe com orientacao a mvp, onde o principal é demonstrar uso das caracteristicas agenticas do ai hub e criação de um custo adapter). alem disso tbm precisava cobrir o maixmo das seguintes tenologias do iris: Embedded Python, IRIS Vector Search aqui esta um repostiorio de exemplo de uso do ai hub: github.com/intersystems-community/ai-hub-dev-template#download-ai-hub-container"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Give an existing production agentic capability with a document (Priority: P1)

An integration engineer adds a single configurable input adapter to a production that
already works, and writes a plain-language document that tells the agent what it may do
and what it must never do. Nothing in the production's existing business logic is rewritten,
no business service class is annotated, and no new integration is written. From that moment
the production can be operated in plain language: the agent reads the request, decides which
of the production's own capabilities to use, acts through them, and reports what it did.

**Why this priority**: This is the whole promise of the feature. A production that already
runs becomes operable by an agent because somebody handed it a document, not because
somebody rewrote it. Everything else in the feature — the governance, the retrieval, the
documents the agent reads on the way — serves this.

**Independent Test**: Attach the adapter to a production with at least two published
capabilities, write the agent's document, submit one goal in plain language through the MCP
endpoint, and observe a final answer plus a record naming which production capabilities were
invoked. The production's business classes are not modified at any point.

**Acceptance Scenarios**:

1. **Given** a running production whose capabilities are published to the MCP endpoint, **When**
   the operator attaches an agent adapter to that production and writes the agent's document,
   **Then** the agent appears as an additional published entry while every previously published
   capability remains published and directly callable.
2. **Given** an attached agent adapter, **When** a caller submits a goal in plain language that
   requires the production's capabilities, **Then** the agent selects and invokes the required
   capability or capabilities and returns a final answer describing the outcome.
3. **Given** an attached agent adapter, **When** the agent runs, **Then** the answer reflects
   the goal that was submitted rather than a generic or empty result.
4. **Given** an attached agent adapter, **When** the agent selects a capability, **Then** the
   production processes that action exactly as it would for a direct caller, and the action is
   visible in the production's own operational trace.
5. **Given** a production that already works and has never been touched by this feature,
   **When** the operator attaches the adapter and writes the document, **Then** the production
   gains agentic capability without any of its existing components being modified.

---

### User Story 2 - Configure the agent without touching production business logic (Priority: P1)

An integration engineer configures the agent entirely through the adapter's settings — most
importantly the agent's prompt — and gets a working agent without adding a single annotation
or parameter to the production's existing business service classes. Two agents with different
prompts behave differently while sharing the same production.

**Why this priority**: The existing publication mechanism requires editing each business
service class to declare it publishable, and the maintainers have explicitly recorded that this
invasion is undesirable. A configuration-driven adapter is the reusable, least-invasive
extension point this project needs; it is a prerequisite for the agent to be usable at all,
not an enhancement.

**Independent Test**: Take a production whose business classes carry no agent-related
configuration, attach the adapter, set a prompt, and confirm the agent can reach the
production's capabilities and that the behaviour changes when the prompt changes — all without
editing any business class.

**Acceptance Scenarios**:

1. **Given** a production whose business classes contain no agent-specific configuration,
   **When** the operator attaches and configures the agent adapter, **Then** the production's
   capabilities become reachable by the agent and no business class is modified.
2. **Given** two agent adapters attached to the same production with different prompts,
   **When** each is exercised, **Then** each behaves according to its own prompt.
3. **Given** a configured agent adapter, **When** the operator changes the prompt,
   **Then** the change takes effect on the next run without the production's business logic
   being redeployed.
4. **Given** a configured agent adapter, **When** the operator inspects it, **Then** the
   operator can see the prompt, the model in use, the set of capabilities the agent may reach,
   and whether the agent is currently enabled.

---

### User Story 3 - Apply the production's written policies, retrieved on demand (Priority: P2)

A production's rules are written down as policies — when a supplier's registration
has been cancelled, when an invoice is large enough to need a human — and those
policies are held as documents the agent can search. The agent does not carry the
rules in its instructions: it retrieves the clause that applies to the situation in
front of it, in the wording the situation presents it, and acts on that clause.
Because the question the agent asks is its own, not the policy's, it finds the
clause even when it shares no literal wording with it.

**Why this priority**: Vector search is one of the two IRIS technologies the feature
is explicitly required to cover, and this is the use that earns its place: the rules
that govern the agent's decisions live outside the agent, so the agent must find
them. It ranks below the core stories because the agent must remain valuable for a
production that has written no policies at all — the retrieval is optional, the
ability to decide is not.

**Independent Test**: Index the production's policies, run a goal where the agent
must apply a rule it was not given, and verify the agent retrieves the clause and
cites it; then ask the same policy a question in different words and verify it
still finds the right clause; then run with no policies indexed and verify the
agent still works and never claims to have consulted one.

**Acceptance Scenarios**:

1. **Given** the production's policies indexed, **When** the agent faces a situation
   that one of the policies governs, **Then** it retrieves the clause that applies,
   acts on that clause, and names the clause in its answer.
2. **Given** the agent asked about a rule in wording that shares no literal words
   with the policy that states it, **When** it searches the policies, **Then** it
   still finds the right clause.
3. **Given** an agent with no policies indexed, **When** it runs, **Then** it still
   answers using the production's capabilities and does not claim to have consulted
   a policy.
4. **Given** a question that no policy answers, **When** the agent answers, **Then**
   it states that it has no documented basis rather than inventing one.
5. **Given** a policy document that changed, **When** it is re-indexed, **Then** the
   stored knowledge reflects the new content instead of the old content appearing
   alongside it.
6. **Given** several productions share one retrieval store, **When** the agent
   retrieves knowledge, **Then** results are narrowed to the knowledge attached to
   that agent's own production.

---

### User Story 4 - Read documents in Embedded Python, reachable by the agent (Priority: P2)

A developer implements the production's document-reading capability in Embedded Python — in the
demonstration, extracting a supplier's details from an invoice document — so the production
carries a real Python-implemented component in its application layer, not merely a Python
wrapper around the agent. That component runs when the production needs it on its own normal
path, the agent reaches it the same way it reaches any other capability and uses its result,
and when a document cannot be read the run ends in failure with a diagnosable reason rather
than reporting a false clean result.

**Why this priority**: Embedded Python is the second IRIS technology the feature is explicitly
required to cover, and the point of covering it is to show Python actually running inside the
application layer of a production — not only as an implementation detail of the agent itself.
It ranks below the core stories because the agent must remain valuable for a production that
chooses not to adopt Python at all.

**Independent Test**: Put one Embedded-Python-implemented component into the demo production's
application layer - in the demonstration, the extraction of a supplier's details from an
invoice document - have the production call it on its own normal path, and separately have
the agent invoke it during a run; then point it at a document it cannot read and verify the
run reports failure rather than a clean result.

**Acceptance Scenarios**:

1. **Given** a production whose application layer contains a capability implemented in
   Embedded Python, **When** the production processes an ordinary request that needs it,
   **Then** the Python-implemented component runs and its result is used — the component is
   part of the application, not only reachable through the agent.
2. **Given** a capability implemented in Embedded Python and reachable by the production,
   **When** the agent's goal requires it, **Then** it is invoked and its result is used in the
   answer.
3. **Given** an Embedded-Python capability that raises an error, **When** the agent runs,
   **Then** the run ends with a failure status carrying a diagnosable reason, and is not
   reported as success.
4. **Given** a document the Embedded-Python capability cannot read, **When** the agent runs,
   **Then** the run ends in failure, and is never reported as an assessment with no findings.
5. **Given** an Embedded-Python capability, **When** the agent invokes it, **Then** it runs
   inside the platform's managed runtime under the production's identity — no separately
   deployed service is required to host it.

---

### User Story 5 - Review and govern what the agent did (Priority: P3)

An operator reviews the history of agent runs to see what each run was asked, which production
capabilities it used, what it retrieved, and how it ended. Actions classified as requiring a
human decision still require one: the agent's attempt is held for approval, the agent is told
the action is pending, and when the decision is refused the agent stops retrying and reports
the block.

**Why this priority**: An agent that can act on a production without a reviewable trail and
without the existing approval gate would be unsafe to enable, so this story is a genuine
requirement — but it can be delivered after the agent demonstrably works, because it extends
an approval mechanism that already exists in the project rather than introducing one.

**Independent Test**: Run the agent against a production containing one action that requires
human approval, then confirm the action was held, appears in the approval queue, and that
refusing it produces a reported block rather than a silent retry or a silent success.

**Acceptance Scenarios**:

1. **Given** a completed agent run, **When** an operator reviews the run history, **Then** the
   goal, the responsible identity, the capabilities used, the retrievals performed, the
   outcome, and the timing are all recorded.
2. **Given** a production capability classified as requiring human approval, **When** the agent
   attempts to use it, **Then** the action is held for approval rather than executed, and the
   agent is informed that the action is pending.
3. **Given** a refused approval, **When** the agent continues, **Then** it does not retry the
   same action indefinitely and reports the block in its answer.
4. **Given** an operator who disables the agent, **When** the agent is exercised afterwards,
   **Then** it is no longer published and the production's individual capabilities remain
   published and callable.

### Demonstration scenario - bundled demo production

The bundled demonstration production is the vehicle used to show the feature working. It is
not part of the feature's contract, and the same adapter applies unchanged to any other
production. The scenario repeats, inside the production, the restricted-company example that
the project's first tutorial demonstrates from outside the gateway, so that the two can be
compared side by side.

**Setup**

1. The demonstration production gains one new component - the agent adapter - carrying the
   operator's prompt, the model to use, and the set of capabilities the agent may reach. No
   existing capability of that production is altered.
2. The production owns the list of restricted companies that the tutorial keeps in a file
   beside the client. The list is read from the production's own storage, so the agent and
   the production can never disagree about which companies are restricted.
3. The demonstration production gains one application-layer capability implemented in
   Embedded Python that reads a supplier invoice document and extracts the details the
   production needs from it - the supplier's company identifier, the invoice number, the
   amount. Reading text and structure out of a document is work the platform's native
   language does not provide.
4. The demonstration production's rules are written down as policy documents - the
   escalation rules, the restricted-list policy, the supplier admission policy - and those
   documents are indexed so the agent can retrieve the clause that applies. The agent's
   instructions therefore say to apply the production's policies, not what those policies
   say.
5. The production's own calls to the external company registry stay in the native language,
   where the platform provides them natively.
6. The MCP endpoint gains one new published entry for the agent, alongside the existing
   entries for the demonstration production's capabilities, which stay exactly as they were.

**The agent's document** - a plain-language document that the operator writes, and that the
agent obeys. It is not the rules themselves; it says to apply the production's policies.

> You are a risk analyst operating this production. When you are given a supplier invoice,
> read it and identify the supplier. Before assessing any company, check whether it appears
> on the restricted list. If it does, request human approval for the risk assessment instead
> of running it, and report that the request is pending. If it does not, look up the
> company's registration and assess it. Never rely on remembered identifiers - always read
> the document and check the list.

**The production's own documents** - the policies the agent is told to apply, which are
retrieved rather than quoted, and which are separate from the agent's document because they
change for reasons of their own: a policy changes when the organisation changes its rules,
an agent's document changes when its job changes.

**Run 1 - a restricted supplier**

```
Caller (MCP): "assess the risk of the supplier on invoice INV-2026-118.pdf"

  -> tool "Agent" -> agent adapter -> agent
      -> capability "read the invoice details"    -> CNPJ 98.765.432/0001-98,
                                                       invoice 2026-118,
                                                       amount 3433.35      (Embedded Python)
      -> capability "is this company restricted?" -> true
      -> capability "request human approval"      -> approval raised
      -> answers: "Invoice 2026-118 is from company 98.765.432/0001-98, which is on
                   the restricted list. The risk assessment is pending human approval."
```

The risk assessment itself does not run. A task appears in the operator's workflow inbox, and
the agent's answer says the request is pending rather than reporting a result.

**Run 2 - a supplier in good standing**

```
Caller (MCP): "assess the risk of the supplier on invoice INV-2026-119.pdf"

  -> tool "Agent" -> agent adapter -> agent
      -> capability "read the invoice details"     -> CNPJ 63.212.233/0001-78,
                                                        invoice 2026-119,
                                                        amount 890.00      (Embedded Python)
      -> capability "is this company restricted?"  -> false
      -> capability "company registration record"  -> active, micro company, Olimpia/SP
      -> capability "risk assessment"              -> approved, clear
      -> answers: "Invoice 2026-119 is from company 63.212.233/0001-78, which is not
                   restricted. Its registration is active in Olimpia/SP. Assessment
                   approved, result clear."
```

**Run 3 - a supplier whose registration is not in good standing**

```
Caller (MCP): "assess the risk of the supplier on invoice INV-2026-120.pdf"

  -> tool "Agent" -> agent adapter -> agent
      -> capability "read the invoice details"     -> CNPJ 12.345.678/0001-95,
                                                        invoice 2026-120,
                                                        amount 12400.00    (Embedded Python)
      -> capability "is this company restricted?"  -> false
      -> capability "company registration record"  -> cancelled, micro company, Sao Vicente/SP
      -> capability "search the production's policies"
             query: "a empresa esta com o registo cancelado?"
             -> clause 3.2 of the risk policy:
                "O registo cadastral da empresa encontra-se com a situacao BAIXADA...
                 a fatura fica pendente de aprovacao humana antes de qualquer pagamento"
                score 0.599
      -> the agent applies the clause it retrieved, which requires human approval,
         so it requests it rather than assessing directly
      -> answers: "Invoice 2026-120 is from company 12.345.678/0001-95, which is not
                   on the restricted list, but whose registration is cancelled. Clause 3.2
                   of the risk policy requires human approval in this case, so the
                   assessment is pending."
```

This run is the one the demonstration exists to make possible, and it needs two
technologies to work together. The production's own risk assessment today answers
"Approved" and "Clear" for every company it is given, so without real registration
data there would be nothing for the agent to judge; and the rule that turns that
observation into an escalation is not in the agent's instructions — it is in a
document the agent has to find. Note the query the agent issued: "a empresa esta com
o registo cancelado?" shares no literal wording with the clause it found, which
speaks of "registo cadastral" and "situacao BAIXADA". A keyword search would have
missed it.

**What the comparison with the tutorial shows**

| | Tutorial, agent outside the gateway | This feature, agent inside the production |
|---|---|---|
| Where the restricted list lives | a file beside the client | the production's own storage |
| Who applies the rule | the client-side agent, from a prompt | the agent inside the production, from the same rule |
| Who asks for human approval | the client-side agent | the agent in the production, through the same approval route |
| Where it leaves a trace | the gateway's audit plane only | the gateway's audit plane and the production's own trace |
| What happens if the list changes | the client must be updated | the production's list is updated, and the agent follows |
| What the agent decides on | the restricted list alone | the restricted list, the supplier's real registration data, and the production's own written rules |

**A fourth run, a question the policies answer**

```
Caller (MCP): "what do I need from a new supplier before I can pay their invoices?"

  -> tool "Agent" -> agent adapter -> agent
      -> capability "search the production's policies"
             query: "que documentos sao precisos para admitir um fornecedor"
             -> "Registo cadastral ativo... Contrato assinado... Certidao de
                 regularidade fiscal... Comprovativo de IBAN..."
      -> answers with the four documents, citing the supplier admission policy
```

This is the same mechanism as Run 3, asked as a question rather than as an action. It
is also optional: with no policies indexed, the agent cannot answer it, and says so
rather than inventing an answer.

### Edge Cases

- What happens when the adapter's prompt field is left empty?
- What happens when the model provider or its credentials are not configured?
- What happens when the agent reaches its effort limit or its time budget before finishing?
- What happens when the agent selects no production capability at all and answers from the
  prompt alone?
- What happens when two agent adapters in the same production would publish under the same
  name?
- What happens when a capability the agent needs is disabled while a run is in progress?
- What happens when the agent's question spans knowledge that has not been indexed?
- What happens when a run is submitted while the same production is being reconfigured?
- What happens when the agent calls the same capability repeatedly with the same arguments?
- What happens when the model provider is unreachable or returns an error mid-run?
- What happens when the company identifier the agent checks is malformed, or is written with
  different punctuation than the restricted list uses?
- What happens when the restricted list is empty, missing, or contains a malformed entry?
- What happens when the agent decides a restricted company needs approval, but the approval
  request itself cannot be raised?
- What happens when the external registry cannot be reached, times out, or returns an error?
- What happens when the registry reports that the company identifier is well-formed but unknown
  to it?
- What happens when the registry is reachable but returns a record the production cannot
  interpret?
- What happens when the invoice document cannot be read, is not a document at all, or is
  protected?
- What happens when the invoice document is a scanned image with no selectable text?
- What happens when the invoice document is readable but does not carry the details the
  production needs?
- What happens when two different documents name the same supplier inconsistently?

## Requirements *(mandatory)*

### Functional Requirements

**Agent adapter**

- **FR-001**: System MUST provide a configurable input adapter that can be added to an
  interoperability production and that accepts a caller-supplied goal as its input.
- **FR-002**: The adapter MUST expose at least one configuration field in which the operator
  specifies the agent prompt that governs the agent's role and instructions.
- **FR-003**: The adapter MUST expose configuration for the language model to use, the identity
  under which the agent's actions are recorded, and the maximum effort and elapsed time allowed
  per run.
- **FR-004**: The adapter MUST allow the operator to scope which of the production's published
  capabilities the agent may use; the default scope MUST be all published capabilities of that
  production.
- **FR-005**: Attaching and configuring the agent MUST NOT require modifications to the
  production's existing business classes.
- **FR-006**: The adapter MUST be enableable and disableable by the operator without removing
  the production's individual capabilities from publication.
- **FR-007**: The adapter's configuration MUST be validated when the adapter starts, and an
  invalid or incomplete configuration MUST be reported with a diagnosable reason rather than
  failing silently at run time.
- **FR-008**: The agent's instructions MUST be expressible as a plain-language document that
  an operator writes and revises, and attaching or revising that document MUST NOT require any
  change to the production's existing components or to anything beyond the adapter's own
  settings.
- **FR-009**: The system MUST allow the operator to revise the agent's document and see the
  change take effect on the next run without the production's components being redeployed.

**Agent execution**

- **FR-010**: System MUST create and run the agent using the platform's AI Hub agentic
  capabilities rather than a bespoke orchestration of its own.
- **FR-011**: The agent MUST be able to invoke the production's published capabilities as
  tools it chooses among, including invoking several of them in sequence within a single run.
- **FR-012**: The agent MUST return a final answer to the caller that reflects the outcome of
  the actions it took.
- **FR-013**: The system MUST record each agent run with its goal, the adapter and production
  it belongs to, the responsible identity, the capabilities used, the retrievals performed, the
  outcome, and the start and end times.
- **FR-014**: The agent MUST respect the platform's existing action-classification and human
  approval rules: a capability classified as requiring approval MUST NOT take effect without an
  explicit human decision, and the agent MUST be informed that the action is pending.
- **FR-015**: The system MUST bound every run by the configured effort and time limits and MUST
  end the run with an explicit recorded outcome when a bound is reached.
- **FR-016**: The system MUST apply the same per-capability authorization rules to
  agent-initiated actions as to actions initiated directly by a caller.
- **FR-017**: The system MUST record the acting identity of agent-initiated capabilities in the
  production's own operational trace, so that the production's history shows which run caused
  which action.
- **FR-018**: The agent's authority over the production's capabilities MUST be governed by the
  same action-classification scheme the gateway already applies to directly invoked
  capabilities — read-only, write, and critical — so that an agent-initiated action is
  classified exactly as the equivalent direct action would be.
- **FR-019**: In the first release the agent MUST reuse the gateway's existing action
  classification and human-approval gate unchanged, and MUST NOT introduce a new
  per-capability authority mechanism. Extending the authority model with finer-grained
  per-capability rules is deferred to a later iteration; the first release SHOULD merely keep
  the point where such a mechanism would be introduced identifiable, so that adding it later
  does not require redesigning the adapter, the agent, or the publication surface.
- **FR-020**: The agent MUST execute inside the production it is attached to, so that the
  production owns the agent's lifecycle, configuration, and routing; exposing the agent to
  external callers MUST NOT move the agent out of the production.
- **FR-021**: The adapter and the agent it carries MUST be applicable to any interoperability
  production without modification, so that neither the adapter nor the agent is tied to the
  demonstration production shipped with this project.

**Publication to MCP**

- **FR-022**: The MCP endpoint MUST publish the agent as an additional tool alongside the
  production's individual capabilities, and the published agent MUST be presented to callers in
  the same manner as the published capabilities.
- **FR-023**: The published agent tool MUST accept the caller's goal as its input and MUST
  describe, in its published description, the purpose the configured prompt gives the agent,
  so that a caller can discover what the agent is for.
- **FR-024**: Attaching an agent MUST NOT remove, rename, or alter the published entries of the
  production's individual capabilities.
- **FR-025**: The gateway MUST NOT publish an agent whose adapter is disabled, misconfigured,
  or not part of a running production.
- **FR-026**: The published name of the agent MUST follow the gateway's existing naming
  conventions and MUST NOT collide with any other published tool.
- **FR-027**: The gateway MUST expose the agent's run history through the gateway's existing
  status and history surface, using the same shape it already returns for other invocations.
- **FR-028**: The published surface of a production that attaches no agent MUST be identical
  to the surface it published before this feature existed — the same tools, with the same
  names and the same input schemas — so that the change to the catalogue builder cannot be
  observed by the callers that were already being served.
- **FR-029**: A change to the published catalogue MUST become visible to the callers of the
  endpoint, and the procedure that makes it visible MUST be part of the operator's guide.
- **FR-030**: The regression contract over the published surface MUST be executable, not only
  documented: the tools published before this feature existed, with their names and their
  input schemas, MUST be recorded in the repository and checked automatically.
- **FR-031**: A published agent tool MUST NOT hold the caller's connection open for longer
  than the transport that carries it tolerates. An agent run that outlasts that window MUST
  be reported to the caller as a processing reference, with the answer retrievable
  afterwards through the gateway's existing status surface. A run that completes after the
  caller has given up MUST still be recorded, with its answer.

**Vector search knowledge**

- **FR-032**: The system MUST support retrieving production knowledge using the platform's
  vector search capability, so that the agent can ground its answers in indexed material.
- **FR-033**: The system MUST provide a way to index source documents into the retrieval store
  with a stable source identity, and to re-index a changed source so that it replaces its
  previous content rather than accumulating alongside it.
- **FR-034**: The agent MUST be able to use vector-based retrieval as a capability during a run,
  and the retrieval MUST match by meaning, so that a question sharing no literal wording with
  the passage that answers it still finds it.
- **FR-035**: Retrieval MUST be filterable by metadata so that results can be narrowed to the
  production, document set, or category the agent is working with.
- **FR-036**: The system MUST be able to report that a retrieval returned no supporting content,
  so that the agent can state it has no documented basis.
- **FR-037**: The agent MUST be able to cite or otherwise identify the source of material it
  used in its answer.
- **FR-038**: Vector search MUST be used in the first release for grounding the agent's answers
  in indexed production knowledge only; using similarity matching to route an incoming goal onto
  a production capability is NOT part of the first release.
- **FR-039**: The attachment of indexed knowledge MUST be optional. An agent with no knowledge
  attached MUST start, run, and answer successfully, and MUST NOT claim to have consulted
  documentation it did not retrieve.
- **FR-040**: The system MUST allow an operator to attach, extend, or detach a production's
  indexed knowledge without changing the agent's configuration or restarting the production.
- **FR-041**: The rules that govern the agent's decisions MUST be able to live in the
  retrievable knowledge rather than only in the agent's instructions, so that the agent can
  act on a rule it was not given and can be corrected by correcting the rule.

**Embedded Python capabilities**

- **FR-042**: The system MUST support capabilities implemented in Embedded Python inside the
  platform and callable from the production's own runtime.
- **FR-043**: The production's application layer MUST be able to contain capabilities
  implemented in Embedded Python, invoked by the production's normal business routing and not
  only by the agent.
- **FR-044**: The agent MUST be able to reach an Embedded-Python-implemented application-layer
  capability through the same route it uses for any other capability, and use its result.
- **FR-045**: A failing Embedded-Python capability MUST surface as a failed run carrying a
  diagnosable reason and MUST NOT be reported as a successful outcome.
- **FR-046**: Python code the agent runs MUST execute inside the platform's managed runtime
  under the production's identity and control; the first release MUST NOT require a separately
  deployed Python service to host agent capabilities.
- **FR-047**: The bundled demonstration production MUST carry at least one application-layer
  capability implemented in Embedded Python, exercised both by the production's own routing and
  by the agent, so that the first release demonstrates the technology end to end rather than
  merely making it possible.
- **FR-048**: The demonstration production's Embedded-Python capability MUST perform work that
  the platform's native language does not provide - in the demonstration, the extraction of a
  supplier's details from an invoice document - and MUST NOT be work the native language
  performs comfortably or natively, such as string handling, file reading, arithmetic, or
  making an HTTP request.
- **FR-049**: The division of labour between the platform's native language and Embedded
  Python MUST follow the project's constitution: business rules stay in the native language,
  and Embedded Python carries the integration itself.
- **FR-050**: An Embedded-Python capability that cannot read what it was given, or that
  fails, MUST fail loudly. It MUST NOT report a successful, empty, or permissive result, so
  that an unreadable document or an erroring service can never be mistaken for a clean
  outcome.
- **FR-051**: The demonstration MUST ship the supplier invoice documents the demonstration
  reads, and the production's own normal path MUST use the details extracted from them, so
  that the extraction capability is part of the application rather than a demonstration
  performed only for the agent.
- **FR-052**: The demonstration's invoice documents MUST be generated from a committed
  generator rather than hand-made, and the generator MUST refuse to emit a document whose
  company identifier has invalid check digits or whose total disagrees with its line items,
  so that a fixture can never drift away from what the demonstration depends on.

**Security and governance**

- **FR-053**: Model provider credentials MUST NOT be stored in clear text in the adapter's
  configuration; they MUST be referenced from the platform's governed secret and configuration
  store.
- **FR-054**: The system MUST apply the gateway's existing authentication and entitlement
  decisions to agent publication, so that an unauthorised caller cannot reach an agent that
  they could not reach the production's capabilities through.
- **FR-055**: The system MUST record, for every agent-initiated capability invocation, the
  capability, the run that caused it, the identity under which it ran, and its outcome.
- **FR-056**: The agent MUST NOT be able to reach capabilities that the operator has excluded
  from its scope, even if the agent attempts to.

**Observability**

- **FR-057**: The system MUST emit structured logs at every supported level for adapter
  configuration, run start and end, capability selection, retrieval, approval hold, and
  failure.
- **FR-058**: The system MUST expose health information covering adapter configuration state and
  agent availability.
- **FR-059**: The system MUST expose, per run, the capabilities used and the retrievals
  performed, so that an operator can diagnose a run without reproducing it.

**Concurrency with the production's other capabilities**

- **FR-060**: An agent run MUST NOT prevent the production's other capabilities from being
  served while it runs. The production's worker pool MUST be able to serve a run in progress
  and the other capabilities at the same time, so that attaching an agent to a production does
  not narrow the capacity the production already offered its callers.

### Key Entities

- **Agent Adapter**: The configuration that attaches an agent to a production. Attributes:
  name, production, prompt, model and provider reference, reachable capability scope,
  iteration and time limits, acting identity, attached knowledge set (optional), enabled state.
- **Agent Run**: One execution of the agent against one goal. Attributes: goal, adapter,
  production, identity, status (completed, failed, held, blocked), capabilities used,
  retrievals performed, final answer, start and end times, failure reason.
- **Capability**: A callable business capability of the production as published to clients.
  Attributes: published name, description, action classification (read-only, write, critical),
  owning production. The agent reaches capabilities through this same concept that clients call
  directly, and an agent-initiated call is classified as the equivalent direct call would be.
- **Knowledge Source**: A document made available to the agent for retrieval. Attributes: stable
  source identity, content, metadata identifying its production and category, indexed-at time.
  Knowledge sources are optional: a production may have none.
- **Registration Record**: What an external registry reports about a company. Attributes:
  company identifier, registration situation, state, opening date, retrieved-at time. A
  production that consults an external service obtains this; the rules that judge it are the
  production's own.
- **Invoice Document**: A supplier invoice the production reads. Attributes: document identity,
  supplier company identifier, invoice number, amount, and whether the details were extracted
  successfully or the document was rejected.
- **Approval**: A pending human decision that an agent-initiated action triggered. Attributes:
  requested action, capability, reason, decision, decider, decided-at time. Existing concept,
  reused for agent actions.
- **Tool Entry**: A published entry in the MCP catalogue. Attributes: name, description,
  classification, kind (capability or agent), owning production. Existing concept, extended to
  carry agent entries.
- **Published Surface Baseline**: The record of what the MCP endpoint published before this
  feature existed — the tools, their names, and their input schemas — held in the repository
  and checked automatically. It is the contract that a change to the catalogue builder cannot
  break, and it may only grow: a tool that was published before must survive, and a
  description that existed may only be enriched.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can go from an unmodified production to a callable agent published in
  the MCP endpoint in under 30 minutes, without editing the production's business classes.
- **SC-002**: In at least 9 of 10 consecutive runs, the agent selects and invokes the
  production capability needed to satisfy the goal without the caller naming that capability.
- **SC-003**: 100 % of agent-initiated capability invocations appear in the production's
  operational trace carrying the identity of the run that caused them.
- **SC-004**: In at least 90 % of runs where a written rule applies to the situation, the
  agent's answer identifies the rule it retrieved and the document it came from.
- **SC-005**: A run that reaches its effort or time bound ends within 2 minutes of that bound
  being reached, with an explicit outcome recorded and no run left in progress.
- **SC-006**: 100 % of agent runs are retrievable in the run history with goal, identity,
  capabilities used, retrievals performed, and outcome.
- **SC-007**: The bundled demonstration production carries at least one application-layer
  capability implemented in Embedded Python - the invoice detail extraction. That capability
  runs on the production's own normal path, the agent invokes it within a run, the supplier's
  identifier, invoice number, and amount are all extracted from a real document, a document
  that cannot be read causes a failed run rather than a reported success, and a document
  without the expected details is rejected rather than half-extracted.
- **SC-008**: Attaching an agent to a production changes none of the published names or
  descriptions of that production's existing capabilities, verified by comparing the published
  catalogue before and after.
- **SC-009**: A caller who lacks entitlement to the production's capabilities cannot reach the
  agent that fronts them.
- **SC-010**: The agent adapter and its publication are exercised successfully against a
  production other than the demonstration production shipped with this project, with no change
  to the adapter's implementation.
- **SC-011**: An agent with no indexed knowledge attached starts, answers a goal using the
  production's capabilities, and completes successfully — the first release does not require a
  knowledge base to be stood up.
- **SC-012**: An agent-initiated action on a capability classified as critical is held for a
  human decision in 100 % of attempts, and is never recorded as executed before that decision.
- **SC-013**: An agent attached to a production that contains no Python-implemented capability
  starts, answers, and completes successfully, proving the Embedded Python coverage is an
  available option rather than a dependency.
- **SC-014**: The published tool surface of a production that attaches no agent is identical,
  entry for entry, to the surface captured before this feature existed — same names, same
  input schemas — and the check that enforces this runs as part of the test suite.
- **SC-015**: A capability that was published before this feature existed still executes
  successfully through the MCP endpoint after the feature is added.
- **SC-016**: A catalogue rebuild becomes visible to the callers of the endpoint without the
  gateway's source being changed, using the procedure the operator's guide documents.
- **SC-017**: An agent run that outlasts the transport's response window leaves the caller
  with a processing reference rather than a failed call, and its answer is retrievable
  through the status surface once the run completes.
- **SC-018**: An agent run of realistic length - a reasoning model making several calls -
  completes and its answer is retrievable, in 100 % of runs, whether or not the caller was
  still waiting.
- **SC-019**: While an agent run is in progress, the production's other capabilities remain
  callable through the same endpoint and complete within the transport's response window, so
  that attaching an agent does not make the endpoint unavailable to the callers it already
  served.

## Assumptions

- The feature is delivered with MVP orientation: the primary purpose is to demonstrate the AI
  Hub's agentic capabilities driving a real production and to establish a reusable
  custom-adapter pattern. Depth of governance polish is deliberately deferred to later
  iterations.
- The deployment provides the AI Hub runtime, with agent, model provider, and vector search
  capabilities available, as in the AI Hub development template base image the project already
  builds on.
- The existing gateway's discovery, publication, guardrail, approval, and audit machinery is
  reused and extended rather than replaced.
- The agent is implemented by the custom adapter and runs inside the production it is attached
  to; the production owns the agent's lifecycle, configuration, and routing. Publishing the
  agent to MCP projects the production's own agent outward and does not relocate it.
- The agent is additive to publication: the production's individual capabilities stay
  published and directly callable.
- External callers reach the agent through an entry point that the gateway already knows how
  to invoke, so that the existing publication, guardrail, approval, and audit path is reused
  rather than bypassed. A production gains a new entry point for this; no existing
  capability's publication is altered.
- The agent adapter is the single owner of the agent's configuration - prompt, model, reachable
  capability scope, effort and time limits - and the production's entry point for the agent
  supplies only the goal to be pursued. One configuration therefore serves every caller of the
  agent, whether it arrives through the gateway or through a direct production trigger, and
  changing the agent's behaviour means changing one place.
- The agent's default scope is every published capability of its own production; restricting
  scope is an operator opt-in.
- The agent's authority in the first release follows the gateway's existing action
  classification (read-only, write, critical): it holds full authority within its scope, and
  the existing approval gate is its only brake. Finer-grained authority is a later iteration,
  and the model is expected to accommodate it without redesign.
- Embedded-Python capabilities are implemented as methods of platform classes written in
  Python and invoked from the production's own runtime, which is the platform's canonical
  pattern; no separately deployed Python service is introduced.
- Embedded Python is used for work the platform's native language does not provide - reading
  text and structure out of documents - and the platform's native language carries everything
  else, including the business rules that consume what was read and the production's own calls
  to external services. This follows the project's constitution, which assigns IRIS business
  logic to the native language and services and integration to Python.
- The demonstration production's Embedded-Python capability reads supplier invoice documents
  held by the production. Reading a document that carries selectable text is assumed;
  recognising text in a scanned image is not, and is a documented extension point rather than
  a first-release requirement.
- The production's lookups against the external company registry reach the network. The
  demonstration therefore depends on that service being reachable from the deployment; the
  dependency is explicit, and an unreachable service makes the capability fail loudly rather
  than report a clean result.
- The demonstration's company identifiers are real identifiers with real registry records, so
  that the agent's judgement rests on actual data rather than on fixtures.
- Vector search is used to ground the agent in the production's own written rules, and the
  knowledge attachment is optional: an agent with no indexed knowledge is fully functional.
- The embeddings in the demonstration are produced by a provider that runs inside the
  platform, so the demonstration needs no second credential and makes no outbound call to
  embed or to retrieve. The retrieval is a capability the agent calls like any other.
- The demonstration's policies are held as plain documents that the production indexes at
  start-up, and the same documents are the ones the agent quotes, so that a rule change is a
  document change and a re-index, not a prompt change.
- The demonstration separates the two kinds of document deliberately: the agent's own
  document states what the agent may do, and the policies state what the rules are. Keeping
  them apart is what allows one to be revised by an operator and the other by the business.
- The demonstration production shipped with this project is a demonstration vehicle only. The
  adapter, the agent, and the publication of both are expected to apply unchanged to any other
  interoperability production.
- In the demonstration, the list of restricted companies moves from the file the tutorial
  keeps beside the client into the production's own storage, so that the production is the
  single source of truth for it. The client-side list remains the tutorial's own mechanism and
  is not part of this feature's contract.
- The demonstration's restricted list holds company identifiers that are valid under the
  registry's own validation. This matters: the list currently shipped with the project holds
  three identifiers whose check digits do not validate, which is invisible today because
  nothing validates them, and which would make every entry unmatchable the moment the
  production does validate. Correcting the list's data is part of bringing the rule into the
  production.
- Provider and model credentials are expected to be configured by an operator in the platform's
  governed configuration and secret store; this feature consumes them but does not provision
  them.
- Conversation continuity across separate calls is not required for the first release; each
  submitted goal is an independent run unless the operator opts into session continuity.
- The model the agent uses must be reachable from the deployment, whether hosted externally or
  run locally; this feature does not host models.
- The agent inherits the production's own error handling for capability failures, so a failing
  capability surfaces as a failed run rather than a silent partial result.
- The working language of this specification is English; the language of operator-authored
  prompts is the operator's choice.

### Out of Scope for the First Release

- Finer-grained per-capability authorisation policies for agent-initiated actions beyond the
  existing read-only / write / critical classification and approval rules. This is deferred
  deliberately: it is to be implemented in a later iteration only if it can be added without
  significant rework, and the first release must not pay for it.
- Using vector similarity to route an incoming goal onto a production capability; retrieval
  serves grounding only in the first release.
- Multi-turn conversation memory across separate submitted goals, and agent-to-agent
  delegation.
- Sharing or distributing agent adapters across productions, and any form of agent
  marketplace.
- Streaming partial answers back to the caller.
- Cost, token, or usage accounting and reporting for agent runs.
- Any change to the publication model of the production's existing business capabilities, which
  remain governed by the current mechanism.

## Clarifications

### Session 2026-11-12

- **Q: Where should the agent execute — inside the production, inside the gateway, or both?**
  → **A: Inside the production.** The agent is implemented by the custom adapter, which is
  mandatory, and the agent must be reachable through MCP exactly like the production's other
  business capabilities. The production owns the agent; the gateway publishes it.
- **Q: How much authority does the agent have over state-changing actions?**
  → **A: Follow the existing authority model** (read-only, write, critical), reusing it
  unchanged, with the existing approval gate as the only brake. Any finer-grained
  per-capability authority is left out of the first release and implemented later only if it
  does not require significant rework. MVP-driven.
- **Q: What role does vector search play in the first release?**
  → **A: Grounding knowledge only**, and optional — the demonstration production is used to
  show it working, but the implementation must apply to any IRIS production unchanged.
- **Q: Is exposing Embedded Python to the agent enough to cover that technology?**
  → **A: No.** Embedded Python must be demonstrated in the production's application layer —
  a real component running on the production's own normal path and reachable by the agent —
  not merely as a Python detail of the agent itself. Recorded in FR-043, FR-047, FR-048,
  User Story 4, and SC-007.
- **Q: What work should the Embedded-Python component do?**
  → **A: Work the platform's native language does not provide — reading a document.** Two
  earlier proposals were rejected: normalising identifiers and reading the restricted list,
  because the native language does that comfortably; and making an HTTP request to the
  external registry, because the native language provides that natively as well. The
  component now extracts a supplier's details from an invoice document, while the
  production's own calls to the registry stay in the native language. Recorded in FR-048,
  FR-049, FR-050, FR-051.
- **Q: Which example should the bundled demonstration production use?**
  → **A: The restricted-company example from the project's first tutorial, moved inside the
  production.** The tutorial's client-side agent reads a restricted-company list and requests
  human approval before assessing a restricted company; the demonstration production runs the
  same rule from inside itself, with the list held by the production and the assessment
  informed by a real registration record. Recorded in the Demonstration scenario.
- **Q: Where does the agent's configuration live, and what does the production's entry point
  do?**
  → **A: The agent adapter owns the configuration** — prompt, model, reachable capability
  scope, effort and time limits — and the production's entry point supplies only the goal.
  One configuration serves every caller of the agent, whether it arrives through the gateway
  or through a direct production trigger.
- **Q: What has to stay true for the rest of the gateway?**
  → **A: Everything that was published before must still be published, unchanged, and still
  work.** The catalogue builder is the path every published tool goes through, so a change
  to it can break the discovery of capabilities that were already served. The contract over
  the published surface is therefore recorded in the repository and checked automatically,
  and the operator's guide documents how a catalogue rebuild becomes visible to callers.
  Recorded in FR-028, FR-029, FR-030, SC-014, SC-015, SC-016.
- **Q: What is vector search for in the first release?**
  → **A: To let the agent find the production's own written rules, and to act on them.**
  Grounding over a corpus of documentation that the demonstration does not otherwise have
  would have demonstrated nothing; the rules that govern the agent's decisions are what the
  agent has to retrieve, and a question that shares no literal wording with the rule it
  needs is the case that only matching by meaning serves. Recorded in FR-034, FR-038,
  FR-041, User Story 3, and the Demonstration scenario.
