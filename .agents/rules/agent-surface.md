# Agent surface

Applies to `.agents/skills/`, `.agents/plugins/`, `.agents/.claude-plugin/`, `.agents/.codex-plugin/` and `server.json`.

- The skill (`.agents/skills/pibox/SKILL.md` and `references/setup.md`) tells agents to run the installed `pibox` wrapper for local work and to use HTTP or MCP only for a server that already runs. Keep that order.
- Every route, tool, variable and default named in the skill must match the code and the docs site. Fix both when either changes.
- The OpenClaw plugin (`.agents/plugins/pibox/`) is MIT, unlike the WTFPL repository. Its `bin/cli.js` only proxies stdio to `$PIBOX_URL/mcp/` through `mcp-remote`; stdout is the MCP channel, so diagnostics go to stderr and the token is never logged.
- `package.json` and `openclaw.plugin.json` keep version `0.0.0`; the publish workflow sets the real version. `.agents/.codex-plugin/plugin.json` carries the release version, written by `make version`.
- `pipeline.yml` publishes exactly the directories listed in `skill_names` and `plugin_names`. Add a new skill or plugin directory to those arrays.
- `server.json` and the Dockerfile `LABEL` share the name `io.github.psyb0t/pibox`. Keep them equal.
