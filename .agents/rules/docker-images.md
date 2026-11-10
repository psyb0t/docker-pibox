# Docker images

- `Dockerfile` (minimal, on `psyb0t/aicodebox:v0.18.4`) and `Dockerfile.full` (on `psyb0t/aicodebox:v0.18.4-full`) must install the same pibox layer: Pi at `ARG PI_VERSION`, the adapter from `pibox/` with `uv pip install --system --break-system-packages --no-deps`, the MCP bridge's npm dependencies, `pibox/init.d/` into `/aicodebox-init.d/`, the same `ENV` block (except `PIBOX_IMAGE_VARIANT`) and `pibox-entrypoint.sh` as `ENTRYPOINT`. Change both files together.
- Generic development tools belong in aicodebox, not here. This repository adds only Pi, the adapter and pibox startup behavior.
- Exact npm versions live in `PI_VERSION` in the Dockerfiles and, for `@modelcontextprotocol/sdk`, in `pibox/extensions/mcp-bridge/package.json`.
- Keep `LABEL io.modelcontextprotocol.server.name="io.github.psyb0t/pibox"` in both files; the MCP Registry checks it against `server.json`.
- `AICODEBOX_ADAPTER`, `AICODEBOX_AGENT_BINARY` and `PIBOX_IMAGE_VARIANT` are fixed by the image and are not in `_PIBOX_ALIASES`.
- `.dockerignore` keeps secrets, `docs/`, `.testing/`, Git metadata, caches and local tooling out of the build context. The Dockerfiles copy only `pibox/`, `pibox/init.d/` and `pibox-entrypoint.sh`; anything else they need must be added to the Dockerfiles and kept out of `.dockerignore`.
- Updating a published image does not update an installed wrapper. A change that needs a matching wrapper must say so in the CHANGELOG.
- Base and Pi updates go through the e2e suite (`make test`) before release, since CI runs only the offline tests.
