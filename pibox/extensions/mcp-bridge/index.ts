/**
 * pi extension: MCP bridge.
 *
 * Reads `.mcp.json` from the workspace (claude-code schema) and gives pi
 * everything each MCP server offers the model:
 *
 *  - tools, registered as `mcp__<server>__<tool>`. Each tool's input schema
 *    (JSON Schema) is passed through, so the LLM sees the original arguments
 *    and pi forwards them to the MCP server;
 *  - the server's instructions (the `instructions` field of its initialize
 *    result), added to the system prompt before every run. Servers put their
 *    how-to there: which tool to reach for first, which to avoid, what a
 *    multi-step flow looks like. Dropping them leaves the model with tool
 *    names and nothing else;
 *  - resources, for servers that declare them, through two tools per server:
 *    `mcp__<server>__list_resources` and `mcp__<server>__read_resource`.
 *    Servers often keep task guides there and point at them from their
 *    instructions.
 *
 *  .mcp.json schema (subset):
 *    {
 *      "mcpServers": {
 *        "<name>": {
 *          "command": "uvx",
 *          "args": ["mcp-server-fetch"],
 *          "env": { "FOO": "bar" }
 *        },
 *        "<remote>": {
 *          "type": "http",
 *          "url": "https://example.invalid/mcp",
 *          "headers": { "Authorization": "Bearer ${TOKEN}" }
 *        }
 *      }
 *    }
 *
 * An entry with `url` connects over streamable HTTP; `${NAME}` in a header
 * value is replaced with that environment variable. Every other entry is a
 * stdio server.
 */
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

interface ServerSpec {
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  type?: string;
  url?: string;
  headers?: Record<string, string>;
}

interface McpConfig {
  mcpServers?: Record<string, ServerSpec>;
}

// One server's instructions can be long (some are full manuals). Past this
// many characters the rest is cut, with a note, so one server cannot crowd
// the system prompt.
const MAX_INSTRUCTIONS_CHARS = 8000;
// The system prompt section the instructions go in.
const INSTRUCTIONS_SECTION = "mcp_server_instructions";

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

function expandEnv(value: string): string {
  return value.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => process.env[name] ?? "");
}

async function connectServer(name: string, spec: ServerSpec): Promise<Client> {
  const client = new Client(
    { name: `pibox-mcp-bridge:${name}`, version: "0.2.0" },
    { capabilities: {} },
  );
  if (spec.url) {
    const headers = Object.fromEntries(
      Object.entries(spec.headers ?? {}).map(([k, v]) => [k, expandEnv(String(v))]),
    );
    await client.connect(
      new StreamableHTTPClientTransport(new URL(spec.url), { requestInit: { headers } }),
    );
    return client;
  }
  if (!spec.command) {
    throw new Error("entry has neither command nor url");
  }
  await client.connect(
    new StdioClientTransport({
      command: spec.command,
      args: spec.args ?? [],
      env: { ...process.env, ...(spec.env ?? {}) } as Record<string, string>,
    }),
  );
  return client;
}

function sanitize(s: string): string {
  return s.replace(/[^A-Za-z0-9_-]/g, "_");
}

function trimInstructions(text: string): string {
  if (text.length <= MAX_INSTRUCTIONS_CHARS) return text;
  return `${text.slice(0, MAX_INSTRUCTIONS_CHARS)}\n[instructions cut at ${MAX_INSTRUCTIONS_CHARS} characters]`;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function textResult(value: unknown): any {
  return { content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }] };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function errorResult(err: unknown): any {
  return { content: [{ type: "text", text: `MCP error: ${String(err)}` }], isError: true };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function registerResourceTools(pi: any, serverName: string, client: Client, taken: Set<string>): void {
  const prefix = `mcp__${sanitize(serverName)}__`;
  const listName = `${prefix}list_resources`;
  const readName = `${prefix}read_resource`;
  if (!taken.has(listName)) {
    taken.add(listName);
    pi.registerTool({
      name: listName,
      label: `${serverName}: list resources`,
      description: `List the resources the ${serverName} MCP server offers (guides, documents, data), with their URIs. Read one with ${readName}.`,
      parameters: {
        type: "object",
        properties: { cursor: { type: "string", description: "Cursor from a previous page, if any." } },
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      async execute(_toolCallId: string, params: any) {
        try {
          return textResult(await client.listResources(params?.cursor ? { cursor: params.cursor } : {}));
        } catch (err) {
          return errorResult(err);
        }
      },
    });
  }
  if (!taken.has(readName)) {
    taken.add(readName);
    pi.registerTool({
      name: readName,
      label: `${serverName}: read resource`,
      description: `Read a resource from the ${serverName} MCP server by URI, such as a URI its instructions or ${listName} name.`,
      parameters: {
        type: "object",
        properties: { uri: { type: "string", description: "The resource URI." } },
        required: ["uri"],
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      async execute(_toolCallId: string, params: any) {
        try {
          const result = await client.readResource({ uri: String(params?.uri ?? "") });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const texts = (result.contents ?? []).map((c: any) =>
            "text" in c && typeof c.text === "string"
              ? c.text
              : `[${c.mimeType ?? "binary"} resource ${c.uri}, ${String(c.blob ?? "").length} base64 characters]`,
          );
          return textResult(texts.join("\n\n"));
        } catch (err) {
          return errorResult(err);
        }
      },
    });
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function (pi: any) {
  const cwd = process.cwd();
  const cfg = loadConfig(cwd);
  if (!cfg?.mcpServers) {
    return;
  }

  const clients: Client[] = [];
  const instructions: string[] = [];
  const taken = new Set<string>();

  for (const [serverName, spec] of Object.entries(cfg.mcpServers)) {
    let client: Client;
    try {
      client = await connectServer(serverName, spec);
    } catch (err) {
      console.error(`[mcp-bridge] connect ${serverName} failed:`, err);
      continue;
    }
    clients.push(client);

    const text = client.getInstructions()?.trim();
    if (text) {
      instructions.push(
        `### ${serverName} (tools mcp__${sanitize(serverName)}__*)\n${trimInstructions(text)}`,
      );
    }

    let tools;
    try {
      tools = await client.listTools();
    } catch (err) {
      console.error(`[mcp-bridge] listTools ${serverName} failed:`, err);
      continue;
    }

    for (const tool of tools.tools) {
      const toolName = `mcp__${sanitize(serverName)}__${sanitize(tool.name)}`;
      taken.add(toolName);
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
            return errorResult(err);
          }
        },
      });
    }

    if (client.getServerCapabilities()?.resources) {
      registerResourceTools(pi, serverName, client, taken);
    }
  }

  if (instructions.length > 0) {
    const section =
      "Instructions from the MCP servers in this workspace. Follow them when using their tools.\n\n" +
      instructions.join("\n\n");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    pi.on("before_agent_start", async (event: any) => {
      const options = event?.systemPromptOptions;
      if (options?.sections && typeof options.sections === "object") {
        // Pi diffs sections against what the model already has, so this
        // costs one patch the first time and nothing on later runs.
        options.sections[INSTRUCTIONS_SECTION] = section;
        return;
      }
      return { systemPrompt: `${event?.systemPrompt ?? ""}\n\n${section}` };
    });
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
