# @psyb0t/pibox

An OpenClaw/MCP plugin that connects your agent to a self-hosted
[pibox](https://github.com/psyb0t/docker-pibox) (pi-coding-agent on the
network) server over the [Model Context Protocol](https://modelcontextprotocol.io).

pibox already serves a Streamable-HTTP MCP endpoint at `/mcp` when
`PIBOX_MCP_MODE=1` is set on the server. This package is a thin stdio↔HTTP
bridge (via [`mcp-remote`](https://www.npmjs.com/package/mcp-remote)) for MCP
clients that speak local stdio servers — it forwards everything to your
running pibox instance and authenticates with your bearer token when the
server requires one.

> pibox is **self-hosted**. This plugin does not ship the agent runtime — it
> connects to a pibox server that **you** run. See the
> [pibox repo](https://github.com/psyb0t/docker-pibox) to stand one up.

## Tools

The 5 pibox MCP tools become available to your agent: `run_prompt` (invoke
pi-coding-agent on a workspace and get its textual response — accepts
`workspace`, `model`, `system_prompt`, `append_system_prompt`, `resume`,
`thinking`, `json_schema`), plus workspace file ops `list_files`,
`read_file`, `write_file`, and `delete_file`.

## Configuration

| Env var | Required | Description |
|---|---|---|
| `PIBOX_URL` | yes | Base URL of your running pibox server, e.g. `http://localhost:8080`. The bridge appends `/mcp`. |
| `PIBOX_MCP_MODE_TOKEN` | no | Bearer token — only if the pibox server was started with `PIBOX_MCP_MODE_TOKEN` set. |

## Install

Install it into your OpenClaw agent from ClawHub:

```bash
openclaw plugins install clawhub:@psyb0t/pibox
```

Then set `PIBOX_URL` (and `PIBOX_MCP_MODE_TOKEN` if your server uses auth) in
the plugin's environment.

## Native remote MCP (no install)

If your MCP client already supports **remote** Streamable-HTTP servers, you
don't need this bridge — point the client straight at `$PIBOX_URL/mcp` with
an `Authorization: Bearer <token>` header.

## License

MIT. See [LICENSE](LICENSE).
