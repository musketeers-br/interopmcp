# Contract: Configuration (bridge, client, container)

**Feature**: `002-mcp-gateway-auth` | **Date**: 2026-10-25

Configuration contract for secured and demo modes. The authoritative security decision is
made in IRIS; this contract ensures the client and bridge do not undermine it.

## Mode matrix

| Setting | Secured | Demo |
|---------|---------|------|
| `INTEROPMCP_MODE` | `secured` | `demo` |
| IRIS app `AutheEnabled` | `32` | `64` |
| IRIS app `Resource` | `""` | `""` |
| IRIS app `MatchRoles` | `""` | `":%All"` |
| `MCPService` `RESOURCE` | `InteropMCP_Access` | `InteropMCP_Access` (present but not reached) |
| `config_http.toml` `allow_anonymous` | `false` | `true` |
| `config_http.toml` endpoint creds | absent | absent |
| `opencode.json` `Authorization` | `{env:INTEROPMCP_BASIC}` | may be omitted |
| Identity | `$USERNAME` | `local-dev` |

Mode is selected explicitly. `Setup.Run()` with no argument provisions secured mode.
`Setup.Run("dev")`/`Run("demo")` is the only way to provision demo mode.

## `config_http.toml`

```toml
[[iris]]
name = "local"
server = { host = "localhost", port = 1972, username = "@{env:WG_USER}", password = "@{env:WG_PASS}" }
endpoints = [
    { path = "/mcp/interopmcp" }
]

[mcp]
transport = "http"
port = 8080
host = "0.0.0.0"
allow_anonymous = false
```

Rules:

1. `endpoints[].username` and `endpoints[].password` MUST be absent in secured mode. Their
   presence means the bridge would replace the caller's credential with a shared identity.
2. `allow_anonymous` MUST be `false` in secured mode and `true` in demo mode.
3. `[[iris]] server` credentials are the technical superserver account. They are not the
   caller identity and may be supplied through environment substitution. They are never
   logged or committed.
4. `host = "0.0.0.0"` inside the container is required for Docker port publishing. The host
   publication is loopback-only (see below). Do not expose this port on a non-loopback
   interface without TLS or a trusted reverse proxy.
5. `config_stdio.toml` is unchanged; stdio is not the secured HTTP path.

## `opencode.json`

```json
{
  "mcp": {
    "InteropMCP": {
      "type": "remote",
      "url": "http://localhost:8080/mcp/interopmcp",
      "headers": {
        "Authorization": "{env:INTEROPMCP_BASIC}"
      },
      "enabled": true
    }
  }
}
```

Rules:

- `INTEROPMCP_BASIC` is `base64(username:password)`, not the raw `username:password`.
- The value is supplied by the user's environment; it is never committed to the repository.
- In demo mode the header may be omitted; in secured mode it is required.
- `{file:...}` is an acceptable alternative if the local OpenCode version supports it, but
  the environment form is the documented default.

## `.env.example`

Documented, non-secret placeholders:

```dotenv
# Bridge -> IRIS superserver (technical account)
WG_USER=_SYSTEM
WG_PASS=change-me

# Demo users created by bootstrap-gateway.script (never commit real values)
INTEROPMCP_DEMO_PASSWORD=change-me
INTEROPMCP_MODE=secured

# Client-side Basic header: base64(mcp_demo:INTEROPMCP_DEMO_PASSWORD)
# Set this in the shell that launches opencode, not in this file.
# INTEROPMCP_BASIC=Basic ...
```

Rules:

- `.env` is gitignored; `.env.example` contains only placeholders.
- `INTEROPMCP_DEMO_PASSWORD` is required by the demo bootstrap in secured mode; the bootstrap
  fails with an actionable message if it is missing.
- `INTEROPMCP_BASIC` is a client-side variable; it is not read by the container. It must be
  exported by the process that launches OpenCode (persist it in `~/.bashrc`). Changing the auth
  contract requires updating `opencode.json`, `.env.example`, `.env`, and `~/.bashrc` together;
  a rebuild does not touch the last two.

## `docker-compose.yml`

```yaml
services:
  iris:
    ports:
      - "127.0.0.1:1972:1972"
      - "127.0.0.1:52773:52773"
      - "127.0.0.1:8080:8080"
    environment:
      - INTEROPMCP_MODE=secured
      - INTEROPMCP_DEMO_PASSWORD=${INTEROPMCP_DEMO_PASSWORD}
    env_file:
      - .env

  mcp-launcher:
    environment:
      - INTEROPMCP_MODE=secured
      - CONTAINER_NAME=ai-hub-dev-template-iris-1
    command: >
      sh -c "
        python3 /home/irisowner/dev/scripts/validate-mcp-config.py \
          --config /home/irisowner/dev/config_http.toml \
          --mode \"$${INTEROPMCP_MODE}\" || exit 1;
        ...
      "
```

Rules:

- Publish on `127.0.0.1` only. Binding the bridge to `127.0.0.1` inside the container would
  break Docker port publishing; loopback publication at the host boundary is the Phase 1
  control.
- The launcher runs the validator before `iris-mcp-server` starts and exits non-zero on
  failure.
- `INTEROPMCP_MODE` must agree with the mode passed to `Setup.Run` and with
  `allow_anonymous`.
- No secret is baked into the image or committed to the repository.

## `scripts/validate-mcp-config.py`

Purpose: fail fast when the bridge configuration would collapse or bypass per-user identity.
Python 3.11+ standard library only (`tomllib`, `argparse`, `sys`).

Checks:

| Condition | Exit | Message |
|-----------|------|---------|
| `mode` not `secured`/`demo` | 2 | `invalid mode: <value> (expected secured or demo)` |
| secured + `allow_anonymous=true` | 1 | `secured mode requires allow_anonymous=false` |
| demo + `allow_anonymous=false` | 1 | `demo mode requires allow_anonymous=true` |
| secured + endpoint `username` or `password` | 1 | `endpoint <path> defines <key>; remove it so the caller credential is forwarded` |
| endpoint `username`/`password` present without `path` | 1 | `endpoint entry is missing path` |
| config unreadable/invalid TOML | 2 | `cannot read <path>: <error>` |

The validator never prints a password or token. It is a startup gate, not a replacement for
the IRIS-side checks (`MCPService` `RESOURCE`, `AuditEnabled`, app `AutheEnabled=32`).

## `iris.script` and `bootstrap-gateway.script`

- `iris.script` calls `Setup.Run("prod")` (secured) instead of `"dev"`.
- `bootstrap-gateway.script` calls `Setup.Run("prod")`, then creates/reconciles `mcp_demo` and
  `mcp_demo2` with `InteropMCPRoles` and the environment-supplied password.
- Both scripts are idempotent; re-running them must not duplicate users, roles, resources, or
  the web application.
- Demo users are not part of the IPM module; they exist only in the demo bootstrap.

## Failure messages (operator-facing)

| Situation | Message must name |
|-----------|-------------------|
| Secured setup, empty `MCPService.RESOURCE` | `br.musketeers.InteropMCP.MCPService` and `RESOURCE` |
| Secured setup, audit disabled | `Security.System.AuditEnabled` |
| Startup, anonymous secured config | `allow_anonymous` |
| Startup, endpoint static credential | `endpoints[].username` / `endpoints[].password` and the endpoint path |
| Demo bootstrap, missing password | `INTEROPMCP_DEMO_PASSWORD` |

No failure message may include a credential value.
