# IRIS InteropMCP — Python smoke harness

External MCP client smoke tests validating the protocol-facing contract
(contracts/mcp-protocol.md) against the InteropMCP endpoint:

- tools/list returns the published catalog
- tools/call executes a demo Business Service
- GetInvocationStatus polls long-running executions

Run from within the IRIS container (Embedded Python) or locally against a
running InteropMCP endpoint:

    python3 -m pip install -r requirements.txt
    python3 smoke/mcp_client.py --endpoint http://localhost:52778/mcp/interopmcp --tool PayLookup --params '{"OrderId":"88201","CustomerId":"C-1"}'

## Done When

- `tools/list` returns `PayLookup`, `CustomerUpdate`, `RiskCheck`, `BatchRun`
- `tools/call` returns `isError: false` with a business response
- `GetInvocationStatus` returns `completed` with the final result
