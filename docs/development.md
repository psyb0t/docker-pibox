---
title: "Development"
description: "Build the pibox images, run lint, the offline tests and the e2e suite, understand the CI pipeline and releases, and build this documentation site."
nav_order: 11
---

# Development

Docker, Make, Bash and jq are enough for everything below. Lint and the Python tests run their tools in containers.

## Make targets

```bash
make help                 # every target
make build                # the minimal image, tagged :v<VERSION> and :latest
make build-full           # the full image, tagged :v<VERSION>-full and :latest-full
make build-all            # both variants
make install              # build the minimal image and install the wrapper against it
make install-full         # the same for the full image
make install-wrapper      # install the wrapper against an image you already have
make lint                 # shellcheck, ruff and pyright
make test-ci              # every offline, credential-free test
make test                 # the e2e suite against a real LLM endpoint
make docs                 # build this site into .testing/docs-site
make clean                # remove the built pibox images
```

`VERSION` is read from [`pibox/pyproject.toml`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/pyproject.toml). `make build` pulls `psyb0t/aicodebox:v0.18.4`, the same default as the `BASE_IMAGE` argument in the Dockerfile. To build on a base you built from a local `docker-aicodebox` checkout, set `SKIP_BASE_PULL=1`, or pass `BASE_IMAGE=...`. `make build-full` does the same with `psyb0t/aicodebox:v0.18.4-full`.

## Lint

`make lint` runs two targets:

- `lint-shell` runs shellcheck from a pinned image over every shell script and the test Docker stub.
- `lint-python` runs `ruff check` and `pyright` on the adapter and its tests inside `psyb0t/aicodebox:v0.18.4`, which already has the `aicodebox` package the adapter imports. The tool versions match the `dev` dependency group in `pyproject.toml`.

Both mount the repository read-only and fail on any finding.

## Tests

| Target | Needs | What it checks |
| --- | --- | --- |
| `make test-python` | Docker | Adapter unit tests in [`pibox/tests/`](https://github.com/psyb0t/docker-pibox/tree/main/pibox/tests), run inside the base image |
| `make test-wrapper-install` | Bash | Wrapper and installer behavior against stub `docker`, `curl`, `sudo` and `ssh-keygen` commands |
| `make test-action` | Bash, jq | The GitHub Action script against a stub Docker that replays canned Pi output |
| `make test-entrypoint-identity` | Docker | `PIBOX_GIT_NAME` and `PIBOX_GIT_EMAIL` through the real base entrypoint |
| `make test-action-provider-output` | Docker | Provider setup prints nothing on stdout, so native JSON output stays clean |
| `make test-openclaw-bridge` | Docker, jq | The OpenClaw MCP bridge picks the right endpoint and bearer header, checked against a stub `mcp-remote` |
| `make test-ci` | Docker, Bash, jq | All of the above |
| `make test` | Docker, `.env.test` | The e2e suite |

`make test-unit` runs the adapter tests with `uv` on the host instead. It needs a `docker-aicodebox` checkout next to this repository, because the development lockfile installs `aicodebox` from there.

### The e2e suite

The e2e tests build the image as `pibox:local` and run it against a real LLM endpoint. The Telegram tests use [psyb0t/telethon-plus](https://github.com/psyb0t/docker-telethon-plus) as a real MTProto user client.

```bash
cp .env.test.example .env.test
$EDITOR .env.test
make test
```

Fill in the `ANTHROPIC_*` values in `.env.test`, and optionally the Z.AI Coding Plan, LiteLLM or Telegram settings. The Telegram tests skip themselves when `AICODEBOX_TELEGRAM_MODE_TOKEN` is empty. The generic-provider tests reuse `ANTHROPIC_AUTH_TOKEN` unless `ZAI_CODING_AUTH_TOKEN` is set. [`test.sh`](https://github.com/psyb0t/docker-pibox/blob/main/test.sh) takes test function names to run a subset, `KEEP_IMAGE=1` keeps `pibox:local` afterwards, and `SKIP_BASE_PULL=1` skips pulling the base.

## CI

[`.github/workflows/pipeline.yml`](https://github.com/psyb0t/docker-pibox/blob/main/.github/workflows/pipeline.yml) runs on every push:

| Job | When | What it does |
| --- | --- | --- |
| `code` | Every branch push | `make lint` and `make test-ci`. The e2e suite needs credentials and does not run in CI |
| `call-docker-image-workflow` | After `code`, on `main` | Builds both variants for `linux/amd64` and `linux/arm64`, scans them, and pushes `:latest`, `:latest-full` and `:sha-<commit>` tags |
| `badges` | `main` and tags | Refreshes the version and license badges |
| `wait` | `v*` tags | Waits for the tagged commit's `main` run to succeed |
| `docker-promote` | After `wait` | Promotes that run's image digests to the release tags without rebuilding |
| `release` | After `docker-promote` | Creates the GitHub release from the tag's notes |
| `publish-to-clawhub` | After `release` | Publishes the `pibox` skill and plugin to ClawHub |
| `publish-to-mcp-registry` | After `release` | Publishes `server.json` to the MCP Registry |

Other branches stop after `code`.

## Versions and releases

```bash
make version              # print the current tag
make version V=X.Y.Z      # write X.Y.Z everywhere it is recorded
```

`make version V=X.Y.Z` updates the package version and lockfile, the Codex plugin manifest, and the release ref in `install.sh`, which the installer uses to download the matching wrapper. It does not commit or tag. A release is an annotated `vX.Y.Z` tag on a commit whose `main` run has passed.

## This documentation site

The site is the `docs/` directory, published by GitHub Pages from `main` with the [Just the Docs](https://just-the-docs.com/) theme. `make docs` builds it with the same image GitHub uses, into `.testing/docs-site`. Every page needs front matter with a unique `title` and a `description` of 50 to 170 characters. Links between pages use the relative `.md` path. Links to files outside `docs/` use the full GitHub URL, because a relative link to them breaks on the site.
