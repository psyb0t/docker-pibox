# pibox

Instructions for coding agents (Codex, Claude Code and others) and for people changing this repository. Users of the image want the documentation site, https://psyb0t.github.io/docker-pibox/, not this file.

## Agent setup

`CLAUDE.md` is a committed symlink to `AGENTS.md`, and `.claude` is a committed symlink to `.agents`, so Claude Code reads the same instructions, rules and skills as Codex. Claude's Edit and Write tools refuse to write through a symlink, so edit `AGENTS.md` and `.agents/rules/*.md` directly.

## What it is

Two Docker images, `psyb0t/pibox:latest` and `psyb0t/pibox:latest-full`, that run [pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) on the shared [aicodebox](https://github.com/psyb0t/docker-aicodebox) base, plus a host wrapper (`pibox`) and an installer. The base owns the entrypoint and every mode: the HTTP API with its OpenAI-compatible endpoint, MCP, Telegram and cron. This repository adds Pi, the `PiAdapter` that drives the Pi CLI for those modes, the `PIBOX_*` names, the upstream provider bootstrap, a Pi extension that bridges workspace MCP servers, a composite GitHub Action, and the agent skill and plugins.

## Architecture

- `wrapper.sh`: the host `pibox` command. Builds `docker run` with the workspace mounted at its own path, `~/.pi`, `~/.aicodebox` and `~/.ssh/pibox` mounted, `--network host`, the Docker socket, forwarded `PIBOX_*` variables, `PIBOX_ENV_*`/`AICODEBOX_ENV_*` passthrough, `*_MOUNT_*` bind mounts and the versioned `AICODEBOX_HOST_*` nested-launch context. Only `PIBOX_*` names cross into the container.
- `install.sh`: creates the host directories and an SSH key, pulls the image, downloads `wrapper.sh` from the release ref in `PIBOX_RELEASE_REF`, writes the chosen image into `PIBOX_INSTALLED_IMAGE`, and installs it with `sudo`.
- `pibox-entrypoint.sh`: the image entrypoint. Copies `PIBOX_X` to `AICODEBOX_X` for the names in `_PIBOX_ALIASES` when the `AICODEBOX_X` value is empty, exports `PIBOX_PROVIDER_API_KEY` as `OPENAI_API_KEY`, runs the provider bootstrap as `aicode`, adds `--provider`/`--model` for plain Pi runs, then execs `/usr/local/bin/aicodebox-entrypoint` from the base.
- `pibox/scripts/setup-provider-env.sh`: validates `PIBOX_PROVIDER_*` or the `ANTHROPIC_*` compatibility settings and writes Pi's `~/.pi/agent/models.json` plus the no-secret marker `~/.pi/agent/pibox-provider.json`. Exits nonzero on invalid settings. Logs JSON to stderr only, so Pi's native stdout stays parseable.
- `pibox/pibox/adapter.py`: `PiAdapter(AgentAdapter)`, selected by `AICODEBOX_ADAPTER=pibox.adapter:PiAdapter`. Builds `pi -p --mode json ...` argv, pins `--provider` from the marker or `ANTHROPIC_BASE_URL`, parses Pi's NDJSON into `RunResult` (text, session id, usage, `provider_error`), turns stream lines into `StreamEvent`s, and lists Pi's state files in `auth_paths`.
- `pibox/init.d/10-pi-extensions.sh`: first-run hook that registers the MCP bridge in `~/.pi/agent/settings.json`.
- `pibox/extensions/mcp-bridge/index.ts`: Pi extension that registers tools from stdio MCP servers in a workspace `.mcp.json` as `mcp__<server>__<tool>`.
- `action.yml` + `scripts/github-action.sh`: composite action that runs Pi through `wrapper.sh` with read-only `/context`, a separate output directory, fresh state, `--no-session`, and the jq filters in `scripts/action-*.jq`.

Request path: client -> base mode (API, MCP, Telegram, cron) -> `PiAdapter.build_argv` -> `pi -p --mode json` with the prompt on stdin -> upstream LLM -> `PiAdapter.parse_output` or `parse_stream_event` -> base mode response.

## Stack

- Base image: `psyb0t/aicodebox:v0.18.4` (minimal) and `:v0.18.4-full`, set by `ARG BASE_IMAGE` in `Dockerfile` and `Dockerfile.full`. The base brings Ubuntu 24.04, Python 3.14, Node.js, Docker CE, `uv` and the `aicodebox` Python package.
- Pi: `@earendil-works/pi-coding-agent`, pinned by `ARG PI_VERSION` (currently `1.1.0`) in both Dockerfiles, installed with `npm install -g --ignore-scripts`.
- Adapter: Python, `requires-python >=3.12`, built with hatchling, installed with `uv pip install --system --no-deps`. No runtime dependencies of its own. Dev group: pytest, ruff, pyright, and `aicodebox` as an editable path to a sibling `../docker-aicodebox` checkout.
- MCP bridge extension: TypeScript loaded by Pi, depends on `@modelcontextprotocol/sdk` (pinned in its `package.json`).
- Shell: Bash with `set -euo pipefail` for wrapper, installer, entrypoint, bootstrap and tests.
- CI: `.github/workflows/pipeline.yml` calling `psyb0t/reusable-github-workflows`.

## Layout

| Path | What it holds |
| --- | --- |
| `Dockerfile`, `Dockerfile.full` | The two image variants. Same pibox layer, different base |
| `pibox-entrypoint.sh` | Image entrypoint: aliasing, provider key, bootstrap, default provider flags |
| `pibox/pyproject.toml` | The single version source (`version = ...`) and the dev tool pins |
| `pibox/pibox/` | The adapter package (`adapter.py`, `__init__.py` reads the version from package metadata) |
| `pibox/tests/` | Adapter unit tests (pytest) |
| `pibox/scripts/` | `setup-provider-env.sh` |
| `pibox/init.d/` | First-run hooks copied to `/aicodebox-init.d/` |
| `pibox/extensions/mcp-bridge/` | The Pi MCP bridge extension |
| `wrapper.sh`, `install.sh` | Host wrapper and installer |
| `action.yml`, `scripts/` | The GitHub Action and its jq filters |
| `tests/` | Bash tests: offline contract tests and the e2e suite run by `test.sh` |
| `tests/fixtures/` | The stub `docker` for action tests and an MCP echo server for e2e |
| `docs/` | The documentation site (GitHub Pages, Jekyll, Just the Docs) |
| `.agents/skills/pibox/` | The agent skill and its `references/setup.md` |
| `.agents/plugins/pibox/` | The OpenClaw stdio-to-HTTP MCP bridge plugin (MIT) |
| `.agents/.claude-plugin/`, `.agents/.codex-plugin/` | Claude Code and Codex plugin manifests |
| `.agents/rules/` | Rules for changing this repository |
| `server.json`, `glama.json` | MCP Registry and Glama metadata |
| `.github/workflows/` | `pipeline.yml` plus repository housekeeping workflows |
| `THIRD_PARTY.md`, `LICENSES/` | Notices for what the images redistribute |

## Commands

Docker, Make, Bash and jq are enough. Lint and the Python tests run in containers.

```bash
make help                  # every target
make build                 # minimal image, :v<VERSION> and :latest
make build-full            # full image, :v<VERSION>-full and :latest-full
make lint                  # shellcheck + ruff + pyright (lint-shell, lint-python)
make test-ci               # offline, credential-free tests, what CI runs
make test-python           # adapter unit tests inside the base image
make test                  # e2e suite, needs .env.test and a real LLM endpoint
make docs                  # build the site into .testing/docs-site
make version V=X.Y.Z       # sync version metadata, no commit, no tag
```

## Project-specific landmines

- The wrapper forwards only `PIBOX_*` variables (minus its own host settings). `ANTHROPIC_*` and other names set on the host never reach the container unless sent as `PIBOX_ENV_<NAME>`.
- A new base setting needs its suffix added to `_PIBOX_ALIASES` in `pibox-entrypoint.sh`, or the `PIBOX_` spelling silently does nothing.
- `make version V=X.Y.Z` is the only way to change the version. It rewrites `pibox/pyproject.toml` (through `uv version`), `pibox/uv.lock`, `.agents/.codex-plugin/plugin.json` and `PIBOX_RELEASE_REF` in `install.sh`. `tests/test_wrapper_install.sh` checks the installer ref against `make version`.
- `make test-unit` and `make pkg-lock` resolve `aicodebox` from `../../docker-aicodebox` relative to `pibox/`. Use `make test-python` when there is no sibling checkout.
- `setup-provider-env.sh` must never write to stdout. `tests/action-provider-output.sh` fails if it does, because the GitHub Action parses Pi's native stdout.
- The prompt goes to Pi on stdin. Never also put it in argv: Pi's `-p` joins stdin and positional text, so the prompt would appear twice.
- With `PIBOX_PROVIDER_*`, `models.json` must hold only the `$OPENAI_API_KEY` reference, never the key. The `ANTHROPIC_*` path writes the token value there, which `docs/security.md` documents. Update that page if either changes.

## Rules

Rules for every change live in `.agents/rules/`, one file per topic. Read the ones that match what you are touching before editing.
