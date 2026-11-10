---
title: "Install and the wrapper"
description: "Install the pibox host wrapper, pick the minimal or full image, run Pi interactively or in the background, and upgrade or remove it."
nav_order: 2
---

# Install and the wrapper

pibox ships as two Docker images and a small Bash wrapper, [`wrapper.sh`](https://github.com/psyb0t/docker-pibox/blob/main/wrapper.sh), that you install on the host as `pibox`. The wrapper is the normal way in, for people and for agents. It mounts the current directory, keeps Pi's state between runs and forwards your settings.

## Requirements

- Docker on the host. The installer stops with `Docker is not installed` otherwise.
- `sudo`, because the installer writes the wrapper to `/usr/local/bin` by default.
- `ssh-keygen`, `curl` and `sed`.
- An LLM endpoint for Pi. See [LLM providers](providers.md).

## Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-pibox/main/install.sh | bash

# Install the full image as the wrapper default.
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-pibox/main/install.sh | PIBOX_FULL=1 bash
```

[`install.sh`](https://github.com/psyb0t/docker-pibox/blob/main/install.sh) does this, in order:

1. Creates `~/.pi`, `~/.aicodebox` and `~/.ssh/pibox`.
2. Generates an ed25519 key at `~/.ssh/pibox/id_ed25519` if none exists. The wrapper mounts that directory as the container's `~/.ssh`, so add the public key wherever Pi needs to push or pull.
3. Pulls the selected image.
4. Downloads `wrapper.sh` from the release tag the installer was cut from, writes the chosen image into it, and installs it with `sudo install`.

`PIBOX_FULL=1` goes on the `bash` side of the pipe. It selects the full image and bakes that choice into the installed wrapper.

| Variable | Default | What it does |
| --- | --- | --- |
| `PIBOX_FULL` | `0` | `1` installs the full image as the default |
| `PIBOX_INSTALL_DIR` | `/usr/local/bin` | Directory the wrapper is installed into |
| `PIBOX_BIN_NAME` | `pibox` | Installed command name. The first script argument overrides it |
| `PIBOX_INSTALL_REF` | the installer's release tag | Git ref the wrapper is downloaded from |
| `PIBOX_SRC_LOCAL` | `false` | `true` uses a local image and the `wrapper.sh` next to the installer, without pulling. `make install` sets it |
| `AICODEBOX_MANAGED_INSTALL` | `0` | `1` silences the "keeping existing SSH key" message for automated installs. `PIBOX_MANAGED_INSTALL` is the older name |

## Image variants

| Image | Base | Contents |
| --- | --- | --- |
| `psyb0t/pibox:latest` | `psyb0t/aicodebox:latest` | The minimal image: Pi, the pibox adapter and the shared runtime |
| `psyb0t/pibox:latest-full` | `psyb0t/aicodebox:latest-full` | The same pibox layer on the shared full development toolchain |

Each release also gets `:vX.Y.Z` and `:vX.Y.Z-full` tags, and every push to `main` publishes a per-commit `:sha-<commit>` tag. Both variants build from the same pibox files, see [`Dockerfile`](https://github.com/psyb0t/docker-pibox/blob/main/Dockerfile) and [`Dockerfile.full`](https://github.com/psyb0t/docker-pibox/blob/main/Dockerfile.full).

## Use the wrapper

Run `pibox` from the directory you want Pi to work in. The wrapper mounts that directory at the same absolute path inside the container, persists `~/.pi`, `~/.aicodebox` and `~/.ssh/pibox`, forwards `PIBOX_*` configuration, and passes Pi arguments through unchanged.

```bash
# interactive Pi in the current directory
pibox

# one prompt, then exit
pibox -p "list the files in this workspace"

# a Pi flag passes straight through
pibox -p "review this change" --thinking high

# Pi's own command surface
pibox --help

# the full image for this run only
PIBOX_FULL=1 pibox -p "run the test suite"
```

Without a mode variable, the container runs Pi itself: interactive when there are no arguments, one-shot with `-p`. When a provider is configured and you pass no `--provider` flag, the entrypoint adds the configured provider and model for you.

### Run a long-lived mode

`PIBOX_DETACH=1` starts a named container in the background instead of a disposable foreground one:

```bash
PIBOX_DETACH=1 \
PIBOX_API_MODE=1 \
PIBOX_API_MODE_TOKEN=your-secret \
PIBOX_AVAILABLE_MODELS=your-model-id \
PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic \
PIBOX_PROVIDER_API=anthropic-messages \
PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
PIBOX_PROVIDER_MODEL=your-model-id \
pibox
```

The container name is `pibox-` plus the workspace path with every character outside `A-Za-z0-9_.-` replaced by `_`, unless `PIBOX_CONTAINER_NAME` is set. Stop it with `docker rm -f <name>` before you start another detached container from the same directory.

### What the wrapper passes to Docker

- `--network host`, so a mode's port is reachable on the host without `-p`.
- `--memory` and `--memory-swap` set to `PIBOX_MAX_MEM` (default `10g`).
- The host Docker socket at `/var/run/docker.sock`, so Pi can run containers.
- The workspace, `~/.pi` (as `/home/aicode/.pi`), `~/.aicodebox` (as `/home/aicode/.aicodebox`) and `~/.ssh/pibox` (as `/home/aicode/.ssh`).
- Every `PIBOX_*` variable except the wrapper's own settings below. `PIBOX_ENV_<NAME>` and `AICODEBOX_ENV_<NAME>` arrive in the container as `<NAME>`.
- One bind mount per `PIBOX_MOUNT_<ANY>` or `AICODEBOX_MOUNT_<ANY>` value. A plain path mounts at the same path, `host:container` mounts where you say.
- `-it` when both stdin and stdout are terminals, otherwise `-i`.

### Wrapper settings

These stay on the host. The wrapper reads them and does not forward them.

| Variable | Default | What it does |
| --- | --- | --- |
| `PIBOX_IMAGE` | the installed image | Image to run |
| `PIBOX_FULL` | the installed choice | `0` forces the minimal image, `1` the full image |
| `PIBOX_DETACH` | `0` | `1` runs a named background container |
| `PIBOX_DATA_DIR` | `~/.pi` | Host directory for Pi configuration, auth, extensions and sessions |
| `PIBOX_STATE_DIR` | `~/.aicodebox` | Host directory for mode configuration, history, `bin/` and `init.d/` |
| `PIBOX_SSH_DIR` | `~/.ssh/pibox` | Host directory mounted as the container's `~/.ssh` |
| `PIBOX_MAX_MEM` | `10g` | Container memory and memory-plus-swap limit |
| `PIBOX_CONTAINER_NAME` | `pibox-<workspace path>` | Container name. Also passed in, where it scopes per-container state files |

## Nested launches

Install `pibox`, `codexbox` and `claudebox` in the same command directory, normally `/usr/local/bin`, when one box should be able to start another. Each wrapper finds the sibling wrapper files there and mounts them read-only into its container. A box can then call the sibling command directly. The sibling runs through the host Docker daemon and mounts its own host data directory, because the parent passes the real host paths through the versioned `AICODEBOX_HOST_*` launch context.

Do not set `AICODEBOX_HOST_*` yourself, copy a wrapper into a container, or mount another box's state directory by hand. The wrapper refuses a launch context version it does not know.

## Direct `docker run`

Use plain `docker run` only when you do not want the wrapper, for example on a server where a Compose file owns the container:

```bash
docker run --rm \
  -e PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic \
  -e PIBOX_PROVIDER_API=anthropic-messages \
  -e PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
  -e PIBOX_PROVIDER_MODEL=your-model-id \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"
```

Without the wrapper, the workspace defaults to `/workspace` and nothing persists unless you mount `/home/aicode/.pi` and `/home/aicode/.aicodebox` yourself. [`.env.example`](https://github.com/psyb0t/docker-pibox/blob/main/.env.example) lists the settings for `docker run --env-file`.

## Upgrade

```bash
docker pull psyb0t/pibox:latest
```

Pulling an image does not update the installed wrapper. Run the installer again to get the wrapper from the latest release.

## Remove

```bash
sudo rm /usr/local/bin/pibox
docker rmi psyb0t/pibox:latest
```

Remove `psyb0t/pibox:latest-full` the same way if you pulled it.

Delete `~/.pi`, `~/.aicodebox` and `~/.ssh/pibox` too if you want the state gone. Other aicodebox-based boxes may share `~/.aicodebox`, so check before you remove it.
