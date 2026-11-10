# @psyb0t/pibox

An OpenClaw/MCP plugin that connects your agent to a self-hosted
[pibox](https://github.com/psyb0t/docker-pibox) (pi-coding-agent on the
network) server over the [Model Context Protocol](https://modelcontextprotocol.io).

pibox already serves a Streamable-HTTP MCP endpoint when
`PIBOX_MCP_MODE=1` is set on the server: at `/mcp/` on the API port in API
mode, or at the root of `PIBOX_MCP_MODE_PORT` (default `8081`) as a sidecar. This package is a thin stdio↔HTTP
bridge (via [`mcp-remote`](https://www.npmjs.com/package/mcp-remote)) for MCP
clients that speak local stdio servers. It forwards everything to your
running pibox instance and authenticates with your bearer token when the
server requires one.

> pibox is **self-hosted**. This plugin does not ship the agent runtime. It
> connects to a pibox server that **you** run. See the
> [pibox repo](https://github.com/psyb0t/docker-pibox) to stand one up.

## Start a local server

Configure the Pi upstream with `PIBOX_PROVIDER_*` or the supported
`ANTHROPIC_*` compatibility variables (through the wrapper, with the
`PIBOX_ENV_` prefix, such as `PIBOX_ENV_ANTHROPIC_AUTH_TOKEN`), then start the
service through the wrapper from the workspace you want to expose. Set both
bearer tokens before publishing a port.

```bash
PIBOX_DETACH=1 \
PIBOX_API_MODE=1 \
PIBOX_MCP_MODE=1 \
PIBOX_AVAILABLE_MODELS=your-model-id \
PIBOX_API_MODE_TOKEN=your-api-token \
PIBOX_MCP_MODE_TOKEN=your-mcp-token \
pibox
```

With `PIBOX_URL=http://localhost:8080` the plugin connects to
`http://localhost:8080/mcp/`. For a sidecar MCP server (MCP mode without API
mode), set `PIBOX_MCP_URL=http://localhost:8081/` instead. It does not launch
the container for you. See the
[documentation](https://psyb0t.github.io/docker-pibox/) for a remote deployment.

## Tools

The 5 pibox MCP tools become available to your agent: `run_prompt` (invoke
pi-coding-agent on a workspace and get its textual response; it accepts
`workspace`, `model`, `system_prompt`, `append_system_prompt`, `resume`,
`thinking`, `json_schema`), plus workspace file ops `list_files`,
`read_file`, `write_file`, and `delete_file`.

## Configuration

| Env var | Required | Description |
|---|---|---|
| `PIBOX_URL` | one of the two | Base URL of a pibox server in API mode, e.g. `http://localhost:8080`. The bridge appends `/mcp/`. |
| `PIBOX_MCP_URL` | one of the two | Full MCP endpoint URL, used as given, e.g. `http://localhost:8081/` for a sidecar MCP server. Wins over `PIBOX_URL`. |
| `PIBOX_MCP_MODE_TOKEN` | no | Bearer token, only if the pibox server was started with `PIBOX_MCP_MODE_TOKEN` set. |

## Install

Install it into your OpenClaw agent from ClawHub:

```bash
openclaw plugins install clawhub:@psyb0t/pibox
```

Then set `PIBOX_URL` or `PIBOX_MCP_URL` (and `PIBOX_MCP_MODE_TOKEN` if your
server uses auth) in the plugin's environment.

## Native remote MCP (no install)

If your MCP client already supports **remote** Streamable-HTTP servers, you
don't need this bridge. Point the client straight at `$PIBOX_URL/mcp/` (or
the sidecar root) with an `Authorization: Bearer <token>` header.

## License

MIT. See [LICENSE](LICENSE).
