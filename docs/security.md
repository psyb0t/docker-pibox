---
title: "Security"
description: "What a pibox container can reach, which surfaces are open without a token, where provider keys are stored, and what to set before exposing a port."
nav_order: 8
---

# Security

pibox runs a coding agent that executes commands. Treat anything that can send it a prompt as able to run code in the container, and the container as able to reach the host.

## What the container can reach

Through the wrapper, a pibox container gets:

- **The host Docker socket.** Pi can start containers with any mount, which is root-equivalent on the host. This is how nested launches and Docker-based work function.
- **Host networking.** Every port a mode opens listens on the host's interfaces, not just inside the container.
- **Passwordless sudo** for the `aicode` user inside the container.
- **Your workspace, read-write,** plus `~/.pi`, `~/.aicodebox` and `~/.ssh/pibox`.

The memory limit (`PIBOX_MAX_MEM`, default `10g`) is the only resource cap the wrapper sets. With plain `docker run` you decide each of these yourself. Leave out the socket and use a published port instead of `--network host` when you do not need them.

## Surfaces and their tokens

| Surface | Gate | Open when |
| --- | --- | --- |
| API, OpenAI-compatible endpoint, `/files` | `PIBOX_API_MODE_TOKEN` | The token is empty. `/healthz` is always open |
| MCP | `PIBOX_MCP_MODE_TOKEN`, separate from the API token | The token is empty |
| Telegram | The bot token, `allowed_chats` and per-chat `allowed_users` | `allowed_chats` is empty or missing and `TELEGRAM_CHAT_ID` is unset |
| Cron, interactive, one-shot | Nothing, they take no requests | Not applicable |

An open API or MCP surface gives anyone who can reach the port agent runs and read, write and delete access to the workspace. The MCP token never falls back to the API token. Before you expose a port:

1. Set `PIBOX_API_MODE_TOKEN` and `PIBOX_MCP_MODE_TOKEN` to long random values, different from each other.
2. Bind to loopback or a private network, or put an authenticating proxy in front.
3. For MCP behind a proxy, allow only its exact host and origin, see [MCP mode](modes/mcp.md#reverse-proxies-and-public-hosts).
4. For Telegram, always set `allowed_chats`.

`DELETE /run/{id}`, `DELETE /files/{path}` and the MCP `delete_file` tool have no undo. On a shared server, one caller can cancel another caller's run or delete their files.

The `/files` routes and the MCP file tools reject paths that leave the workspace root. That protects the file API, not the agent: `run_prompt` and `/run` let Pi do anything the container can.

## Secrets on disk

- With `PIBOX_PROVIDER_*`, the key reaches Pi as the `OPENAI_API_KEY` environment variable, and `~/.pi/agent/models.json` holds only the reference `$OPENAI_API_KEY`.
- With the `ANTHROPIC_*` compatibility path, startup writes the token itself into `~/.pi/agent/models.json`. The file is mode `600`, but it sits in the host directory the wrapper mounts, `PIBOX_DATA_DIR` (`~/.pi`), and survives the container.
- The installer creates an SSH key without a passphrase at `~/.ssh/pibox/id_ed25519`, and the wrapper mounts that directory into every pibox container. Give that key only the access Pi needs.

## The GitHub Action

The action runs the same wrapper on the runner, so it inherits the Docker socket and host networking. Use it only for trusted workloads on disposable runners. [GitHub Action](github-action.md#runner-trust) lists the precautions the action takes and the ones left to you.

## Model output

Text and files that Pi produces are untrusted. Do not execute them, or paste them into shell source, without checking them first.
