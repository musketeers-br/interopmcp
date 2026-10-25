# Quickstart: IRIS InteropMCP validation

**Feature**: specs/001-interop-mcp | **Date**: 2026-10-19

End-to-end validation guide. Proves the four user stories from spec.md against the demo
production. Reference [contracts/mcp-protocol.md](contracts/mcp-protocol.md) for exact
payload shapes and [data-model.md](data-model.md) for entities.

## Prerequisites

- IRIS 2026.3+ container with AI HUB `%AI` package, namespace `IRISAPP`
- Interoperability enabled in the namespace
- MCP client for manual checks (e.g., MCP Inspector) — optional; the Python smoke harness
  covers the same path
- Existing `src/br/musketeers/InteropMCP/Demo` classes compiled (they stay untouched)

## Setup (first time)

```text
1. Compile all sources:  src/br/musketeers/InteropMCP/*.cls, src/br/musketeers/InteropMCP/Demo/*.cls, tests/br/musketeers/InteropMCP/*.cls
2. IRIS terminal (IRISAPP):
     Do ##class(br.musketeers.InteropMCP.Setup).Run("dev")     // dev mode: unauthenticated local
3. Verify:  Set st = ##class(br.musketeers.InteropMCP.Health).GetStatus()  → production running,
   catalogSize ≥ 5, pendingApprovals = 0
```

`Setup.Run("dev")` is idempotent — safe to re-run.

## Validation scenarios

### S1 — Tool discovery + invocation (User Story 1, SC-001)

```text
1. Via MCP client connected to the gateway endpoint:
     tools/list
   Expected: PayLookup, CustomerUpdate, RiskCheck, BatchRun, GetInvocationStatus
   — each with description + inputSchema (no unannotated sample tools, FR-003)
2. tools/call PayLookup { "OrderId": "88201", "CustomerId": "C-1" }
   Expected: synchronous business response (isError false), matching demo BS output
3. Register a new annotated BS (or toggle SetEnabled) → BuildCatalog → tools/list
   Expected: catalog updated with no manual code change (SC-004)
```

### S2 — Guardrails (User Story 2, SC-005)

```text
1. tools/call CustomerUpdate { "CustomerId": "C-1", "NewAddress": "Rua X, 100" }
   without authorization → isError true, authorization_required (FR-008)
2. Same call with authorized session → executes, response returned
3. tools/call RiskCheck { "Cnpj": "00.000.000/0001-00", "Scope": "full" }
   Expected: pending-approval + invocationId; NO execution (FR-009)
4. IRIS terminal: Do ##class(br.musketeers.InteropMCP.Approvals).Approve("APR-...", "operator1")
   → polling GetInvocationStatus returns completed with result
5. Second critical call, then Reject(...) → GetInvocationStatus returns rejected;
   no execution ever started (SC-005)
```

### S3 — Traceability (User Story 3, SC-002)

```text
1. After S1–S2 calls, open Management Portal → Interoperability → message history
   Expected: for EVERY AI-triggered tool call, a full BS→BP→BO flow:
   CustomerUpdateBS → AuditProcess → AuditOperation headers with the request body
   (br.musketeers.InteropMCP.Demo.CustomerUpdateRequest) persisted — ~4 Ens.MessageHeader rows per call (FR-010)
2. Visual Trace on any header: 3 hops with timings
3. Terminal: ^InteropMCP.Demo.AuditD holds the JSON payload dump per call;
   ^InteropMCP.LogD holds gateway logs; ToolInvocation records cover 100% of
   the calls made above with agent identity + duration (SC-002)
```

### S4 — Long-running (User Story 4, FR-011)

```text
1. tools/call BatchRun { "ReportSet": "daily" }
   Expected: immediate {"status":"in-progress","invocationId":...} (< 2 s)
2. GetInvocationStatus { "invocationId": ... } → in-progress, then completed with result
3. GetInvocationStatus { "invocationId": "bogus" } → not_found error
```

### S5 — Automated suites

```text
1. %UnitTest: run tests/br/musketeers/InteropMCP suites with /noload
   Expected: all pass; coverage ≥ 90% on br.musketeers.InteropMCP package
2. Python smoke: python/smoke run against the endpoint
   Expected: list → call → status flow passes from an external client (SC-001)
3. Zero-regression check: run demo BS workload with gateway enabled vs disabled
   Expected: no behavioral difference, no added error rate (SC-003)
```

## Teardown

```text
Do ##class(br.musketeers.InteropMCP.Setup).TearDown()   // removes endpoint + demo production (idempotent)
```

## Failure triage

| Symptom | Check |
|---------|-------|
| tools/list empty | Production running? BS annotations present? BuildCatalog error log (`registry` component) |
| Compilation error in generated tools | SchemaMapper output for the offending request class; request class compiled? |
| pending-approval never resolves | ApprovalRequest decision state; Approvals.ListPending() |
| Auth rejection in dev | Setup ran with "dev" mode? (FR-015 dev exception) |
