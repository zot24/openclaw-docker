# OpenClaw Docker Image
# Uses pre-built base image for fast builds
# Base image contains: apt packages, pnpm, mcporter, sag, playwright/chromium
#
# To build locally without registry access, first build the base:
#   docker build -f Dockerfile.base -t ghcr.io/zot24/openclaw-base:latest .

ARG BASE_IMAGE=ghcr.io/zot24/openclaw-base:latest

# =============================================================================
# Stage 1: Builder
# Clone and build OpenClaw
# =============================================================================
FROM ${BASE_IMAGE} AS builder

WORKDIR /app

# Clone OpenClaw repository
ARG OPENCLAW_VERSION=main
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git .

# Install dependencies and build
RUN pnpm install --frozen-lockfile || pnpm install
RUN pnpm build && pnpm ui:build

# =============================================================================
# Stage 2: Runtime
# Final image with built application
# =============================================================================
FROM ${BASE_IMAGE} AS runtime

WORKDIR /app

# Copy built application from builder with correct ownership
COPY --from=builder --chown=openclaw:openclaw /app /app

# Create data directories
RUN mkdir -p /home/openclaw/.openclaw /home/openclaw/clawd \
    && chown -R openclaw:openclaw /home/openclaw/.openclaw /home/openclaw/clawd

# Copy entrypoint script
COPY --chown=openclaw:openclaw entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 18789 18790

# Set environment
ENV NODE_ENV=production
ENV HOME=/home/openclaw

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/ || exit 1

# Run as non-root user
# For Umbrel: use "user: 1000:1000" in docker-compose.yml (standard Umbrel pattern)
USER openclaw

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]
