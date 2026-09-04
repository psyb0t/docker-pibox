# Changelog

All notable changes per release. Versions follow [semver](https://semver.org)
pre-1.0 conventions: minor bumps may include breaking REST changes (called
out explicitly), patch bumps are docs / build / fixes only.

## v0.15.12, 2026-09-04

- Bumped the digest-pinned base image to `psyb0t/aicodebox:v0.14.6`, which adds independent event retention through `eventMode` and the stable full-event envelope to `POST /run`.
- Documented how `eventMode: "full"` preserves native Pi thinking, tool lifecycle, retry, compaction, and provider records.
- Added adapter regression tests proving full-event mode keeps Pi's JSON stream and preserves native thinking and tool records unchanged.
- Added `make pkg-lock` and refreshed the lockfile against aicodebox v0.14.6.

## v0.15.11 — 2026-08-13

Fixes the GLM / Anthropic-provider auth that the pi 0.84.0 bump in v0.15.10 broke.

- `scripts/setup-anthropic-baseurl.sh` now writes the RESOLVED auth-token value
  into pi's `models.json` provider `apiKey`, not the env-var name. pi >= 0.84.0
  (shipped in v0.15.10) sends `apiKey` literally — it no longer resolves an
  env-var name the way pi <= 0.75 did — so writing `ANTHROPIC_AUTH_TOKEN` made
  every request 401 upstream. Any pibox pointed at an Anthropic-compatible
  endpoint via `ANTHROPIC_BASE_URL` (Z.AI GLM, proxies) was affected since
  v0.15.10.
- Added `tests/test_glm.sh`: a regression guard that boots the container and
  asserts (1) the on-disk provider `apiKey` is the resolved token, not the bare
  variable name, and (2) a real completion comes back end-to-end. Would have
  caught the v0.15.10 break.

## v0.15.10 — 2026-08-13

Refreshes the pi coding agent and the aicodebox base, adds one-command version
bumping, and realigns the packaged version metadata with the release tag.

- **pi coding agent upgraded `0.75.3` → `0.84.0`** (`@earendil-works/pi-coding-agent`).
  This is a large jump across many pi releases — the container build and tests
  exercise the pi integration, but verify your workflows if you depend on
  specific pi behaviour.
- Base image bumped to `psyb0t/aicodebox:v0.14.5`, which fixes the API-mode
  container restart-looping while an agent request runs — the agent subprocess
  is now spawned in its own session/process group, so a signal it (or a tool it
  spawned) delivers no longer reaches the uvicorn PID 1. Inherited from the
  base; pibox itself is unchanged.
- Added `make version V=X.Y.Z`, which sets the version everywhere it lives
  (`pibox/pyproject.toml`, `pibox/uv.lock`, `.agents/.codex-plugin/plugin.json`),
  commits, and tags in one command. `make version` with no argument still prints
  the current version.
- Realigned `pibox/pyproject.toml` with the release tag — it had drifted to
  `0.14.0` because the published image is tagged from the git tag, not from
  `pyproject.toml`. `make version` brings it back in step and keeps it there.

## v0.15.9 — 2026-08-09

Documentation only. No code in this repo changed.

- Added `docs/modes/` — one page per mode (`api.md`, `telegram.md`, `cron.md`, `mcp.md`), each carrying that mode's full setup, compose example, and its own environment-variable table. The README's `## Modes` section is now a short summary linking to them, and the Table of Contents lists each page (MCP mode was previously absent from it).
- Per-mode environment variables lived in two places: the `## Modes` prose and the `## Configuration` tables. They now live once, on each mode's page; `## Configuration` keeps the naming convention, the mode-flag table, and workspace/runtime vars, and links down for the rest. The duplication was a drift source, not a convenience.
- The opening line promised "five ways in" and then listed six. It no longer commits to a count it does not keep, and names the OpenAI-compatible endpoint as part of the HTTP API rather than as a separate way in.
- `.agents/.codex-plugin/plugin.json` was left at `0.15.7`. Nothing rewrites this file — the ClawHub workflow only rewrites `.agents/plugins/*/package.json` — so it is bumped by hand and is now back in step with the tag.

## v0.15.8 — 2026-08-01

CI plumbing only. No code in this repo changed — every commit in this release
touches `.github/workflows/`.

- The pipeline was split: building and publishing stay in `pipeline.yml`, and
  everything that leaves the host now lives beside it in `mirror-and-archive.yml`.
- The repo is mirrored to Codeberg as well as GitLab.
- It is archived to the Wayback Machine, Software Heritage and archive.org.
- Issues opened on either mirror are copied back to GitHub every six hours, and
  closed here when the original closes.
- Pull requests are switched off on the mirrors — they are force-pushed from
  GitHub, so anything merged there would be destroyed by the next sync. Issues
  and forking stay enabled.

## v0.15.7 — 2026-07-27

Codex install command was missing from the README. Documentation only, no behavior change.

- The Codex subsection under `## Agent integrations` only told the reader to run `codex
  plugin marketplace add psyb0t/agents` and stopped — it never showed the actual install
  command. Added the missing line: `codex plugin add pibox@psyb0t`.
- Clarified the invocation prose to distinguish the two ways Codex picks up the skill:
  installed via the marketplace it invokes as `$pibox:pibox`; picked up automatically with
  no install from a repo's own `.agents/skills/` it invokes as plain `$pibox`.

## v0.15.6 — 2026-07-27

Agent-integration manifests. Documentation only, no behavior change.

- Added `.agents/.claude-plugin/plugin.json` — makes the existing `pibox` skill installable
  natively as a Claude Code plugin via `claude plugin marketplace add psyb0t/agents` +
  `claude plugin install pibox@psyb0t`. Declares `userConfig` for the pibox URL and the
  API/MCP bearer tokens so Claude Code prompts for them instead of requiring exported env vars.
- Added `.agents/.codex-plugin/plugin.json` — the matching Codex manifest (`codex plugin
  marketplace add psyb0t/agents`), pointing at the same `.agents/skills/`.
- Added a `## Agent integrations` section to the README (with Table of Contents entry) documenting
  the Claude Code, Codex, and OpenClaw (skill + MCP-bridge plugin) install commands in one place.

## v0.15.5 — 2026-07-27

- Added a GitHub Actions CI status badge to the README.

## v0.15.4 — 2026-07-27

- Added self-hosted version and license badges plus a Docker Hub pulls badge; wired a badges job into pipeline.yml.

## v0.15.3 — 2026-07-26

Listed on the official MCP Registry — no behavior change.

- Added `server.json` — published to the official Model Context Protocol Registry (`registry.modelcontextprotocol.io`) as `io.github.psyb0t/pibox`, pointing at the `psyb0t/pibox` Docker image. Ownership is proven by an `io.modelcontextprotocol.server.name` LABEL on the image; publishing runs on tag pushes via GitHub OIDC (secretless). Also added a `glama.json` maintainer claim.

## v0.15.2 — 2026-07-26

Third-party license notices. Documentation only, no behavior change.

- Added `THIRD_PARTY.md` + `LICENSES/` documenting the image-baked pi coding agent (`@earendil-works/pi-coding-agent`, MIT). The project's own code stays WTFPL.

## v0.15.1 — 2026-07-26

Skill docs hardening — no behavior change.

- **`pibox` skill docs hardened** (`.agents/skills/pibox/SKILL.md`, `references/setup.md`): added a `Security & safety` section plus inline warnings at every relevant spot — explicit "empty token = unauthenticated" callouts for `PIBOX_API_MODE_TOKEN` and `PIBOX_MCP_MODE_TOKEN`, and destructive-operation guardrails on `DELETE /run/{id}`, `DELETE /files/{path}`, and the MCP `delete_file` tool (agent must never call these without an explicit user request for that exact action, confirm target, no bulk-delete, admin-only on shared instances).
- Docs only — no code, wire, or default-value changes.

## v0.15.0 — 2026-07-25

ClawHub skill + plugin, and README/Makefile corrections.

- **New `pibox` agent skill** (`.agents/skills/pibox/`) documenting every mode the box exposes — interactive shell, one-shot exec, the REST API, the OpenAI-compatible `/openai/v1/chat/completions` endpoint, the streamable-HTTP MCP server, the Telegram bot, and the cron scheduler.
- **New `@psyb0t/pibox` code plugin** (`.agents/plugins/pibox/`) — a stdio↔HTTP MCP bridge (`mcp-remote`) so an OpenClaw/MCP agent can drive a running box's `/mcp` endpoint. MIT-licensed.
- **CI publishes both to ClawHub** on tag pushes via the reusable `clawhub-publish.yml` (validate → publish, skills + plugins).
- **README corrected**: `POST /run` takes `async` / `fireAndForget` in the body (there is no `/run/async`); async polling is `GET /run/result?runId=<id>`; cancel is `DELETE /run/{id}`; `make build` now pulls the published `psyb0t/aicodebox` base (`VERSION` from `pibox/pyproject.toml`; `SKIP_BASE_PULL=1` / `BASE_IMAGE=…` to override).

## v0.14.0 — 2026-07-20

Track aicodebox v0.14.0 — `stream:true` for tool-calling and schema modes
on `/openai/v1/chat/completions` no longer returns `400`; it now serves
as **buffered SSE**.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` → `psyb0t/aicodebox:v0.14.0` (was `v0.13.0`). Tag-only —
  v0.14.0 image not yet on Docker Hub at release time; digest pin
  pending registry push.
- **Behavior change (via the base).** A tool call or a schema-validated
  answer only exists once the full response is computed, so it can't
  stream token-by-token. Previously `stream:true` combined with `tools`
  or `response_format` returned `400`. Now the base computes the whole
  answer non-streamed and replays it as a single-shot SSE stream
  (`text/event-stream`): an opening `{"role":"assistant"}` chunk, one
  `content` delta (schema/text) or one `tool_calls` delta (carrying the
  `index` clients need to reconstruct them), the finish chunk
  (`finish_reason:"stop"` or `"tool_calls"`), then `data: [DONE]`.
  **Breaking** for callers that special-cased the old `400` — the
  client's streaming SDK is satisfied, it just isn't token-incremental
  for these two modes. Plain chat still streams incrementally as
  before. Genuine failures still surface as HTTP errors (schema
  exhausted → `422`, agent crash → `500`) rather than a stream.
- **PiAdapter unchanged.** The buffered-SSE replay is entirely base-side
  (the OAI route gates the existing incremental streaming path to plain
  chat only, and replays finished tool/schema answers as SSE chunks
  instead). The adapter contract is unaffected.
- **Tests.** `test_api_oai_stream_schema_rejected` (which asserted the
  removed `400`) is replaced by
  `test_api_oai_stream_schema_buffers_to_sse` — a real round-trip
  against the configured GLM model that sends `stream:true` +
  `x-aicodebox-json-schema`, then asserts `200`, a
  `text/event-stream` body carrying `chat.completion.chunk` objects,
  `finish_reason:"stop"`, `data: [DONE]`, and that the single content
  delta carries the schema-matching answer.
- All 49 tests pass against the new build
  (`SKIP_BUILD=1 SKIP_BASE_PULL=1 ./test.sh`).
- Minor bump (v0.13.0 → v0.14.0) — the OAI wire behavior for
  `stream:true` + `tools`/`response_format` changed from `400` to a
  `200` SSE stream.

## v0.13.0 — 2026-07-18

Track aicodebox v0.13.0 — OpenAI-style client-executed tool calling on
`/openai/v1/chat/completions`, composable with `response_format` so an
agentic multi-tool flow can end in a schema-validated structured JSON
reply.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` → `psyb0t/aicodebox:v0.13.0` (was `v0.11.0`). Tag-only —
  v0.13.0 image not yet on Docker Hub at release time; digest pin
  pending registry push. This jump folds in two base releases:
  - **v0.12.0** — client-executed tool calling. A client that sends
    `tools` gets `tool_calls` back (`finish_reason=tool_calls`), runs
    the tool in its own environment, and sends the result back —
    stateless, exactly like OpenAI. `tool_choice`
    (auto/none/required/specific) is honored. In tool mode the harness's
    own internal tools default OFF (the machine acts as a pure
    function-calling model); `x-aicodebox-no-tools: 0` re-enables the
    hybrid. Also: tools are now disabled by default on the OAI endpoint
    for non-tool requests too (an OpenAI SDK caller can't know the agent
    can touch the filesystem/shell) — opt in with
    `x-aicodebox-no-tools: false` or an `x-aicodebox-tools-allowlist`.
  - **v0.13.0** — `tools` + `response_format` now COMPOSE in one
    request (v0.12.0 rejected the pairing with `400`). They describe
    different turn types: a tool-call turn → `tool_calls` (NOT
    schema-checked); the final-answer turn (model stops calling tools)
    → validated against the schema with the same up-to-3-retry
    self-correction (exhausted → `422`, crash → `500`). `tools` +
    `stream:true` still → `400`.
- **PiAdapter unchanged.** Tool calling and schema composition are
  entirely base-side (system-prompt directive injection + response
  shaping on the OAI route). pi runs its own internal tools; the base
  bridges the OpenAI client-executed-tools contract on top. The adapter
  contract is unaffected.
- **Tests.** Two new real end-to-end tool-calling tests against the
  configured GLM model (`$TEST_MODEL` via Z.AI), replacing the old
  `test_api_oai_reject_tools` (which asserted the removed `400`):
  - `test_api_oai_tool_calling` — a full two-round-trip: model emits a
    `get_weather` tool call, the test runs it and feeds the result back,
    model folds it into a final answer with `finish_reason=stop`.
  - `test_api_oai_tools_plus_schema` — the composed flow: `tools` +
    `response_format` in one request, model calls `get_weather` for two
    cities (tool turn NOT schema-checked), then emits a
    schema-validated structured JSON final answer with the fed-back
    values.
- All 49 tests pass against the new build
  (`SKIP_BUILD=1 SKIP_BASE_PULL=1 ./test.sh`).
- Minor bump (v0.12.0 → v0.13.0) — new OAI request/response surface
  (`tools`, `tool_choice`, composed `tools`+`response_format`);
  backwards compatible for callers that don't send `tools`, except the
  OAI endpoint now defaults to tools-off (opt back in per request).

## v0.12.0 — 2026-07-09

Track aicodebox v0.11.0 and populate the new `provider_error` field —
upstream provider errors (content-safety rejections, rate limits, auth
failures) now surface as HTTP `400` on `/openai/v1/chat/completions`
instead of a `200` with empty `text`.

- **Base image bump.** `Dockerfile` + `Makefile` `BASE_IMAGE` →
  `psyb0t/aicodebox:v0.11.0`, digest-pinned to the multi-arch manifest
  index `sha256:9d5406fe2a336e97a41dd847ef55614386e68d6f3d7b331fa717678`
  `1571efd5a` (v0.11.0 is on Docker Hub, so the pin the earlier releases
  deferred is now in place). `tests/common.sh` uses the plain
  `v0.11.0` tag.
- **PiAdapter change.** `parse_output` now passes the captured
  provider-error detail through on `RunResult.provider_error` (the base
  field added in aicodebox v0.11.0). pi reports an upstream rejection as
  `stopReason=error` + `errorMessage` on the assistant turn; the adapter
  already logged that at WARN, and now also forwards it so the OAI route
  can turn it into a proper error response.
- **Behavior change (via the base).** When the model provider rejects a
  request (e.g. a `[1301]` content-safety error) the agent process still
  exits `0` with empty text. Previously the OAI endpoint returned a
  `200` with `""` content — an empty-but-valid completion that hid the
  failure. Now the base checks `provider_error` ahead of the exit-code /
  parse-error handling and returns HTTP `400` with the provider's
  message, and the schema-mode retry helper stops re-prompting the
  moment a provider error appears (replaying the same prompt into the
  same filter never helps). **Breaking** for callers that treated a
  `200`-with-empty-text as success.
- All 48 tests pass against the new build
  (`SKIP_BUILD=1 SKIP_BASE_PULL=1 ./test.sh`).
- Minor bump (v0.11.3 → v0.12.0) — the OAI wire behavior on provider
  errors changed from `200` to `400`.

## v0.11.3 — 2026-06-30

Track aicodebox v0.10.1 — periodic safety-net purge for orphaned
ephemeral workspaces.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` → `psyb0t/aicodebox:v0.10.1` (was `v0.10.0`). Tag-only —
  v0.10.1 image not yet on Docker Hub at release time; digest pin
  pending registry push.
- **Inherited operational fix.** v0.10.0 cleans up ephemeral
  `/tmp/aicodebox/<uuid>/` workspaces in `finally` after every request
  code path. But `finally` doesn't run on SIGKILL, on container
  restart with a leftover root, or when the cleanup helper itself
  raises. v0.10.1 adds a periodic sweep (every 10 minutes) that
  removes ephemeral-workspace directories older than 1h (covers
  worst-case schema runs 10x over). Bonus: `purge_stale_uploads`
  now also logs a WARN on skipped/failed entries instead of silently
  swallowing OSError.
- PiAdapter unchanged. /run callers unchanged. Adapter contract
  unaffected — internal base-side periodic-purge wiring only.
- All 48 tests pass against the new build
  (`SKIP_BUILD=1 SKIP_BASE_PULL=1 ./test.sh`).
- Patch bump (v0.11.2 → v0.11.3) — pure base-side operational fix
  tracking, no pibox-side wire/API changes.

## v0.11.2 — 2026-06-27

Track aicodebox v0.10.0 — cheap schema retries via ephemeral workspace +
session-continue on `/openai/v1/chat/completions`.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` → `psyb0t/aicodebox:v0.10.0` (was `v0.9.1`). Tag-only —
  v0.10.0 image not yet on Docker Hub at release time; digest pin
  pending registry push.
- **Inherited optimization.** Schema-mode retries on
  `/openai/v1/chat/completions` no longer replay the full original
  prompt:
  - Schema request + no `x-aicodebox-workspace` header → base allocates
    ephemeral `/tmp/aicodebox/<uuid>/` (mode `0o700`), cleaned up in
    `finally` after every code path (200 / 422 / 500).
  - `run_with_json_retry` runs retries with `no_continue=False` +
    minimal corrective prompt (error + directive + schema) instead of
    replaying the full original input.
  - Caller-provided workspace → fresh-session retry fallback (v0.9.1
    behavior); isolation guarantees only on workspaces the base owns.
  - Cost: a 100k-token request needing 3 retries paid 400k input tokens
    before v0.10.0; now ~100k + ~1.5k corrective overhead per retry.
  - `/run` callers unchanged — `run_with_json_retry` gained
    `continue_session_on_retry` (default `False`) that the OAI route
    flips to `True` when it owns an ephemeral workspace.
- PiAdapter unchanged. The `--continue` vs `--no-session` argv branch
  already maps to `req.no_continue` correctly; the base controls which
  value to pass.
- All 48 tests pass against the new build
  (`SKIP_BUILD=1 SKIP_BASE_PULL=1 ./test.sh`).
- Patch bump (v0.11.1 → v0.11.2) — pure base-side optimization
  tracking, no pibox-side wire/API changes.

## v0.11.1 — 2026-06-22

Track aicodebox v0.9.1 — schema-mode retry prompt now carries the
original task so the fresh-session retry agent has context to correct
informed.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` → `psyb0t/aicodebox:v0.9.1` (was `v0.9.0`). Tag-only —
  v0.9.1 image not yet on Docker Hub at release time; digest pin
  pending registry push.
- **Inherited bug fix.** Schema-mode retries (since v0.8.0) run with
  `no_continue=True` for fresh-session correction. Through v0.9.0 the
  retry prompt carried only the bad output + parse error + schema —
  NO original task. For schemas where correction depends on task
  context (large enum picks, allowed-values lists, domain identifiers)
  the retry agent had ~zero chance of correcting. v0.9.1 re-states the
  original task in the retry body. Net effect: retries succeed more
  often, so cumulative token usage on retrying schema runs should DROP
  even though each individual retry prompt is slightly longer.
- PiAdapter unchanged. No new tests (existing schema-via-`/run` +
  schema-via-OAI tests still exercise the path end-to-end). 48/48 green.
- Pibox version bump via the single-source pattern (0.11.0 → 0.11.1,
  patch — pure base bug-fix tracking, no pibox-side API changes).

## v0.11.0 — 2026-06-19

Track aicodebox v0.9.0 — OpenAI-standard `response_format` body field on
`/openai/v1/chat/completions`. Stock OAI SDKs (LangChain, openai-python,
LlamaIndex) can now drive schema enforcement without our proprietary
`x-aicodebox-json-schema` header.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` pinned to `psyb0t/aicodebox:v0.9.0` (was `v0.8.3`).
  Tag-only — v0.9.0 image not yet on Docker Hub at release time;
  digest pin pending registry push.
- **Breaking (OAI schema-mode callers).** `response_format` body field
  is now honoured by the base. Callers that depended on the previous
  400 rejection for `response_format={"type":"json_object"}` as a
  control-flow signal must update — it's now a valid request that
  runs the schema-validation retry helper.
  - `type=text` → no schema (default, unchanged)
  - `type=json_object` → permissive `{"type":"object"}` constraint —
    forces parseable JSON without restricting structure
  - `type=json_schema` → uses `response_format.json_schema.schema`
    (OpenAI structured-outputs shape) as the constraint
  - Failure semantics unchanged: success → canonical re-serialized
    JSON content; retries exhausted → 422; agent crash → 500;
    `stream:true + schema` → 400.
  - Precedence when both body and `x-aicodebox-json-schema` header
    are set: body wins (OAI standard); base logs the conflict at INFO.
- **Tests.**
  - `test_api_oai_reject_tools`: dropped the
    `response_format=json_object → 400` assertion (no longer rejected;
    that exact scenario is now the happy path of the new test below).
    `tools[]` still rejected (pi runs its own tool surface).
  - `test_api_oai_response_format_json_object` (new): asserts the body
    field forces JSON output, content is canonical (starts with `{`),
    schema-conforming `{"word":"HELLO"}`.
  - `test_api_oai_response_format_json_schema` (new): asserts the
    structured-outputs shape (`type=json_schema` +
    `json_schema.schema=...`) drives validation end-to-end.
- All 48 tests pass against the new build
  (`SKIP_BUILD=1 SKIP_BASE_PULL=1 ./test.sh`).
- PiAdapter unchanged — base v0.9.0 only added route-level body
  parsing. Adapter contract was already wide enough.
- No README sync needed; the `/run` body field list is unchanged. The
  README's "OpenAI-compatible" section already promises OAI-shape
  compat, which `response_format` body field strengthens.

## v0.10.0 — 2026-06-19

Track aicodebox v0.8.3 — base-side schema-mode logging + single-source
versioning. Add reconstruction-grade logging to PiAdapter. Adopt the same
single-source versioning pattern across pibox.

- **Base image bump.** `Dockerfile` + `Makefile` + `tests/common.sh`
  `BASE_IMAGE` pinned to `psyb0t/aicodebox:v0.8.3` (was `v0.8.1@sha256:...`).
  Tag-only this time — the v0.8.3 image is not yet on Docker Hub at release
  time; digest pin will be added once it's pushed. v0.8.x base changes
  inherited: reconstruction-grade logs on the schema-mode path (v0.8.2)
  and single-source `__version__` via `importlib.metadata` (v0.8.3).
- **PiAdapter logging (new).** Adapter was previously silent — zero
  `logging` calls. Brought up to spec against
  reconstruction-grade detail (structured DEBUG/INFO/WARN with file/line/func metadata):
  - `pibox.adapter` logger; uses the base's existing `_JsonFormatter`,
    no new dependency.
  - `validate(req)`: DEBUG entry summarising output_format / thinking /
    no_tools / tools_allowlist / json_schema / resume flags. WARN on
    each rejected combination (unknown thinking level, tools_allowlist
    × no_tools mutex) with the rejected value.
  - `build_argv(req)`: DEBUG decision-summary (model, thinking, session
    choice = resume|no-session|continue, tools choice =
    none|allowlist|default, extra_args count, forced-provider-anthropic
    flag, final argc). Plus a separate DEBUG when the JSON-schema
    system-prompt fragment is bolted on (logs schema_keys, never the
    schema body — keeps log volume bounded).
  - `parse_output(stdout, req)`: WARN per malformed NDJSON line
    (previously silent-swallowed).
    WARN when an assistant turn carries `stopReason=error` +
    `errorMessage` — previously these went undiagnosed (the 401 / token
    / ByteString failures customers hit returned empty `.text` with no
    log trail). INFO summary: text_len, session_id, lines, decoded,
    decode_errors, usage_keys, provider_error flag.
  - `parse_events(stdout, req)`: WARN per malformed line + per non-dict
    event. DEBUG summary (events, decode_errors, non_dict).
  - `parse_stream_event(line, req)`: WARN per malformed line.
  - Security: NO tokens / NO secrets / NO full prompts / NO full
    schemas in any log line. Provider errors truncated to ≤200 chars;
    sample lines truncated to ≤80 chars; only schema KEYS (not values)
    are surfaced.
- **Single-source versioning.**
  - `pibox/pyproject.toml` `[project] version` is now THE canonical
    version source. Bumped to `0.10.0` (was stuck at `0.1.0` since
    initial release — same drift bug aicodebox fixed in v0.8.3).
  - `pibox/pibox/__init__.py` reads `__version__` via
    `importlib.metadata.version("pibox")`. Fallback sentinel
    `0.0.0+source` when running from a source checkout so the drift
    is OBVIOUS rather than silently reporting a stale hardcoded number.
  - `Makefile` derives `TAG` from `pyproject.toml` via `awk`, tags
    BOTH `:v0.10.0` AND `:latest` on every `make build`. New
    `make version` target prints what would be tagged. Override at
    build time via `VERSION=… make build` for one-offs.
- **Makefile build resilience.** `pull-base` honors `SKIP_BASE_PULL=1`
  (mirrors `tests/common.sh`'s existing knob) — needed because the
  v0.8.3 base wasn't on the registry at release time. The local image
  is used when set; bails clearly when it's also missing.
- **All 46 tests pass** against the new build (`SKIP_BUILD=1
  SKIP_BASE_PULL=1 ./test.sh`).
- PiAdapter functional contract unchanged. No `/run` / OAI / MCP /
  files-API wire changes. No doc-sync needed beyond the CHANGELOG.

## v0.9.0 — 2026-06-18

Track aicodebox v0.8.1 — schema validation actually runs on OAI, per-attempt
breakdown, agent-crash vs schema-exhaustion split.

- **Base image bump.** `Dockerfile` + `Makefile` `BASE_IMAGE` pinned to
  `psyb0t/aicodebox:v0.8.1@sha256:3a234d49d348b3182897c781be6b364e6b5d17784c4b70ac12df132e066d6dac`
  (was `psyb0t/aicodebox:latest`). Digest pin guards against tag-rebuild
  drift — `:latest` and `:v0.8.1` currently resolve to different image IDs
  on Docker Hub.
- **Breaking (schema callers via OAI).** `POST /openai/v1/chat/completions`
  with `x-aicodebox-json-schema` now runs the schema-validation retry
  helper (was plumbed in v0.7.0 but never actually validated). On success
  `message.content` is the canonical re-serialized JSON (no markdown
  fences, no surrounding prose). On schema-exhaustion: `422`. On agent
  crash mid-run: `500`. `stream:true + x-aicodebox-json-schema` is
  rejected at the route with `400` (mid-stream validation has no clean
  recovery path).
- **Additive — per-attempt breakdown.** `/run` schema responses now carry
  `.attempts` (one entry per attempt: `{index, usage, exitCode, parseError}`).
  OAI envelope carries `.aicodebox_attempts` as a vendor extension.
  Top-level `.usage` is summed across attempts so the billable total
  reflects every retry.
- **Tests (additive).** `test_api_run_json_mode` now also asserts
  `.attempts[0]` has the v0.8.1 shape. `test_api_oai_header_json_schema`
  tightened to assert canonical content (starts with `{`, no fences) +
  `.aicodebox_attempts`. New `test_api_oai_stream_schema_rejected` covers
  the `stream + schema → 400` rule.
- PiAdapter unchanged — base widened `RunResult` with `.attempts` but
  the adapter only populates `text`/`session_id`/`usage`; the base writes
  `.attempts` after retries.

## v0.8.0 — 2026-06-08

Test the aicodebox v0.7.0 `x-aicodebox-*` OAI headers.

- aicodebox v0.7.0 exposed six more `RunSpec` knobs as custom headers on
  `POST /openai/v1/chat/completions`. PiAdapter already consumed all six
  on `RunRequest`, so pibox gets them for free.
- New header surface (all delivered by the base, validated end-to-end by
  pibox's tests):
  - `x-aicodebox-json-schema` — JSON object; flips internal
    `output_format` to `json-verbose` so the assistant's final turn is
    schema-validated (up to 3 self-correction retries).
  - `x-aicodebox-resume` — adapter session id to resume.
  - `x-aicodebox-extra-args` — JSON array OR comma-separated string.
  - `x-aicodebox-timeout-seconds` — int per-run wall-clock cap.
  - `x-aicodebox-tools-allowlist` — JSON array OR comma-separated string.
  - `x-aicodebox-no-tools` — `1`/`true`/`yes`.
- Three new tests: schema header happy-path, schema header
  malformed-JSON rejection (400 with header name in detail), and
  extra-args header round-trip in BOTH CSV + JSON-array forms.
- Additive, no breaking changes.

## v0.7.0 — 2026-05-23

Align with aicodebox v0.6.0 — `jsonSchema` is the only dial.

- **Breaking (`/run` callers).** `verbose` request field removed.
  aicodebox v0.6.0 collapsed the v0.5.0 (`verbose × jsonSchema`) matrix
  to one flag. Migration:
  - `verbose: true` (events + sessionId + usage) → set
    `jsonSchema: {"type": "object"}` (or any real schema you want
    validated).
  - Schema-set responses now also carry `text`, `events`, `sessionId`,
    `usage` alongside `json`.
  - Lean default (no schema): `{runId, workspace, exitCode, text}`.
- Pydantic's `extra=ignore` default means stale callers passing
  `verbose: true` silently drop the field — no 422 on the vestigial flag.
- PiAdapter: no code changes; comment refresh only. Server derives
  `output_format=json-verbose` for schema-set runs and `text` otherwise.
- Streaming surfaces unchanged. `/run` is one-shot (events buffered in
  the final JSON). `/openai/v1/chat/completions` with `stream:true` emits
  per-token SSE deltas via `parse_stream_event`.

## v0.6.0 — 2026-05-23

Align with aicodebox v0.5.0 — `verbose` + `jsonSchema` contract.

- **Breaking (`/run` callers).** `outputFormat` enum dropped, replaced
  by two orthogonal flags:
  - `jsonSchema` (dict|null) — JSON mode + schema validation + up-to-3
    self-correction retries.
  - `verbose` (bool) — full diagnostic response shape (text + events +
    sessionId + usage); default lean.
- The two compose: `jsonSchema + verbose=true` returns both `.json`
  (parsed object) and `.events` (adapter event log).
- Response field rename: `.parsed` → `.json`.
- Lean default response drops `sessionId` / `usage`. Send `verbose:true`
  to keep them.
- Migration table:
  - `outputFormat=text` → omit both flags
  - `outputFormat=json` → `jsonSchema={...}`
  - `outputFormat=json-verbose` → `verbose=true`
  - New: `jsonSchema={...} + verbose=true` for json + events
- PiAdapter: no code changes; comment refresh.
- OpenAI-compat surface unchanged.

## v0.5.0 — 2026-05-23

Align with aicodebox v0.4.0 `/run` payload restructure.

- **Breaking (`/run` callers).** Each `outputFormat` now produces one
  well-defined surface:
  - `text` → `{..., text}`
  - `json` → `{..., parsed}` on success; `{..., text, parseError, jsonRetries}` on failure (up-to-3 retries handled by base)
  - `json-verbose` → `{..., events}` (decoded pi NDJSON stream)
- Raw `stdout`/`stderr` opt-in via `includeRaw: true`. Default responses
  omit them; `stderr` still auto-included on non-zero exit.
- `json-verbose × jsonSchema` rejected at the base (mutex).
- PiAdapter:
  - `validate()` delegates `output_format` vocab + `json-verbose × jsonSchema` mutex to the base.
  - `parse_output()` shrunk to text/session_id/usage only. Envelope assembly is gone.
  - New `parse_events()` override: JSON-decodes pi's NDJSON for `json-verbose` mode.
  - `parse_stream_event()` unchanged.
- OpenAI-compat surface unchanged.

## v0.4.0 — 2026-05-23

json-verbose envelope + real OAI streaming.

- `outputFormat=json-verbose` returns a structured envelope in
  `result.parsed`: sessionId, model, stopReason, turns (full
  conversation), usage, text, and cost. Incompatible with `json_schema`
  (422).
- **Real OAI `/v1/chat/completions` SSE streaming.**
  `PiAdapter.parse_stream_event()` decodes pi's `--mode json` events
  into delta / session / usage / stop StreamEvents. Per-token chunks
  reach consumers as pi emits them instead of one buffered chunk.
- Test infrastructure: base image pulled from `psyb0t/aicodebox:latest`
  by default. Sibling-repo build path gone. Knobs: `PIBOX_BASE_IMAGE`,
  `SKIP_BASE_PULL`, `SKIP_BUILD`.
- `AICODEBOX_AVAILABLE_MODELS` now set on every API test container —
  the base removed the adapter-name fallback at `/v1/models`.
- Drop-in upgrade — no breaking API changes for existing callers.

## v0.3.2 — 2026-05-22

`anthropic-baseurl` setup runs every boot.

- **Bug fix.** When `/home/aicode/.aicodebox` is bind-mounted from the
  host, the `init.d` marker survived container rebuilds, so
  `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` changes never propagated to
  pi's `models.json` after the first boot. The setup script now runs
  from `pibox-entrypoint` on every container start.
- No env-var or API changes — pure bug fix, drop-in upgrade.

## v0.3.1 — 2026-05-21

`PIBOX_AVAILABLE_MODELS` required for API mode.

- Tracks aicodebox v0.2.1, which removed the silent `/v1/models`
  fallback. API mode now refuses to boot without a real model list —
  pi has no sensible default because the provider (Z.AI / Anthropic /
  OpenRouter / etc.) determines what's available.
- README quick-start, API mode section, and config table call this out.
  Telegram `/model` picker degrades gracefully on empty list.
- Requires aicodebox v0.2.1 base.

## v0.3.0 — 2026-05-21

Env var rename + standalone MCP mode.

- **Breaking.** Every `PIBOX_*` env var follows
  `<MODE>_MODE` / `<MODE>_MODE_<KNOB>` now, mirroring aicodebox v0.2.0.
- MCP is independent of the foreground mode (API mounts `/mcp`;
  everything else gets a sidecar uvicorn on `PIBOX_MCP_MODE_PORT`).
- Separate bearer per surface — `PIBOX_API_MODE_TOKEN` and
  `PIBOX_MCP_MODE_TOKEN`, no fallback.
- Migration: rename existing `PIBOX_MODE_API`, `PIBOX_TELEGRAM_BOT_TOKEN`,
  `PIBOX_MODE_CRON_FILE`, etc. to the new shape. No backwards-compat shim.
- Requires aicodebox v0.2.0 base.

## v0.2.0 — 2026-05-21

`PIBOX_*` env-var aliases.

- User-facing env vars are now `PIBOX_*`; the entrypoint translates each
  `PIBOX_X` → `AICODEBOX_X` on container start. `AICODEBOX_*` still
  works and wins when both are set — fully backwards compatible.
- README Configuration section documents the full set, including
  `PIBOX_MODE_API_TOKEN` (replaces the previously-misnamed
  `AICODEBOX_AUTH_TOKENS`) and previously-undocumented vars
  `PIBOX_MODE_API_PORT`, `PIBOX_TELEGRAM_OVERRIDES`,
  `PIBOX_AVAILABLE_EFFORTS`, `PIBOX_CRON_HISTORY_DIR`,
  `PIBOX_CONTAINER_NAME`.

## v0.1.4 — 2026-05-21

Document `/files` endpoints + expand file-ops test coverage.

## v0.1.3 — 2026-05-20

Bump pi-coding-agent to 0.75.3; fix repo link.

## v0.1.2 — 2026-05-20

Docs: correct mode combination claims.

## v0.1.1 — 2026-05-20

Fix `uv pip install` on Ubuntu 24.04.

## v0.1.0 — 2026-05-19

Initial release.
