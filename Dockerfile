# Stage 1: Build dependencies
FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source

# Stage 2: Build stage - compile native extensions and install Playwright
FROM debian:13.4 AS builder

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Install build dependencies (will be discarded after this stage)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential nodejs npm python3 python3-dev python3-pip libffi-dev git && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# Copy only necessary files for build
COPY pyproject.toml ./
COPY hermes_cli/ ./hermes_cli/
COPY agent/ ./agent/
COPY tools/ ./tools/
COPY gateway/ ./gateway/
COPY cron/ ./cron/
COPY acp_adapter/ ./acp_adapter/
COPY scripts/ ./scripts/
COPY docker/ ./docker/
COPY run_agent.py ./
COPY model_tools.py ./
COPY toolsets.py ./
COPY hermes_state.py ./
COPY batch_runner.py ./
COPY hermes_constants.py ./

# Install Python dependencies (build wheels for native extensions)
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

# Install Node dependencies and Playwright
COPY package*.json ./
RUN npm install --prefer-offline --no-audit 2>/dev/null || true && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force && \
    rm -rf /root/.npm /root/.cache

# Stage 3: Runtime stage - minimal image
FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV HERMES_HOME=/opt/data

# Install only runtime dependencies (no build tools)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    nodejs npm python3 libffi8 procps && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Non-root user
RUN useradd -u 10000 -m -d /opt/data hermes

# Copy gosu for privilege management
COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/

# Copy Python virtual environment from builder
COPY --from=builder --chown=hermes:hermes /opt/hermes/.venv /opt/hermes/.venv

# Copy application code (only necessary runtime files)
COPY --chown=hermes:hermes hermes_cli/ /opt/hermes/hermes_cli/
COPY --chown=hermes:hermes agent/ /opt/hermes/agent/
COPY --chown=hermes:hermes tools/ /opt/hermes/tools/
COPY --chown=hermes:hermes gateway/ /opt/hermes/gateway/
COPY --chown=hermes:hermes cron/ /opt/hermes/cron/
COPY --chown=hermes:hermes acp_adapter/ /opt/hermes/acp_adapter/
COPY --chown=hermes:hermes scripts/ /opt/hermes/scripts/
COPY --chown=hermes:hermes utils.py /opt/hermes/
COPY --chown=hermes:hermes docker/ /opt/hermes/docker/
COPY --chown=hermes:hermes run_agent.py /opt/hermes/
COPY --chown=hermes:hermes model_tools.py /opt/hermes/
COPY --chown=hermes:hermes toolsets.py /opt/hermes/
COPY --chown=hermes:hermes hermes_state.py /opt/hermes/
COPY --chown=hermes:hermes batch_runner.py /opt/hermes/
COPY --chown=hermes:hermes hermes_constants.py /opt/hermes/

# Copy Playwright browsers from builder
COPY --from=builder --chown=hermes:hermes /opt/hermes/.playwright /opt/hermes/.playwright

WORKDIR /opt/hermes

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    nodejs npm git && \
    rm -rf /var/lib/apt/lists/*

# Install Node dependencies for whatsapp-bridge (scripts already copied above)
RUN cd scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force && \
    apt-get purge -y --auto-remove git && \
    rm -rf /var/lib/apt/lists/*

RUN chmod +x /opt/hermes/docker/entrypoint.sh

# Ensure hermes owns the app directory
RUN chown -R hermes:hermes /opt/hermes

VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
