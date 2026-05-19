#!/usr/bin/env python3
"""Minimal stdio MCP server used by test_mcp_bridge_pulls_workspace_mcp_json.

Exposes one tool, `echo`, that returns its `text` argument prefixed with a
unique marker. The test asserts the marker appears in pi's final response,
which can only happen if the mcp-bridge extension loaded `.mcp.json`,
connected to this server, registered the tool, and pi actually invoked it.
"""

import asyncio

import mcp.types as types
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions
from mcp.server.stdio import stdio_server

server: Server = Server("testsrv")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="echo",
            description=(
                "Return the input text prefixed with the marker "
                "MCP_BRIDGE_OK. The ONLY way to produce that marker is "
                "to call this tool."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "text": {"type": "string", "description": "text to echo"},
                },
                "required": ["text"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    if name != "echo":
        raise ValueError(f"unknown tool: {name}")
    text = arguments.get("text", "")
    return [types.TextContent(type="text", text=f"MCP_BRIDGE_OK:{text}")]


async def main() -> None:
    async with stdio_server() as (r, w):
        await server.run(
            r,
            w,
            InitializationOptions(
                server_name="testsrv",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    asyncio.run(main())
