# pibox — pi-coding-agent on the aicodebox base.
#
# Build (base lives in the sibling repo ../docker-aicodebox):
#   docker build -t aicodebox-base:local ../docker-aicodebox/
#   docker build --build-arg BASE_IMAGE=aicodebox-base:local -t pibox:local .
#
# Base pinned to aicodebox v0.8.3 (tag-only — v0.8.3 image not yet on the
# registry at release time; digest pin will be added once it's pushed).
# v0.8.x ships:
#   - JSON-schema validation on /openai/v1/chat/completions (v0.8.0)
#   - per-attempt usage breakdown + summed billing across retries (v0.8.1)
#   - agent-crash 500 vs schema-exhaustion 422 split (v0.8.1)
#   - smarter JSON extraction (fenced-in-prose, brace-balanced) (v0.8.0)
#   - reconstruction-grade logging on the schema-mode path (v0.8.2)
#   - single-source __version__ via importlib.metadata (v0.8.3)
ARG BASE_IMAGE=psyb0t/aicodebox:v0.8.3
FROM ${BASE_IMAGE}

# pi-coding-agent — pinned npm install.
ARG PI_VERSION=0.75.3
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
