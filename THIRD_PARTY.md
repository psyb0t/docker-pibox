# Third-Party Software

pibox's own code (this repo) is [WTFPL](LICENSE)-licensed, and the
`.agents/plugins/pibox` MCP bridge is MIT (its own LICENSE). The **published
Docker images** bake in the pi coding agent + base tooling at build time, all
of which are open-source and permissively licensed. This file lists what the
published images redistribute — not dev-only dependencies, and not anything the
end user downloads themselves.

| Component | Kind | License (SPDX) | Source | Where it lives | Note |
|---|---|---|---|---|---|
| [`@earendil-works/pi-coding-agent`](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) | npm global install | `MIT` | https://github.com/earendil-works/pi-mono | `Dockerfile` — `npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}` | The `pi` coding agent. Open source (MIT), so redistribution in the image is fine — attribution retained. Full text: [`LICENSES/pi-coding-agent-MIT.txt`](LICENSES/pi-coding-agent-MIT.txt). |
| [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) | npm dependency of the bundled plugin | `MIT` | https://www.npmjs.com/package/mcp-remote | `.agents/plugins/pibox/package.json` | Dependency of the `@psyb0t/pibox` MIT plugin, not baked into the Docker image. |

pibox itself talks to an Anthropic-compatible LLM endpoint you configure
(`ANTHROPIC_BASE_URL`, e.g. Z.AI or Anthropic direct) — that's a network
service the operator points at, not software this repo distributes. Base-image
tooling (Node.js, Python, git, etc.) comes from the
[aicodebox](https://github.com/psyb0t/docker-aicodebox) base image under its own
notices.

See also [`.agents/plugins/pibox/LICENSE`](.agents/plugins/pibox/LICENSE) for
the MIT text covering the `@psyb0t/pibox` plugin.
