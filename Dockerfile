# Clawdbot Docker Image
# Builds Clawdbot from source for use with Umbrel and other self-hosted platforms

FROM node:22-bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Set working directory
WORKDIR /app

# Clone Clawdbot repository
ARG CLAWDBOT_VERSION=main
RUN git clone --depth 1 --branch ${CLAWDBOT_VERSION} https://github.com/clawdbot/clawdbot.git .

# Install dependencies
RUN pnpm install --frozen-lockfile || pnpm install

# Build the application
RUN pnpm build

# Build the UI assets (Control Panel, WebChat)
RUN pnpm ui:build

# Create data directories
RUN mkdir -p /root/.clawdbot /root/clawd

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
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

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]
