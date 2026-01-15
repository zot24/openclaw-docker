#!/bin/bash
set -e

CONFIG_DIR="${CLAWDBOT_DATA_DIR:-/root/.clawdbot}"
CONFIG_FILE="${CONFIG_DIR}/clawdbot.json"
WORKSPACE="${CLAWDBOT_WORKSPACE:-/root/clawd}"

# Create directories if they don't exist
mkdir -p "${CONFIG_DIR}" "${WORKSPACE}" "${WORKSPACE}/memory" "${WORKSPACE}/skills"

# Generate configuration if it doesn't exist or if Telegram token changed
generate_config() {
    echo "Generating Clawdbot configuration..."

    # Build Telegram configuration
    local TELEGRAM_ENABLED="false"
    local TELEGRAM_TOKEN=""
    if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
        TELEGRAM_ENABLED="true"
        TELEGRAM_TOKEN="${TELEGRAM_BOT_TOKEN}"
    fi

    # Generate auth token if not provided (exported for use in WebChat injection)
    AUTH_TOKEN="${CLAWDBOT_GATEWAY_TOKEN:-$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}"

    # Validate token is alphanumeric only (security: prevents injection in HTML/JS)
    if [[ ! "${AUTH_TOKEN}" =~ ^[a-zA-Z0-9]+$ ]]; then
        echo "ERROR: Auth token must be alphanumeric only. Invalid characters found."
        exit 1
    fi

    # Write configuration file
    # Note: WebChat UI is served by Gateway on port 18789 at /chat
    # bind: "lan" required to expose outside container (default is loopback)
    cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "port": ${CLAWDBOT_GATEWAY_PORT:-18789},
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "${AUTH_TOKEN}"
    }
  },
  "channels": {
    "telegram": {
      "enabled": ${TELEGRAM_ENABLED},
      "botToken": "${TELEGRAM_TOKEN}",
      "dmPolicy": "pairing",
      "streamMode": "partial"
    },
    "whatsapp": {
      "enabled": false
    },
    "discord": {
      "enabled": false
    },
    "slack": {
      "enabled": false
    },
    "signal": {
      "enabled": false
    }
  },
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE}",
      "timeoutSeconds": 600,
      "memorySearch": {
        "enabled": false
      }
    }
  },
  "skills": {
    "entries": {}
  }
}
EOF
    echo "Configuration generated at ${CONFIG_FILE}"
}

# Always regenerate config to pick up env var changes
generate_config

# Check if Telegram is configured
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
    echo "Telegram bot token configured - Telegram channel enabled"
else
    echo "NOTE: No TELEGRAM_BOT_TOKEN set. Telegram channel disabled."
    echo "To enable Telegram:"
    echo "  1. Create a bot via @BotFather on Telegram"
    echo "  2. Copy the bot token"
    echo "  3. Set TELEGRAM_BOT_TOKEN environment variable"
fi

# Check for Anthropic API key
if [ -z "${ANTHROPIC_API_KEY}" ]; then
    echo "WARNING: No ANTHROPIC_API_KEY set. Claude models will not work."
    echo "Set ANTHROPIC_API_KEY environment variable to use Claude."
fi

# Create default workspace files if they don't exist
if [ ! -f "${WORKSPACE}/SOUL.md" ]; then
    cat > "${WORKSPACE}/SOUL.md" <<EOF
# Soul

You are a helpful AI assistant running on Umbrel.
You are friendly, concise, and helpful.
EOF
fi

if [ ! -f "${WORKSPACE}/MEMORY.md" ]; then
    cat > "${WORKSPACE}/MEMORY.md" <<EOF
# Long-term Memory

This file stores durable facts and preferences.
EOF
fi

echo "Starting Clawdbot..."
echo "  Gateway port: ${CLAWDBOT_GATEWAY_PORT:-18789}"
echo "  WebChat UI: http://localhost:${CLAWDBOT_GATEWAY_PORT:-18789}/chat"

# Inject auth token into WebChat UI so it can connect to the gateway
# The WebChat stores settings (including token) in localStorage under a specific key
# We inject a script that pre-populates the token before the app loads
WEBCHAT_INDEX="/app/dist/ui/chat/index.html"
if [ -f "${WEBCHAT_INDEX}" ]; then
    # Inject script that sets the token in localStorage before the app initializes
    # The app reads settings from localStorage and uses the token for WebSocket auth
    INJECT_SCRIPT="<script>(function(){try{var k='clawdbot-control-settings',s=localStorage.getItem(k),o=s?JSON.parse(s):{};if(!o.token){o.token='${AUTH_TOKEN}';localStorage.setItem(k,JSON.stringify(o));}}catch(e){}})();</script>"
    sed -i "s|</head>|${INJECT_SCRIPT}</head>|" "${WEBCHAT_INDEX}"
    echo "  Auth token injected into WebChat UI"
fi

# Start the gateway
cd /app
exec node dist/index.js gateway
