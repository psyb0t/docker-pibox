/**
 * pi extension: MCP bridge.
 *
 * Reads `.mcp.json` from the workspace (claude-code schema) and registers each
 * MCP server's tools with pi via `pi.registerTool()`. Each tool's input schema
 * (JSON Schema) is wrapped as a passthrough so the LLM sees the original
 * arguments and pi forwards them to the MCP server.
 *
 *  .mcp.json schema (subset):
 *    {
 *      "mcpServers": {
 *        "<name>": {
 *          "command": "uvx",
 *          "args": ["mcp-server-fetch"],
 *          "env": { "FOO": "bar" }
 *        }
 *      }
 *    }
 */
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

interface ServerSpec {
  command: string;
  args?: string[];
  env?: Record<string, string>;
}

interface McpConfig {
  mcpServers?: Record<string, ServerSpec>;
}

function loadConfig(cwd: string): McpConfig | null {
  const path = join(cwd, ".mcp.json");
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8")) as McpConfig;
  } catch (err) {
    console.error(`[mcp-bridge] failed to parse ${path}:`, err);
    return null;
  }
}

async function connectServer(name: string, spec: ServerSpec): Promise<Client> {
  const transport = new StdioClientTransport({
    command: spec.command,
    args: spec.args ?? [],
    env: { ...process.env, ...(spec.env ?? {}) } as Record<string, string>,
  });
  const client = new Client(
    { name: `pibox-mcp-bridge:${name}`, version: "0.1.0" },
    { capabilities: {} },
  );
  await client.connect(transport);
  return client;
}

function sanitize(s: string): string {
  return s.replace(/[^A-Za-z0-9_-]/g, "_");
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function (pi: any) {
  const cwd = process.cwd();
  const cfg = loadConfig(cwd);
  if (!cfg?.mcpServers) {
    return;
  }

  const clients: Client[] = [];

  for (const [serverName, spec] of Object.entries(cfg.mcpServers)) {
    let client: Client;
    try {
      client = await connectServer(serverName, spec);
    } catch (err) {
      console.error(`[mcp-bridge] connect ${serverName} failed:`, err);
      continue;
    }
    clients.push(client);

    let tools;
    try {
      tools = await client.listTools();
    } catch (err) {
      console.error(`[mcp-bridge] listTools ${serverName} failed:`, err);
      continue;
    }

    for (const tool of tools.tools) {
      const toolName = `mcp__${sanitize(serverName)}__${sanitize(tool.name)}`;
      pi.registerTool({
        name: toolName,
        label: `${serverName}: ${tool.name}`,
        description: tool.description ?? `MCP tool from ${serverName}`,
        // pi accepts a raw JSON Schema here; typebox is optional.
        parameters: tool.inputSchema ?? { type: "object", properties: {} },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        async execute(_toolCallId: string, params: any) {
          try {
            const result = await client.callTool({
              name: tool.name,
              arguments: params ?? {},
            });
            return {
              content: result.content ?? [
                { type: "text", text: JSON.stringify(result) },
              ],
              details: { server: serverName, tool: tool.name },
            };
          } catch (err) {
            return {
              content: [
                { type: "text", text: `MCP error: ${String(err)}` },
              ],
              isError: true,
            };
          }
        },
      });
    }
  }

  pi.on("session_shutdown", async () => {
    // Close every MCP client so its stdio subprocess exits and pi can shut
    // down cleanly. Without this, pi -p hangs after printing its final
    // response because the spawned MCP servers keep the event loop alive.
    // Race against a short timeout so a misbehaving subprocess can't block
    // pi's exit indefinitely.
    await Promise.race([
      Promise.all(
        clients.map(async (c) => {
          try {
            await c.close();
          } catch {
            // best-effort
          }
        }),
      ),
      new Promise((resolve) => setTimeout(resolve, 2000)),
    ]);
    // Belt-and-suspenders: pi -p still hangs in some node versions because
    // the MCP transport's child_process keeps the event loop alive even
    // after close(). Force-exit on shutdown — pi has already printed its
    // final output by this point.
    setTimeout(() => process.exit(0), 500).unref();
  });
}
