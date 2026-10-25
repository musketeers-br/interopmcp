# Contract: MCP Protocol (agent-facing)

**Feature**: specs/001-interop-mcp | **Date**: 2026-10-19

The gateway exposes a standard MCP server endpoint (IRIS web application, Type 18) backed by
`br.musketeers.InteropMCP.ToolSet`. All messages are MCP `JSON-RPC 2.0`; request/response envelopes follow
the MCP specification. External stdio clients reach the same endpoint through the
`iris-mcp-server` bridge (docs: AI Hub → MCP Server).

## Methods

### initialize / notifications

Standard MCP lifecycle; no gateway-specific behavior. Server advertises tool capability.

### `tools/list`

Returns every enabled, currently available tool (FR-003, FR-013).

```json
{
  "tools": [
    {
      "name": "PayLookup",
      "description": "Verify payment status for an order (read-only)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "OrderId":    { "type": "string", "description": "Order identifier" },
          "CustomerId": { "type": "string", "description": "Customer identifier" }
        },
        "required": ["OrderId"]
      }
    }
  ]
}
```

`inputSchema` is generated from the backing `Ens.Request` property metadata (R5). Disabled
or unavailable services do not appear.

### `tools/call`

**Name**: one of the listed tools. **Arguments**: object matching `inputSchema`.

#### Success (synchronous tool)

```json
{
  "content": [
    { "type": "text", "text": "{\"Status\":\"Compensated\",\"Paid\":true,\"Amount\":150.75}" }
  ],
  "isError": false
}
```

`content[0].text` carries the business service response (JSON string).

#### Write tool without authorization

```json
{
  "content": [
    { "type": "text", "text": "{\"error\":\"authorization_required\",\"tool\":\"CustomerUpdate\"}" }
  ],
  "isError": true
}
```

#### Critical tool (always returns pending, never executes directly)

```json
{
  "content": [
    { "type": "text",
      "text": "{\"status\":\"pending-approval\",\"invocationId\":\"inv-8f31\",\"message\":\"Awaiting human approval\"}" }
  ],
  "isError": false
}
```

#### Long-running tool (immediate reference, FR-011)

```json
{
  "content": [
    { "type": "text",
      "text": "{\"status\":\"in-progress\",\"invocationId\":\"inv-9c02\",\"pollWith\":\"GetInvocationStatus\"}" }
  ],
  "isError": false
}
```

### `GetInvocationStatus` (gateway-provided tool)

**Arguments**: `{ "invocationId": "string" }`

| Invocation state | Response text |
|------------------|---------------|
| in progress | `{"status":"in-progress","invocationId":"..."}` |
| completed | `{"status":"completed","invocationId":"...","result":{...}}` |
| failed | `{"status":"failed","invocationId":"...","error":"..."}` |
| pending-approval | `{"status":"pending-approval","invocationId":"..."}` |
| unknown id | `{"error":"not_found","invocationId":"..."}` (isError: true) |

## Error contract (all methods)

| Condition | Behavior |
|-----------|----------|
| Unknown tool name | MCP error response, agent-readable message |
| Schema violation | MCP error response listing the failing parameters (FR-012) |
| Backing service disabled/stopped | Tool hidden from `tools/list`; `tools/call` returns `service_unavailable` error (FR-013) |
| Unauthenticated remote caller | Transport-level auth rejection before dispatch (FR-015) |
| Duplicate tool names at build | Build-time failure; catalog never published ambiguous (FR-014) |

## Non-goals

- No gateway-specific JSON-RPC extensions; admin operations are NOT agent-callable (see
  admin-api.md).
- Agent identity flows via transport authentication, not tool arguments.
