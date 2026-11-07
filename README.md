# IRIS InteropMCP

IRIS InteropMCP turns **InterSystems Interoperability Productions** into native
**Model Context Protocol (MCP) servers**. AI agents, corporate assistants and LLM-based
tools can invoke legacy Business Services through natural language — with per-tool security
guardrails and full audit — without rewriting a single line of integration code.

Built on the InterSystems AI HUB framework in ObjectScript and deployed as a containerized workload.

## Quick start

The AI Hub image is **not on Docker Hub** — you must download it from the InterSystems EAP Portal first, then load it locally.

1. **Download the AI Hub image**
   - Go to [https://evaluation.intersystems.com/Eval/early-access/AIHub](https://evaluation.intersystems.com/Eval/early-access/AIHub)
   - Download the `.docker.tar.gz` for your platform:
     - **arm64** for macOS (Apple Silicon)
     - **amd64** for Linux/Windows

2. **Load the image into Docker**

   You can download **any** AI Hub version from the EAP Portal. For convenience, use the same version as this repo (`2026.3.0AI.154.0`) — then skip step 3.

   ```bash
   docker load -i /path/to/iris-community-2026.3.0AI.154.0-docker.tar.gz
   ```
   > **Tip:** The filename matches the tag, e.g., `iris-community-2026.3.0AI.154.0-docker.tar.gz`

3. **Verify iris-main.log exists with correct ownership** (idempotent)
   
   ```bash
   [ -f iris-main.log ] || touch iris-main.log
   sudo chown 51773:51773 iris-main.log && sudo chmod 666 iris-main.log && ls -la iris-main.log
   # Expected: -rw-rw-r-- 1 51773 51773 out/date_size iris-main.log
   ```

4. **Update the Dockerfile (only if using a different version)**

   The repo's `Dockerfile` defaults to `2026.3.0AI.154.0`:
   ```dockerfile
   ARG IMAGE=docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.154.0
   ```

   > **If you downloaded `2026.3.0AI.154.0` above, skip this step** — nothing to edit.

   Otherwise, edit `Dockerfile` and change the `ARG IMAGE=...` line to match your loaded image tag.

5. **Prepare credentials**
   1. Create `.env` from `.env.example` and fix the bridge password:
      ```bash
      cp .env.example .env && sed -i 's/^WG_PASS=change-me/WG_PASS=SYS/' .env
      ```
      > `WG_PASS` must be `SYS` (IRIS default password) for the `iris-mcp-server` bridge to connect to the node. Without this the catalog is empty (`names=[]`) and tool calls fail with `I/O error: early eof`.

   2. Export the client authentication credential for opencode and other MCP clients:
      ```bash
      export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:change-me' | base64 -w0)"
      ```
      > Add this line to `~/.bashrc` so that opencode (and other MCP clients) send the `Authorization` header correctly. This variable is **client-side** — it is not read by the container. To persist across rebuilds, add to `~/.bashrc` and open a new terminal.

   > `opencode.json` reads `{env:INTEROPMCP_BASIC}` from the process environment at startup.
   > A transient `export` is lost on restart, and container rebuild does not update
   > `~/.bashrc`/`.env` (they are outside the image). Persist in `~/.bashrc`, then open a
   > new terminal.

   6. **Start the container**

   For a clean rebuild (recommended the first time or after changes):

   ```bash
   docker compose down -v
   docker compose build --no-cache
   docker compose up -d
   ```

7. **Wait for health and verify**

   ```bash
   docker compose logs -f
   ```

   Look for `Supervising mcp-server` in `ai-hub-mcp-launcher` service.

8. **Connect your AI coding assistant to the MCP endpoint**

   The MCP server runs at `http://localhost:8080/mcp`. Configure your preferred tool:

   **opencode** (pre-configured in this repo)
   - The repo already includes `opencode.json` with InteropMCP configured
   - Just run:
     ```bash
     opencode
     ```
   - Config (`opencode.json`):
     ```json
     "InteropMCP": {
       "type": "remote",
       "url": "http://localhost:8080/mcp",
       "headers": { "Authorization": "{env:INTEROPMCP_BASIC}" },
       "enabled": true
     }
     ```

   **Claude Code**
   - Create `.mcp.json` in the repo root:
     ```json
     {
       "mcpServers": {
         "interopmcp": {
           "url": "http://localhost:8080/mcp"
         }
       }
     }
     ```
   - Restart Claude Code

   **GitHub Copilot (VS Code)**
   - Add to VS Code `settings.json`:
     ```json
     "mcp": {
       "servers": {
         "interopmcp": {
           "url": "http://localhost:8080/mcp"
         }
       }
     }
     ```
   - Reload VS Code window (Ctrl+Shift+P → "Developer: Reload Window")

6. **Test it**
    - **6.1 Invoke a tool** — in your AI assistant's chat:

      ```
      Use the PayLookup tool with OrderId 88201 and CustomerId C-1
      ```

      ![PayLookup via Opencode](docs/articles/img/article-1-step-03-opencode-paylookup.png)
    - **6.2 Verify in IRIS Management Portal**
      - Access the Message Viewer at [http://localhost:52773/csp/irisapp/EnsPortal.MessageViewer.zen?$NAMESPACE=IRISAPP&](http://localhost:52773/csp/irisapp/EnsPortal.MessageViewer.zen?$NAMESPACE=IRISAPP&)
      - Login: **_SYSTEM** / **SYS** — namespace: **IRISAPP**
      - Filter messages by today → see the `Ens.MessageHeader` entry with the BS→BP→BO chain
      - Click **Visual Trace** on that message to see the full flow: `Demo.PayLookupService` → `Demo.AuditProcess` → `Demo.AuditOperation`

      ![PayLookup in IRIS Interoperability](docs/articles/img/article-1-step-03-opencode-paylookup-msg.png)
    - **6.3 Verify audit store** (SQL):
     - Access the SQL portal at [http://localhost:52773/csp/sys/exp/%25CSP.UI.Portal.SQL.Home.zen?$NAMESPACE=IRISAPP](http://localhost:52773/csp/sys/exp/%25CSP.UI.Portal.SQL.Home.zen?$NAMESPACE=IRISAPP)
     ```sql
     SELECT * FROM br_musketeers_InteropMCP.Invocations ORDER BY InvocationId DESC
     ```
   - **6.4 Verify demo audit payload**:

     ```bash
     docker exec -it ai-hub-dev-template-iris-1 iris session iris -U IRISAPP
     ```

     Then run:
     ```objectscript
     zwrite ^InteropMCP.Demo.AuditD
     halt
     ```

**MCP endpoint:** `http://localhost:8080/mcp`

For more detailed information and additional examples, see [InteropMCP: Turn your InterSystems IRIS productions into MCP tools for AI agents](docs/articles/article-1-idea-ai-hub-tutorial.md).

## Troubleshooting / Rebuild from scratch

| Symptom | Probable cause | Solution |
|---------|---------------|---------|
| `"InteropMCP Failed to get tools"` | `INTEROPMCP_BASIC` missing/stale in opencode environment (`~/.bashrc`) | `printenv INTEROPMCP_BASIC`; fix the block in `~/.bashrc` (derive from `.env`), open a new terminal and restart opencode. Rebuild only as fallback |
| `"InteropMCP Failed to get tools"` with `INTEROPMCP_BASIC` correct | `iris-mcp-server` exposes `iris_status` with empty `inputSchema` (`{}`), invalid schema for MCP 2025-11-25 clients (opencode) | Bring up the bridge with `run --status-tool false`; `docker-compose.yml` already does this on start and supervisor |
| Bridge discovers 0 tools | `config_http.toml` without `WG_USER`/`WG_PASS` | Create `.env` from `.env.example` and export `INTEROPMCP_BASIC` |
| `401` on discovery | Bridge credential missing or invalid | Check `.env` and `INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:change-me' | base64 -w0)"` |
| `403` on tool execution | User is not a member of `InteropMCPRoles` | Use `mcp_demo` (entitled) instead of `mcp_demo2` (unentitled) |
| Bridge won't come up | Supervisor does not restart by itself | `docker exec -d <container> sh -c '/usr/irissys/bin/iris-mcp-server -c /home/irisowner/dev/config_http.toml run --status-tool false > /tmp/mcp.log 2>&1'` |
| Catalog outdated after rebuild | Bind-mount overwrites `GeneratedTools.cls` | `BuildCatalog` runs during `docker build`; if necessary, re-provision: `docker exec <container> iris session IRIS -U IRISAPP < bootstrap-gateway.script` |

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

## Architecture at a glance

```mermaid
flowchart TD
    subgraph Client["MCP Client"]
        A[MCP client / opencode]
    end

    subgraph Bridge["MCP Bridge"]
        B[iris-mcp-server bridge :8080]
    end

    subgraph Gateway["MCP Gateway (Web app /mcp/interopmcp)"]
        C[Web app /mcp/interopmcp - Type 18]
        D[br.musketeers.InteropMCP.MCPService - %AI.MCP.Service]
        E[br.musketeers.InteropMCP.ToolSet]
        F[GeneratedTools + InvocationStatusTools]
        G[Guardrails]
        H[Invoker]
    end

    subgraph Production["Interop Production"]
        I[Business Service]
        J[AuditProcess - BP]
        K[AuditOperation - BO]
    end

    subgraph Storage["Storage & Audit"]
        L[^InteropMCP.Demo.AuditD payload]
        M[Ens.MessageHeader + Visual Trace]
        N[Invocations audit store]
    end

    A -->|JSON-RPC| B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G
    G -->|proceed| H
    H -->|fires BS only| I
    I -->|SendRequestSync| J
    J -->|SendRequestSync| K
    K --> L
    I -.-> M
    H -.-> N
```

The MCP gateway only **fires** Business Services — it never writes into production
structures. The trace is produced by the production components themselves.

## Project layout

```
src/
  br/
    musketeers/
      InteropMCP/              Gateway application (13 ObjectScript classes)
      InteropMCP/Demo/         Demo production + request/response classes (container demo only)
tests/
  br/
    musketeers/
      InteropMCP/              %UnitTest suites
python/
  smoke/                       External MCP client smoke harness
docs/
  interop-mcp/                 Detailed documentation
specs/
  001-interop-mcp/             Specification artifacts (spec, plan, contracts, tasks)
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
