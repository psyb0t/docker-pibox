# pibox — pi-coding-agent on the aicodebox base.
#
# Build (base lives in the sibling repo ../docker-aicodebox):
#   docker build -t aicodebox-base:local ../docker-aicodebox/
#   docker build --build-arg BASE_IMAGE=aicodebox-base:local -t pibox:local .
#
# Base pinned to the aicodebox v0.14.6 multi-architecture manifest.
# v0.14.6 adds independent native event retention through `eventMode`
# while keeping schema validation, usage, session data, and raw output
# as separate response controls.
# v0.13.0 lets `tools` and `response_format` COMPOSE in one request on
# /openai/v1/chat/completions — an agentic tool-calling flow can now end
# in a schema-validated structured JSON reply (v0.12.0 rejected that
# pairing with a 400). They describe different turn types: a tool-call
# turn → tool_calls / finish_reason=tool_calls (NOT schema-checked); the
# final-answer turn (model stops calling tools) → validated against the
# schema with the same up-to-3-retry self-correction (exhausted → 422,
# crash → 500). The tools directive carries the final-answer schema so
# the model is told both exits coherently.
# v0.12.0 adds OpenAI-style client-executed tool calling on
# /openai/v1/chat/completions: a client that sends `tools` gets
# `tool_calls` back (finish_reason=tool_calls), runs the tool in its own
# environment, and sends the result back — stateless, exactly like
# OpenAI. In tool mode the harness's own internal tools default OFF (the
# machine acts as a pure function-calling model); send
# x-aicodebox-no-tools: 0 to re-enable the hybrid. tool_choice
# (auto/none/required/specific) is honored.
# v0.11.0 surfaces upstream provider errors (content-safety rejections,
# rate limits, auth failures) as HTTP 400 on
# /openai/v1/chat/completions instead of a 200 with empty text.
# RunResult gained a `provider_error` field; the OAI route checks it
# ahead of the exit-code / parse-error handling, and the schema-mode
# retry helper stops re-prompting the moment a provider error appears
# (replaying the same prompt into the same filter never helps). This
# adapter populates `provider_error` from pi's stopReason=error +
# errorMessage on the assistant turn.
# v0.10.1 adds a 10-minute safety-net purge that sweeps orphaned
# /tmp/aicodebox/<uuid>/ workspaces (TTL 1h). Covers the SIGKILL /
# container-restart / cleanup-helper-raise cases the v0.10.0 `finally`
# block can't reach.
# v0.10.0 made schema-mode retries CHEAP on
# /openai/v1/chat/completions — when no x-aicodebox-workspace is set,
# the route allocates an ephemeral /tmp/aicodebox/<uuid>/ (mode 0o700)
# and tells run_with_json_retry to session-continue the conversation
# instead of replaying the full original prompt. A 100k-token request
# needing 3 retries used to pay 400k input tokens; now ~100k + ~1.5k
# corrective overhead. Cleaned up in `finally` after every code path
# (200 / 422 / 500). /run callers unchanged.
# v0.9.1 fixed the schema-mode retry helper to include the original
# task in each retry prompt (previously: only the bad output + error
# + schema, leaving the fresh-session retry agent with no idea what
# task it was correcting — fatal for large-enum / domain-identifier
# schemas).
# v0.9.0 added OpenAI-standard response_format body field support on
# /openai/v1/chat/completions — stock OAI SDKs (LangChain, openai-python,
# LlamaIndex) can drive schema validation without our proprietary
# x-aicodebox-json-schema header. v0.8.x changes inherited:
#   - JSON-schema validation on /openai/v1/chat/completions (v0.8.0)
#   - per-attempt usage breakdown + summed billing across retries (v0.8.1)
#   - agent-crash 500 vs schema-exhaustion 422 split (v0.8.1)
#   - smarter JSON extraction (fenced-in-prose, brace-balanced) (v0.8.0)
#   - reconstruction-grade logging on the schema-mode path (v0.8.2)
#   - single-source __version__ via importlib.metadata (v0.8.3)
ARG BASE_IMAGE=psyb0t/aicodebox:v0.14.6@sha256:0895ce88281fd1c307fdbbca5cec86989a252a1ca314713d74eec521c7651853
FROM ${BASE_IMAGE}

# MCP Registry ownership label.
LABEL io.modelcontextprotocol.server.name="io.github.psyb0t/pibox"

# pi-coding-agent — pinned npm install.
ARG PI_VERSION=0.84.0
RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

# pibox python package (the PiAdapter). aicodebox is already in the base image
# so we install with --no-deps to avoid redundant resolution.
COPY pibox /opt/pibox
RUN uv pip install --system --break-system-packages --no-deps /opt/pibox \
    && chmod +x /opt/pibox/scripts/*.sh

# Pre-install the mcp-bridge extension's npm deps once at build time.
# The extension is later copied into the workspace on first run via init.d.
RUN cd /opt/pibox/extensions/mcp-bridge && npm install --omit=dev --no-audit --no-fund

# First-run init: drop pibox extensions and templates into the aicode home.
COPY pibox/init.d/ /aicodebox-init.d/
RUN chmod +x /aicodebox-init.d/*.sh

# Adapter selection — the modes resolve this at runtime.
ENV AICODEBOX_ADAPTER=pibox.adapter:PiAdapter \
    AICODEBOX_AGENT_BINARY=pi

# pibox-branded entrypoint: aliases PIBOX_* → AICODEBOX_*, then exec the base.
COPY pibox-entrypoint.sh /usr/local/bin/pibox-entrypoint
RUN chmod +x /usr/local/bin/pibox-entrypoint
ENTRYPOINT ["/usr/local/bin/pibox-entrypoint"]
