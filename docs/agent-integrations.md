---
title: "Agent integrations"
description: "Install the pibox skill and plugins in Claude Code, Codex and OpenClaw, and bridge stdio MCP clients to a running pibox server."
nav_order: 7
---

# Agent integrations

The repository ships an agent skill and an MCP bridge plugin under [`.agents/`](https://github.com/psyb0t/docker-pibox/tree/main/.agents). The [skill](https://github.com/psyb0t/docker-pibox/tree/main/.agents/skills/pibox) works in any agent that reads `.agents/skills/`, such as [peen](https://github.com/psyb0t/peen). It tells agents to use the installed wrapper for local work, and to use MCP only for a server that is already running.

## Claude Code

```bash
claude plugin marketplace add psyb0t/agents
claude plugin install pibox@psyb0t
```

Claude Code asks for the pibox URL and, if auth is on, the API and MCP tokens. It stores the tokens in your OS keychain.

## Codex

```bash
codex plugin marketplace add psyb0t/agents
codex plugin add pibox@psyb0t
```

Installed through the marketplace, the skill is invoked as `$pibox:pibox`. Codex also picks the skill up with no install in any repository that contains `.agents/skills/`, where it is invoked as plain `$pibox`.

## OpenClaw

The skill is published to ClawHub on every release:

```bash
openclaw skills install @psyb0t/pibox
```

For MCP clients that only speak local stdio, the [`@psyb0t/pibox`](https://github.com/psyb0t/docker-pibox/tree/main/.agents/plugins/pibox) plugin bridges stdio to the server's `/mcp/` endpoint through [`mcp-remote`](https://www.npmjs.com/package/mcp-remote):

```bash
openclaw plugins install clawhub:@psyb0t/pibox
```

| Variable | Required | Meaning |
| --- | --- | --- |
| `PIBOX_URL` | yes | Base URL of the running server, such as `http://localhost:8080`. The bridge appends `/mcp/` |
| `PIBOX_MCP_MODE_TOKEN` | no | Bearer token, needed only when the server was started with `PIBOX_MCP_MODE_TOKEN` |

The bridge appends `/mcp/`, which is the API-mode path. A sidecar MCP server serves at its port root instead, so for a sidecar, point an MCP client that speaks streamable HTTP straight at `http://host:8081/` rather than using the bridge.

The plugin does not start a server. Start one from the workspace you want to expose, with both tokens set:

```bash
PIBOX_DETACH=1 \
PIBOX_API_MODE=1 \
PIBOX_MCP_MODE=1 \
PIBOX_AVAILABLE_MODELS=your-model-id \
PIBOX_API_MODE_TOKEN=your-api-token \
PIBOX_MCP_MODE_TOKEN=your-mcp-token \
pibox
```

If your MCP client already supports remote streamable HTTP servers, you do not need the bridge. Point the client at `$PIBOX_URL/mcp/` with an `Authorization: Bearer <token>` header, as in [MCP mode](modes/mcp.md#connecting-a-client).

## MCP Registry

The image is listed in the MCP Registry as `io.github.psyb0t/pibox`. The entry in [`server.json`](https://github.com/psyb0t/docker-pibox/blob/main/server.json) points at `docker.io/psyb0t/pibox:latest` with the streamable HTTP transport on port `8081`, the sidecar placement.
