# pibox — pi-coding-agent on the aicodebox base.
#
# Build (base lives in the sibling repo ../docker-aicodebox):
#   docker build -t aicodebox-base:local ../docker-aicodebox/
#   docker build --build-arg BASE_IMAGE=aicodebox-base:local -t pibox:local .
ARG BASE_IMAGE=psyb0t/aicodebox:latest
FROM ${BASE_IMAGE}

# pi-coding-agent — pinned npm install.
ARG PI_VERSION=0.74.0
RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

# pibox python package (the PiAdapter). aicodebox is already in the base image
# so we install with --no-deps to avoid redundant resolution.
COPY pibox /opt/pibox
RUN uv pip install --system --break-system-packages --no-deps /opt/pibox

# Pre-install the mcp-bridge extension's npm deps once at build time.
# The extension is later copied into the workspace on first run via init.d.
RUN cd /opt/pibox/extensions/mcp-bridge && npm install --omit=dev --no-audit --no-fund

# First-run init: drop pibox extensions and templates into the aicode home.
COPY pibox/init.d/ /aicodebox-init.d/
RUN chmod +x /aicodebox-init.d/*.sh

# Adapter selection — the modes resolve this at runtime.
ENV AICODEBOX_ADAPTER=pibox.adapter:PiAdapter \
    AICODEBOX_AGENT_BINARY=pi
