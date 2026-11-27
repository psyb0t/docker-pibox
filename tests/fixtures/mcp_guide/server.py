#!/usr/bin/env python3
"""MCP server with instructions and a resource, for tests/test_mcp_bridge_context.sh.

    server.py stdio <name>
    server.py http <name> <port> <bearer-token>

Serves its instructions, one resource (`guide://<name>/howto`) and one tool
(`ping`), each carrying a marker built from <name>, so the test can tell
which server's text reached the model and how. In HTTP mode every request
must carry `Authorization: Bearer <bearer-token>`; others get 401.
"""

from __future__ import annotations

import sys

from mcp.server.fastmcp import FastMCP


def build(name: str) -> FastMCP:
    server = FastMCP(
        name,
        instructions=f"INSTRUCTIONS_MARKER_{name}: read guide://{name}/howto before acting.",
    )

    @server.resource(f"guide://{name}/howto", name="howto", description="How to use this server.")
    def howto() -> str:
        return f"RESOURCE_MARKER_{name}: step one, step two."

    @server.tool(description=f"Return TOOL_MARKER_{name}.")
    def ping() -> str:
        return f"TOOL_MARKER_{name}"

    return server


def main() -> int:
    mode, name = sys.argv[1], sys.argv[2]
    server = build(name)
    if mode == "stdio":
        server.run()
        return 0

    port, token = int(sys.argv[3]), sys.argv[4]
    import uvicorn
    from starlette.middleware.base import BaseHTTPMiddleware
    from starlette.responses import PlainTextResponse

    async def check_token(request, call_next):
        if request.headers.get("authorization") != f"Bearer {token}":
            return PlainTextResponse("unauthorized", status_code=401)
        return await call_next(request)

    app = server.streamable_http_app()
    app.add_middleware(BaseHTTPMiddleware, dispatch=check_token)
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")
    return 0


if __name__ == "__main__":
    sys.exit(main())
