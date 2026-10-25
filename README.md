# IRIS InteropMCP

IRIS InteropMCP turns **InterSystems Interoperability Productions** into native
**Model Context Protocol (MCP) servers**. AI agents, corporate assistants and LLM-based
tools can invoke legacy Business Services through natural language — with per-tool security
guardrails and full audit — without rewriting a single line of integration code.

Built on the InterSystems AI HUB framework in ObjectScript (`%AI.ToolSet`, `%AI.Tool`,
`%AI.MCP.Service`) and deployed as a containerized workload.

## Get running fast

The AI Hub image is **not on Docker Hub** — you must download it from the InterSystems EAP Portal first, then load it locally.

```bash
# 1. Download from https://evaluation.intersystems.com/Eval/early-access/AIHub
#    Get the .docker.tar.gz for your platform (arm64 for macOS, amd64 for Linux/Windows)

# 2. Load the image into Docker
docker load -i /path/to/iris-community-2026.3.0AI.xxx-docker.tar.gz

# 3. Update the Dockerfile FROM line to match the loaded image tag (e.g. 2026.3.0AI.154.0)

# 4. Start everything
docker compose up -d --build

# 5. Open opencode in this repo (opencode.json already configured)
opencode

# 6. Test it — in opencode chat:
# > "Use the PayLookup tool with OrderId 88201 and CustomerId C-1"
```

**MCP endpoint:** `http://localhost:8080/mcp/interopmcp`

> **See [Quick start](#quick-start) for detailed setup, [Tutorial](#quick-tutorial-with-opencode) for verification steps.**

## Features

- **Automatic tool discovery** — scans a running production for Business Services enabled
  via class annotations and publishes each one as an MCP tool with a typed input schema
  generated from its request message.
- **Per-tool security guardrails** — every tool is classified as `readonly` (autonomous),
  `write` (requires authorization) or `critical` (requires explicit human approval before
  execution). Critical calls are queued and never run without a recorded approval.
- **Native traceability** — every tool call drives a real message flow through the
  production (Business Service → Business Process → Business Operation), producing
  `Ens.MessageHeader` rows and a Visual Trace chain. The gateway keeps its own audit store
  (`br.musketeers.InteropMCP.Invocations`) and never writes into production structures.
- **Sync-over-async support** — tools flagged as long-running return a processing reference;
  agents poll `GetInvocationStatus` for the outcome.
- **Container-oriented** — image builds provision the MCP endpoint, demo production and
  tool catalog; production autostarts with IRIS; a sidecar supervises the MCP bridge.
- **Governance split** — the IPM module ships only the gateway application; the demo
  production lives only in the container build.

## Quick start

Detailed setup steps:

### 1. Download the AI Hub container image

1. Go to the [InterSystems Early Access Program Portal](https://evaluation.intersystems.com/Eval/early-access/AIHub) and download the AI Hub container for your platform.
   - File ends with `docker.tar.gz`
   - Choose **arm64** for macOS (Apple Silicon), **amd64** for Linux/Windows

2. Load the image into Docker:
   ```bash
   docker load -i /path/to/iris-community-2026.3.0AI.xxx-docker.tar.gz
   ```
   Verify with `docker images` — you should see something like:
   ```
   docker.iscinternal.com/docker-intersystems/intersystems/iris-community   2026.3.0AI.154.0   <image-id>
   ```
   > **Note:** The version includes a build number (e.g., `2026.3.0AI.154.0`), not just `2026.3.0AI`.

3. Update the `Dockerfile` in this repo — change the `FROM` line to match the exact image name printed above.

### 2. Build and start

```bash
docker compose up -d --build
```

The build provisions everything: MCP endpoint (`/mcp/interopmcp`), demo production
(`br.musketeers.InteropMCP.Demo.Production`) with the BS→BP→BO trace chain, tool catalog, and the
`iris-mcp-server` bridge (supervised).

## Quick tutorial with opencode

1. **Invoke a tool** — in opencode chat:
   > "Use the PayLookup tool with OrderId 88201 and CustomerId C-1"

2. **Verify in IRIS Management Portal**:
   - Go to **Interoperability → View Messages** → filter by today → you'll see the `Ens.MessageHeader` entry with the BS→BP→BO chain
   - Click **Visual Trace** on that message to see the full flow: `Demo.PayLookupService` → `Demo.AuditProcess` → `Demo.AuditOperation`

3. **Verify audit store** (terminal):
   ```objectscript
   zn "USER"
   zwrite ^InteropMCP.Invocations
   ```
   Or via SQL:
   ```sql
   SELECT * FROM br_musketeers.InteropMCP.Invocations ORDER BY InvocationId DESC
   ```

4. **Verify demo audit payload**:
   ```objectscript
   zn "USER"
   zwrite ^InteropMCP.Demo.AuditD
   ```

## Architecture at a glance

```mermaid
flowchart LR
    A[MCP client / opencode] -->|JSON-RPC| B[iris-mcp-server bridge :8080]
    B --> C[Web app /mcp/interopmcp - Type 18]
    C --> D[br.musketeers.InteropMCP.MCPService - %AI.MCP.Service]
    D --> E[br.musketeers.InteropMCP.ToolSet]
    E --> F[GeneratedTools + InvocationStatusTools]
    F --> G[Guardrails]
    G -->|proceed| H[Invoker]
    H -->|fires BS only| I[Business Service]
    I -->|SendRequestSync| J[AuditProcess - BP]
    J -->|SendRequestSync| K[AuditOperation - BO]
    K --> L[^InteropMCP.Demo.AuditD payload]
    I -.-> M[Ens.MessageHeader + Visual Trace]
    H -.-> N[Invocations audit store]
```

The MCP gateway only **fires** Business Services — it never writes into production
structures. The trace is produced by the production components themselves.

## Project layout

```
src/br/musketeers/InteropMCP/    Gateway application (13 ObjectScript classes)
src/br/musketeers/InteropMCP/Demo/        Demo production + request/response classes (container demo only)
tests/br/musketeers/InteropMCP/  %UnitTest suites
python/smoke/      External MCP client smoke harness
docs/interop-mcp/  Detailed documentation
specs/001-interop-mcp/  Specification artifacts (spec, plan, contracts, tasks)
```

## Documentation

| Document | Content |
|----------|---------|
| [Architecture](docs/interop-mcp/architecture.md) | Component map, request lifecycle, traceability and security models, deployment topology |
| [Operations guide](docs/interop-mcp/operations-guide.md) | Deploy/teardown, onboarding new Business Services, approval workflow, monitoring, testing |
| [API reference](docs/interop-mcp/api-reference.md) | MCP tool contract and ObjectScript class/method reference |
| [Troubleshooting](docs/interop-mcp/troubleshooting.md) | Runbook, UDL dialect rules for this build, diagnostic queries and globals map |

## IPM module

`module.xml` packages **only** the gateway (`br.musketeers.InteropMCP.PKG`). To deploy the application
without the demo, install the module and provision the endpoint in production mode:

```objectscript
Do ##class(br.musketeers.InteropMCP.Setup).Run("prod")
```

`prod` mode requires platform authentication and a least-privilege role
(`InteropMCPRoles`); `dev` mode (used by the container demo) runs unauthenticated on
localhost only.
