# Quickstart: Per-User Authentication and Authorization

**Feature**: `002-mcp-gateway-auth` | **Date**: 2026-10-25

End-to-end validation guide for secured mode. Reference
[contracts/mcp-auth.md](contracts/mcp-auth.md) for exact HTTP behavior and
[data-model.md](data-model.md) for entities.

## Prerequisites

- IRIS 2026.3 AI HUB container built from this repository.
- `iris-mcp-server` available at `/usr/irissys/bin/iris-mcp-server`.
- Docker Compose.
- An OpenCode client with remote MCP support.
- The IRIS system password authentication is enabled (the instance default).

## 1. Configure the environment

Create `.env` from `.env.example` and set the technical and demo values:

```dotenv
WG_USER=_SYSTEM
WG_PASS=<technical superserver password>
INTEROPMCP_DEMO_PASSWORD=<demo password, not the real corporate password>
INTEROPMCP_MODE=secured
```

Rules:

- `WG_USER`/`WG_PASS` are the bridge's technical account for the IRIS superserver.
- `INTEROPMCP_DEMO_PASSWORD` is used by the demo bootstrap to create `mcp_demo` and
  `mcp_demo2`. Do not commit it.
- `INTEROPMCP_BASIC` is **not** stored in `.env`; it must be present in the environment of the
  process that launches OpenCode. Persist the export in the shell startup file (e.g.
  `~/.bashrc`) — a transient `export` is lost on restart.
- When the auth contract changes (env name, header format, password), update `opencode.json`,
  `.env.example`, `.env`, and the launch shell together. A container rebuild does **not**
  update `~/.bashrc`/`.env` (they live outside the image).

Compute the client header locally:

```bash
export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:%s' "$INTEROPMCP_DEMO_PASSWORD" | base64 -w0)"
# persist it so OpenCode inherits it at every launch:
echo "export INTEROPMCP_BASIC='$INTEROPMCP_BASIC'" >> ~/.bashrc
```

For a second user:

```bash
export INTEROPMCP_BASIC_2="Basic $(printf 'mcp_demo2:%s' "$INTEROPMCP_DEMO_PASSWORD" | base64 -w0)"
```

## 2. Start the stack

```bash
docker compose up -d --build
```

The `mcp-launcher` performs, in order:

1. `scripts/validate-mcp-config.py` — fails if the mode, `allow_anonymous`, or endpoint
   credentials are inconsistent.
2. `bootstrap-gateway.script` — `Setup.Run("prod")`, demo production, `mcp_demo`/`mcp_demo2`.
3. `iris-mcp-server -c config_http.toml run`.

If the validator fails, the bridge is not started and the container log names the offending
setting.

## 3. Verify provisioning

```bash
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "IRISAPP"
Set sc = ##class(Security.Applications).Get("/mcp/interopmcp", .p)
Write "app=", $$$ISOK(sc), " auth=", p("AutheEnabled"), " resource=", p("Resource"), " match=", p("MatchRoles"), !
Set sc = ##class(Security.Resources).Get("InteropMCP_Access", .r)
Write "resource=", $$$ISOK(sc), " public=", r("PublicPermission"), !
Set sc = ##class(Security.Roles).Get("InteropMCPRoles", .role)
Write "role=", $$$ISOK(sc), " resources=", role("Resources"), !
Write "serviceResource=", $PARAMETER("br.musketeers.InteropMCP.MCPService", "RESOURCE"), !
Write "auditEnabled=", ##class(Security.System).Get(, .sys), " ", sys("AuditEnabled"), !
Write "mode=", $Get(^InteropMCP.Config("mode")), !
Halt
EOF
```

Expected:

```text
app=1 auth=32 resource= match= 
resource=1 public=0
role=1 resources=InteropMCP_Access:U,%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW,...
serviceResource=InteropMCP_Access
auditEnabled=1 1
mode=secured
```

## 4. Configure OpenCode

`opencode.json` already points at the bridge. The remote entry must carry the per-user
header:

```json
"InteropMCP": {
  "type": "remote",
  "url": "http://localhost:8080/mcp/interopmcp",
  "headers": { "Authorization": "{env:INTEROPMCP_BASIC}" },
  "enabled": true
}
```

Restart OpenCode from a **new** shell where `INTEROPMCP_BASIC` is exported (persisted in
`~/.bashrc`). In demo mode the header may be omitted.

## 5. Validation scenarios

### S1 — Missing credential (401)

```bash
curl -sS -i -X POST http://localhost:8080/mcp/interopmcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: `401`, no tool list. The IRIS audit contains an `INTEROPMCP` /
`AuthenticationDenied` row (or a `%LOGIN` failure if the bridge reaches CSP authentication).

### S2 — Invalid credential (401)

```bash
curl -sS -i -u mcp_demo:wrong-password -X POST http://localhost:8080/mcp/interopmcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: `401`, no tool list, `%LOGIN` / `LoginFailure` in `%SYS.Audit` with
`Username=mcp_demo`.

### S3 — Valid user without entitlement (403)

Create a user with no `InteropMCPRoles`:

```bash
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "%SYS"
Set sc = ##class(Security.Users).Create("mcp_norole", "", "mcp_norole", "No Role", "IRISAPP", "", "", 0, 1)
Write "create=", $$$ISOK(sc), !
Halt
EOF
```

Then:

```bash
curl -sS -i -u mcp_norole:mcp_norole -X POST http://localhost:8080/mcp/interopmcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: `403`, no catalog/result. `%SYS.Audit` contains `INTEROPMCP` / `AccessDenied` with
`Username=mcp_norole`.

### S4 — Entitled user: read and write

Use the OpenCode client or the smoke harness with `mcp_demo`:

```bash
python3 python/smoke/mcp_client.py \
  --endpoint http://localhost:8080/mcp/interopmcp \
  --basic "$INTEROPMCP_BASIC" \
  --tool PayLookup \
  --params '{"OrderId":"88201","CustomerId":"C-1"}'
```

Then invoke `CustomerUpdate` (write). Expected: both succeed; `Invocations.AgentIdentity` is
`mcp_demo`; the write call still passes the tool's own guardrails.

### S5 — Identity isolation

Run at least 20 interleaved `PayLookup` calls as `mcp_demo` and `mcp_demo2`. Query:

```sql
SELECT AgentIdentity, COUNT(*) AS Calls
FROM br.musketeers.InteropMCP.Invocations
GROUP BY AgentIdentity
```

Expected: two distinct identities, counts matching the calls, no `"agent"` and no
`UnknownUser`.

### S6 — Revocation on the next request (403)

```bash
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "%SYS"
Kill u Set u("Roles") = ""
Set sc = ##class(Security.Users).Modify("mcp_demo2", .u)
Write "revoke=", $$$ISOK(sc), !
Halt
EOF
```

Without reconnecting, call a tool as `mcp_demo2`. Expected: `403` on the next request. Restore
the role afterward.

### S7 — Idempotent setup

```bash
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "IRISAPP"
Write ##class(br.musketeers.InteropMCP.Setup).Run("prod"), !
Write ##class(br.musketeers.InteropMCP.Setup).Run("prod"), !
Write ##class(br.musketeers.InteropMCP.Setup).Run("prod"), !
Halt
EOF
```

Expected: three successes; exactly one app, one resource, one role; behavior unchanged.

### S8 — Mode switch

```bash
# demo
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "IRISAPP"
Write ##class(br.musketeers.InteropMCP.Setup).Run("dev"), !
Halt
EOF
# no credential now succeeds; identity is local-dev

# back to secured
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "IRISAPP"
Write ##class(br.musketeers.InteropMCP.Setup).Run("prod"), !
Halt
EOF
# no credential is refused again
```

### S9 — Static endpoint credential is rejected at startup

Temporarily add `username = "x", password = "y"` to the endpoint in `config_http.toml` and
restart the launcher. Expected: the validator exits non-zero with a message naming
`endpoints[].username`/`password` and the endpoint path; the bridge does not start. Remove the
fields afterward.

### S10 — Audit query

```sql
SELECT EventType, Event, Username, Description, EventData, UTCTimeStamp
FROM %SYS.Audit
WHERE EventType IN ('%LOGIN', 'INTEROPMCP')
ORDER BY UTCTimeStamp DESC
```

Expected: `LoginFailure` rows for bad passwords, `AuthenticationDenied` rows for missing
credentials, `AccessDenied` rows for entitlement denials. None contains a password, Basic
token, or `Authorization` value.

## 6. Credential-exclusion check

```bash
docker exec ai-hub-dev-template-iris-1 sh -c \
  'grep -R --binary-files=text -E "Basic |password|Authorization" /tmp/mcp.log /home/irisowner/dev/iris-main.log || true'
```

Also inspect `Invocations` and `%SYS.Audit` rows created during the tests. Expected: no
credential or header value. Test passwords such as `wrong-password` must not appear.

## 7. Troubleshooting

| Symptom | Check |
|---------|-------|
| `401` for a valid user | Is the app `AutheEnabled=32`? Is the password correct? Does the bridge forward the header? |
| `403` for an entitled user | Does `InteropMCPRoles` include `InteropMCP_Access:U`? Is the user assigned the role? Is `MCPService.RESOURCE` present? |
| `502 GATEWAY_REQUIRED` | The request bypassed `iris-mcp-server`; use the bridge URL `:8080`, not the IRIS port directly. |
| Bridge does not start | Run `python3 scripts/validate-mcp-config.py --config config_http.toml --mode "$INTEROPMCP_MODE"` and read the named setting. |
| Audit rows missing | Is `Security.System.AuditEnabled=1`? Check the `%SYS.Audit` query and the IRIS audit settings. |
| Identity is `local-dev` in secured mode | `^InteropMCP.Config("mode")` is `demo`, or `$USERNAME` is `UnknownUser`; re-run `Setup.Run("prod")` and verify the app auth mode. |
| Identity is `"agent"` | `GeneratedTools.cls` was not regenerated after the `Registry` change; run `BuildCatalog`. |

## 8. Teardown

```bash
docker exec -i ai-hub-dev-template-iris-1 iris session IRIS <<'EOF'
zn "IRISAPP"
Do ##class(br.musketeers.InteropMCP.Setup).TearDown()
Halt
EOF
```

`TearDown()` removes the web application only. It intentionally leaves `InteropMCP_Access`,
`InteropMCPRoles`, and demo users in place to avoid silently revoking access from other
consumers. Remove them manually if decommissioning the instance.

## 9. Phase 2 notes

OAuth 2.0, custom API keys, per-tool RBAC, LDAP/SSO, corporate TLS/reverse proxy, and
WebSocket denial auditing are out of scope. See
[`docs/interop-mcp/authentication.md`](../../docs/interop-mcp/authentication.md) §10.
