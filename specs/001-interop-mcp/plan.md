# Implementation Plan: IRIS InteropMCP — Interoperability Productions as MCP Servers

**Branch**: `new-version-01` | **Date**: 2026-10-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-interop-mcp/spec.md`

## Summary

Build an MCP gateway on InterSystems IRIS that exposes Business Services of running
Interoperability Productions as MCP tools, achieving the PRD objectives (auto-discovery,
schema generation, sync-over-async, guardrails, native traceability) using the IRIS AI HUB
framework in ObjectScript, following the patterns demonstrated in `src/Sample`
(`%AI.ToolSet`, `%AI.Tool`, `%AI.MCP.Service`, endpoint setup class). A demo production in
the `Sample` package (mirroring Use Case 1 plus critical/async cases) validates end-to-end.

## Technical Context

**Language/Version**: ObjectScript on InterSystems IRIS 2026.3 (AI HUB `%AI` package
present); Python 3.10+ (client-side test harness and container tooling only — core gateway
is ObjectScript per mandated approach)

**Primary Dependencies**: IRIS AI HUB (`%AI.ToolSet`, `%AI.Tool`, `%AI.MCP.Service`),
Interoperability Engine (`Ens.Director`, `Ens.BusinessService`, `Ens.Request/Ens.Response`,
`Ens.MessageHeader`), `iris-mcp-server` bridge binary (stdio clients → IRIS MCP endpoint),
MCP Python client (tests only)

**Storage**: IRIS persistent classes for tool registry, invocation records, and approval
requests; native `Ens.MessageHeader` for interoperability traceability; no external database

**Testing**: `%UnitTest` classes (run with `/noload`); Python MCP-client smoke tests;
coverage via line-coverage tooling on the `br.musketeers.InteropMCP` package

**Target Platform**: Linux containers (Docker/Kubernetes); MCP exposed through an IRIS web
application endpoint (Type 18, MCP service) with authentication outside local development

**Project Type**: Integration gateway service (ObjectScript class library + demo production
+ test suite)

**Performance Goals**: Interactive tool call p95 well inside the 30 s default wait window
(demo services < 5 s); catalog build for tens of services in seconds; zero throughput
regression on the host production (SC-003)

**Constraints**: 100% of AI calls audited in message history (SC-002); guardrail enforcement
cannot be bypassed; authenticated endpoint outside local dev (FR-015); logging at all levels
in every component (FR-016); container-oriented deployment (constitution)

**Scale/Scope**: Single namespace; demo production with 4 Business Services → ~6 tools;
design supports tens of tools per catalog

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
|-----------|------|--------|
| Technology Stack (ObjectScript + Python backend, React frontend) | Core gateway in ObjectScript AI HUB per spec mandate; Python restricted to test harness; no frontend in this feature (React N/A — not violated, simply absent) | PASS |
| Comprehensive Logging | Every layer (tool wrapper, guardrails, registry, approvals, health) logs at all levels via a shared log helper (FR-016) | PASS |
| Monitoring and Observability | Health/status class exposing gateway + production state for monitoring systems (FR-017); every invocation traced in `Ens.MessageHeader` | PASS |
| Security by Design | Guardrails (FR-006–009), authenticated endpoint (FR-015), least-privilege web-app roles (deviation from sample's `:%All` documented in research), audit of security events (FR-018) | PASS |
| Container-Oriented Architecture | IRIS + gateway deployed as container images; setup/teardown scripted; no host-specific paths in generated config | PASS |

No violations → Complexity Tracking table remains empty after re-check (see bottom).

## Project Structure

### Documentation (this feature)

```text
specs/001-interop-mcp/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── mcp-protocol.md  # MCP JSON-RPC contract exposed to AI agents
│   └── admin-api.md     # ObjectScript class-method contract for admin operations
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
src/
├── br/musketeers/InteropMCP/                    # Gateway package (new)
│   ├── ToolSet.cls                # %AI.ToolSet: description + includes generated tools + status tool
│   ├── Registry.cls               # Catalog build/scan; generates & compiles gateway Tools class
│   ├── Invocations.cls            # ToolInvocation records: create/update/query (audit support)
│   ├── Approvals.cls              # ApprovalRequest lifecycle: create/list/approve/reject
│   ├── Guardrails.cls             # Classification enforcement: read/write/critical decisions
│   ├── SchemaMapper.cls           # Ens.Request property metadata → input parameter definition
│   ├── Invoker.cls                # Ens.Director sync + queued invocation; wait-window split
│   ├── Log.cls                    # All-level structured logging helper (constitution)
│   ├── Health.cls                 # Gateway + production health for monitoring (FR-017)
│   └── Setup.cls                  # Endpoint provisioning + demo catalog bootstrap (idempotent)
├── br/musketeers/InteropMCP/Demo/                        # Existing AI HUB samples + new demo production
│   ├── ... (existing classes unchanged)
│   ├── PayLookupRequest.cls       # Ens.Request (read-only demo)
│   ├── PayLookupBS.cls            # Ens.BusinessService, read-only classification
│   ├── CustomerUpdateRequest.cls  # Ens.Request (write demo)
│   ├── CustomerUpdateBS.cls       # Ens.BusinessService, write classification
│   ├── RiskCheckRequest.cls       # Ens.Request (critical demo)
│   ├── RiskCheckBS.cls            # Ens.BusinessService, critical classification
│   ├── BatchRunRequest.cls        # Ens.Request (long-running demo)
│   ├── BatchRunBS.cls             # Ens.BusinessService, long-running/queued
│   └── MCPDemoProduction.cls      # Ens.Production hosting the four BSs
tests/
└── br/musketeers/InteropMCP/                    # %UnitTest suites (registry, guardrails, invoker, e2e)
python/
└── smoke/                         # Python MCP-client smoke tests (constitution: Python backend role)
```

**Structure Decision**: Single IRIS class-library layout under `src/`, with the gateway
isolated in package `br.musketeers.InteropMCP` and all demo/acceptance assets in package
`br.musketeers.InteropMCP.Demo` (keeping existing sample classes untouched). Tests mirror
the gateway package in `tests/br/musketeers/InteropMCP/`; Python lives only under
`python/` as the client-side smoke harness.

## Complexity Tracking

> Re-checked after Phase 1 design: no constitution violations. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
