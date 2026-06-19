# Changelog

All notable changes per release. Versions follow [semver](https://semver.org)
pre-1.0 conventions: minor bumps may include breaking REST changes (called
out explicitly), patch bumps are docs / build / fixes only.

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
  `~/.claude/rules/06-logging.md` (reconstruction-grade detail):
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
    (previously silent-swallowed — violated `05-error-handling.md`).
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
- **Single-source versioning per `~/.claude/rules/49-versioning.md`.**
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
