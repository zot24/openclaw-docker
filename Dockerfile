# OpenClaw Docker Image
# Multi-stage build for optimal caching and build times
# Stage 1: Heavy dependencies (cached, rarely changes)
# Stage 2: Build OpenClaw (rebuilds on code changes)
# Stage 3: Runtime (final image with all tools)
#
# Security: Runs as dedicated non-root 'openclaw' user (UID 1000)

# =============================================================================
# Stage 1: Dependencies
# Install all system packages and global tools that rarely change
# =============================================================================
FROM node:22-bookworm-slim AS deps

# Create openclaw user for running the application
# The node:22-bookworm-slim base image has a 'node' user with UID/GID 1000.
# We rename it to 'openclaw' for clarity and create a proper home directory.
RUN usermod -l openclaw -d /home/openclaw -m node \
    && groupmod -n openclaw node \
    && mkdir -p /home/openclaw \
    && chown -R openclaw:openclaw /home/openclaw

# Install system dependencies
# - Build essentials: git, curl, ca-certificates, wget
# - Media processing: ffmpeg, imagemagick
# - Browser automation: chromium and dependencies
# - Python tools: python3, pip
# - Audio: ALSA/PulseAudio for TTS playback
# - Utilities: gh (GitHub CLI), zip, unzip, tar
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    gh \
    ffmpeg \
    imagemagick \
    alsa-utils \
    libasound2-dev \
    pkg-config \
    pulseaudio \
    python3 \
    python3-pip \
    python3-venv \
    zip \
    unzip \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libatspi2.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Install Node.js global tools
RUN npm install -g mcporter

# Install Python tools - uv only (whisper is optional and heavy)
# Users who need STT can install whisper manually
RUN pip3 install --no-cache-dir --break-system-packages uv

# Install sag (ElevenLabs TTS CLI) - download pre-built binary
# https://github.com/steipete/sag
ARG SAG_VERSION=0.3.2
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then SAG_ARCH="x86_64"; else SAG_ARCH="aarch64"; fi && \
    curl -fsSL "https://github.com/steipete/sag/releases/download/v${SAG_VERSION}/sag-v${SAG_VERSION}-${SAG_ARCH}-unknown-linux-gnu.tar.gz" | \
    tar -xzf - -C /usr/local/bin sag && \
    chmod +x /usr/local/bin/sag

# Install Playwright Chromium browser as openclaw user
ENV PLAYWRIGHT_BROWSERS_PATH="/home/openclaw/.cache/ms-playwright"
USER openclaw
RUN npx -y playwright@latest install chromium
USER root

# =============================================================================
# Stage 2: Builder
# Clone and build OpenClaw (rebuilds when OPENCLAW_VERSION changes)
# =============================================================================
FROM deps AS builder

WORKDIR /app

# Clone OpenClaw repository
ARG OPENCLAW_VERSION=main
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git .

# Install dependencies and build in one layer for efficiency
RUN pnpm install --frozen-lockfile || pnpm install
RUN pnpm build && pnpm ui:build

# =============================================================================
# Stage 3: Runtime
# Final image with all tools and built application
# =============================================================================
FROM deps AS runtime

WORKDIR /app

# Copy built application from builder with correct ownership (avoids slow chown)
COPY --from=builder --chown=openclaw:openclaw /app /app

# Create data directories with proper ownership
RUN mkdir -p /home/openclaw/.openclaw /home/openclaw/clawd \
    && chown -R openclaw:openclaw /home/openclaw/.openclaw /home/openclaw/clawd

# Copy entrypoint script
COPY --chown=openclaw:openclaw entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports
# 18789: Gateway (HTTP + WebSocket + WebChat at /chat)
# 18790: Bridge (TCP for mobile nodes)
EXPOSE 18789 18790

# Set environment
ENV NODE_ENV=production

# Health check (gateway serves HTTP on 18789)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/ || exit 1

# Run as non-root user for security
USER openclaw

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]
