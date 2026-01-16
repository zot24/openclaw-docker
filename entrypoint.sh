#!/bin/bash
set -e

CONFIG_DIR="${CLAWDBOT_DATA_DIR:-/root/.clawdbot}"
CONFIG_FILE="${CONFIG_DIR}/clawdbot.json"
WORKSPACE="${CLAWDBOT_WORKSPACE:-/root/clawd}"

# Create directories if they don't exist
mkdir -p "${CONFIG_DIR}" "${WORKSPACE}" "${WORKSPACE}/memory" "${WORKSPACE}/skills"

# Create WhatsApp credentials directory
mkdir -p "${CONFIG_DIR}/credentials/whatsapp/default"

# Generate configuration if it doesn't exist or if Telegram token changed
generate_config() {
    echo "Generating Clawdbot configuration..."

    # Build Telegram configuration
    local TELEGRAM_ENABLED="false"
    local TELEGRAM_TOKEN=""
    local TELEGRAM_DM_POLICY="${CLAWDBOT_DM_POLICY:-pairing}"
    local TELEGRAM_ALLOW_FROM=""
    if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
        TELEGRAM_ENABLED="true"
        TELEGRAM_TOKEN="${TELEGRAM_BOT_TOKEN}"
    fi

    # Build allowFrom line if TELEGRAM_ALLOWED_USERS is set (comma-separated user IDs)
    local TELEGRAM_ALLOW_LINE=""
    if [ -n "${TELEGRAM_ALLOWED_USERS}" ]; then
        # Convert comma-separated IDs to JSON array
        local ALLOW_ARRAY=$(echo "${TELEGRAM_ALLOWED_USERS}" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
        TELEGRAM_ALLOW_LINE=",\"allowFrom\": [${ALLOW_ARRAY}]"
    fi

    # Build WhatsApp configuration
    local WHATSAPP_ENABLED="${WHATSAPP_ENABLED:-false}"
    local WHATSAPP_DM_POLICY="${WHATSAPP_DM_POLICY:-pairing}"
    local WHATSAPP_GROUP_POLICY="${WHATSAPP_GROUP_POLICY:-disabled}"

    # Build allowFrom line if WHATSAPP_ALLOWED_NUMBERS is set (comma-separated phone numbers)
    local WHATSAPP_ALLOW_LINE=""
    if [ -n "${WHATSAPP_ALLOWED_NUMBERS}" ]; then
        local ALLOW_ARRAY=$(echo "${WHATSAPP_ALLOWED_NUMBERS}" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
        WHATSAPP_ALLOW_LINE=",\"allowFrom\": [${ALLOW_ARRAY}]"
    fi

    # Build groups line if WHATSAPP_GROUPS is set (comma-separated group IDs or "*" for all)
    local WHATSAPP_GROUPS_LINE=""
    if [ -n "${WHATSAPP_GROUPS}" ]; then
        if [ "${WHATSAPP_GROUPS}" = "*" ]; then
            WHATSAPP_GROUPS_LINE=",\"groups\": [\"*\"]"
        else
            local GROUPS_ARRAY=$(echo "${WHATSAPP_GROUPS}" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            WHATSAPP_GROUPS_LINE=",\"groups\": [${GROUPS_ARRAY}]"
        fi
    fi

    # Build Discord configuration
    local DISCORD_ENABLED="false"
    local DISCORD_DM_POLICY="${DISCORD_DM_POLICY:-pairing}"
    local DISCORD_TOKEN_LINE=""
    local DISCORD_ALLOW_LINE=""
    if [ -n "${DISCORD_BOT_TOKEN}" ]; then
        DISCORD_ENABLED="true"
        DISCORD_TOKEN_LINE=",\"botToken\": \"${DISCORD_BOT_TOKEN}\""
    fi
    if [ -n "${DISCORD_ALLOWED_USERS}" ]; then
        local ALLOW_ARRAY=$(echo "${DISCORD_ALLOWED_USERS}" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
        DISCORD_ALLOW_LINE=",\"allowFrom\": [${ALLOW_ARRAY}]"
    fi

    # Build Slack configuration
    local SLACK_ENABLED="false"
    local SLACK_TOKEN_LINES=""
    local SLACK_ALLOW_LINE=""
    if [ -n "${SLACK_APP_TOKEN}" ] && [ -n "${SLACK_BOT_TOKEN}" ]; then
        SLACK_ENABLED="true"
        SLACK_TOKEN_LINES=",\"appToken\": \"${SLACK_APP_TOKEN}\",\"botToken\": \"${SLACK_BOT_TOKEN}\""
    fi
    if [ -n "${SLACK_ALLOWED_USERS}" ]; then
        local ALLOW_ARRAY=$(echo "${SLACK_ALLOWED_USERS}" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
        SLACK_ALLOW_LINE=",\"allowFrom\": [${ALLOW_ARRAY}]"
    fi

    # Build MS Teams configuration
    local MSTEAMS_ENABLED="false"
    local MSTEAMS_CONFIG_LINES=""
    if [ -n "${MSTEAMS_APP_ID}" ] && [ -n "${MSTEAMS_APP_PASSWORD}" ]; then
        MSTEAMS_ENABLED="true"
        MSTEAMS_CONFIG_LINES=",\"appId\": \"${MSTEAMS_APP_ID}\",\"appPassword\": \"${MSTEAMS_APP_PASSWORD}\""
    fi

    # Build Signal configuration (requires signal-cli to be installed)
    local SIGNAL_ENABLED="false"
    local SIGNAL_NUMBER_LINE=""
    if [ -n "${SIGNAL_NUMBER}" ]; then
        # Check if signal-cli is available
        if command -v signal-cli &> /dev/null; then
            SIGNAL_ENABLED="true"
            SIGNAL_NUMBER_LINE=",\"number\": \"${SIGNAL_NUMBER}\""
        else
            echo "WARNING: SIGNAL_NUMBER set but signal-cli not installed. Signal disabled."
        fi
    fi

    # Generate auth token if not provided (exported for use in WebChat injection)
    AUTH_TOKEN="${CLAWDBOT_GATEWAY_TOKEN:-$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}"

    # Validate token is alphanumeric only (security: prevents injection in HTML/JS)
    if [[ ! "${AUTH_TOKEN}" =~ ^[a-zA-Z0-9]+$ ]]; then
        echo "ERROR: Auth token must be alphanumeric only. Invalid characters found."
        exit 1
    fi

    # Determine model configuration based on available API keys
    # Priority: CLAWDBOT_MODEL (explicit) > MiniMax > Anthropic > OpenAI > OpenRouter > Moonshot > GLM > OpenCode
    local MODEL_CONFIG=""
    local MODELS_SECTION=""
    local PROVIDERS_JSON=""

    # Build providers configuration for each available API key
    local HAS_PROVIDERS="false"

    # MiniMax provider
    if [ -n "${MINIMAX_API_KEY}" ]; then
        HAS_PROVIDERS="true"
        PROVIDERS_JSON="${PROVIDERS_JSON}${PROVIDERS_JSON:+,}
      \"minimax\": {
        \"baseUrl\": \"https://api.minimax.io/anthropic\",
        \"apiKey\": \"${MINIMAX_API_KEY}\",
        \"api\": \"anthropic-messages\",
        \"models\": [
          {
            \"id\": \"MiniMax-M2.1\",
            \"name\": \"MiniMax M2.1\",
            \"reasoning\": false,
            \"input\": [\"text\"],
            \"cost\": { \"input\": 15, \"output\": 60, \"cacheRead\": 2, \"cacheWrite\": 10 },
            \"contextWindow\": 200000,
            \"maxTokens\": 8192
          }
        ]
      }"
    fi

    # Note: Built-in providers (Anthropic, OpenAI, OpenRouter) use API keys from environment
    # variables automatically. We only need to add custom providers to the models section.
    # Custom providers need explicit configuration with baseUrl, api type, and models array.

    # Moonshot provider (Chinese LLM) - custom provider
    if [ -n "${MOONSHOT_API_KEY}" ]; then
        HAS_PROVIDERS="true"
        PROVIDERS_JSON="${PROVIDERS_JSON}${PROVIDERS_JSON:+,}
      \"moonshot\": {
        \"baseUrl\": \"https://api.moonshot.cn/v1\",
        \"apiKey\": \"${MOONSHOT_API_KEY}\",
        \"api\": \"openai-chat\",
        \"models\": [
          { \"id\": \"moonshot-v1-8k\", \"name\": \"Moonshot v1 8K\", \"contextWindow\": 8000 },
          { \"id\": \"moonshot-v1-32k\", \"name\": \"Moonshot v1 32K\", \"contextWindow\": 32000 },
          { \"id\": \"moonshot-v1-128k\", \"name\": \"Moonshot v1 128K\", \"contextWindow\": 128000 }
        ]
      }"
    fi

    # GLM provider (ChatGLM) - custom provider
    if [ -n "${GLM_API_KEY}" ]; then
        HAS_PROVIDERS="true"
        PROVIDERS_JSON="${PROVIDERS_JSON}${PROVIDERS_JSON:+,}
      \"glm\": {
        \"baseUrl\": \"https://open.bigmodel.cn/api/paas/v4\",
        \"apiKey\": \"${GLM_API_KEY}\",
        \"api\": \"openai-chat\",
        \"models\": [
          { \"id\": \"glm-4-plus\", \"name\": \"GLM-4 Plus\", \"contextWindow\": 128000 },
          { \"id\": \"glm-4\", \"name\": \"GLM-4\", \"contextWindow\": 128000 },
          { \"id\": \"glm-4-flash\", \"name\": \"GLM-4 Flash\", \"contextWindow\": 128000 }
        ]
      }"
    fi

    # OpenCode provider (local models: Ollama, vLLM, LM Studio, etc.) - custom provider
    if [ -n "${OPENCODE_BASE_URL}" ]; then
        HAS_PROVIDERS="true"
        local OPENCODE_KEY_LINE=""
        [ -n "${OPENCODE_API_KEY}" ] && OPENCODE_KEY_LINE=",\"apiKey\": \"${OPENCODE_API_KEY}\""
        local OPENCODE_MODEL_ID="${OPENCODE_MODEL:-llama3.1}"
        PROVIDERS_JSON="${PROVIDERS_JSON}${PROVIDERS_JSON:+,}
      \"opencode\": {
        \"baseUrl\": \"${OPENCODE_BASE_URL}\"${OPENCODE_KEY_LINE},
        \"api\": \"openai-chat\",
        \"models\": [
          { \"id\": \"${OPENCODE_MODEL_ID}\", \"name\": \"${OPENCODE_MODEL_ID}\", \"contextWindow\": 128000 }
        ]
      }"
    fi

    # Build models section if any providers configured
    if [ "${HAS_PROVIDERS}" = "true" ]; then
        MODELS_SECTION=",
  \"models\": {
    \"mode\": \"merge\",
    \"providers\": {${PROVIDERS_JSON}
    }
  }"
    fi

    # Determine primary model (explicit override or auto-select)
    if [ -n "${CLAWDBOT_MODEL}" ]; then
        # Explicit model override
        MODEL_CONFIG="\"model\": \"${CLAWDBOT_MODEL}\""
    elif [ -n "${MINIMAX_API_KEY}" ]; then
        MODEL_CONFIG="\"model\": { \"primary\": \"minimax/MiniMax-M2.1\" }"
    elif [ -n "${ANTHROPIC_API_KEY}" ]; then
        MODEL_CONFIG="\"model\": \"anthropic/claude-sonnet-4\""
    elif [ -n "${OPENAI_API_KEY}" ]; then
        MODEL_CONFIG="\"model\": \"openai/gpt-4o\""
    elif [ -n "${OPENROUTER_API_KEY}" ]; then
        MODEL_CONFIG="\"model\": \"openrouter/anthropic/claude-sonnet-4\""
    elif [ -n "${MOONSHOT_API_KEY}" ]; then
        MODEL_CONFIG="\"model\": \"moonshot/moonshot-v1-128k\""
    elif [ -n "${GLM_API_KEY}" ]; then
        MODEL_CONFIG="\"model\": \"glm/glm-4-plus\""
    elif [ -n "${OPENCODE_BASE_URL}" ]; then
        MODEL_CONFIG="\"model\": \"opencode/${OPENCODE_MODEL:-llama3.1}\""
    else
        # No provider configured, default to Anthropic (will fail without key)
        MODEL_CONFIG="\"model\": \"anthropic/claude-sonnet-4\""
    fi

    # Runtime configuration
    local AGENT_TIMEOUT="${AGENT_TIMEOUT:-600}"
    local AGENT_TIMEZONE="${AGENT_TIMEZONE:-UTC}"
    local ENABLE_MEMORY="${ENABLE_MEMORY_SEARCH:-false}"
    local ENABLE_BROWSER="${ENABLE_BROWSER:-true}"
    local ENABLE_EXEC="${ENABLE_EXEC:-true}"
    local EXEC_TIMEOUT="${EXEC_TIMEOUT:-30000}"

    # Build tools configuration
    local TOOLS_CONFIG=""
    if [ "${ENABLE_BROWSER}" = "true" ] || [ "${ENABLE_EXEC}" = "true" ]; then
        local TOOL_ENTRIES=""
        if [ "${ENABLE_BROWSER}" = "true" ]; then
            TOOL_ENTRIES="\"browser\": { \"enabled\": true }"
        fi
        if [ "${ENABLE_EXEC}" = "true" ]; then
            [ -n "${TOOL_ENTRIES}" ] && TOOL_ENTRIES="${TOOL_ENTRIES},"
            TOOL_ENTRIES="${TOOL_ENTRIES}\"exec\": { \"enabled\": true, \"timeout\": ${EXEC_TIMEOUT} }"
        fi
        TOOLS_CONFIG=",
      \"tools\": { ${TOOL_ENTRIES} }"
    fi

    # Gateway configuration
    local GATEWAY_MODE="${GATEWAY_MODE:-local}"
    local GATEWAY_BIND="${GATEWAY_BIND:-lan}"

    # Write configuration file
    # Note: WebChat UI is served by Gateway on port 18789 at /chat
    # bind: "lan" required to expose outside container (default is loopback)
    cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "${GATEWAY_MODE}",
    "port": ${CLAWDBOT_GATEWAY_PORT:-18789},
    "bind": "${GATEWAY_BIND}",
    "auth": {
      "mode": "token",
      "token": "${AUTH_TOKEN}"
    }
  },
  "channels": {
    "telegram": {
      "enabled": ${TELEGRAM_ENABLED},
      "botToken": "${TELEGRAM_TOKEN}",
      "dmPolicy": "${TELEGRAM_DM_POLICY}",
      "streamMode": "partial"${TELEGRAM_ALLOW_LINE}
    },
    "whatsapp": {
      "enabled": ${WHATSAPP_ENABLED},
      "dmPolicy": "${WHATSAPP_DM_POLICY}",
      "groupPolicy": "${WHATSAPP_GROUP_POLICY}"${WHATSAPP_ALLOW_LINE}${WHATSAPP_GROUPS_LINE}
    },
    "discord": {
      "enabled": ${DISCORD_ENABLED},
      "dmPolicy": "${DISCORD_DM_POLICY}"${DISCORD_TOKEN_LINE}${DISCORD_ALLOW_LINE}
    },
    "slack": {
      "enabled": ${SLACK_ENABLED}${SLACK_TOKEN_LINES}${SLACK_ALLOW_LINE}
    },
    "msteams": {
      "enabled": ${MSTEAMS_ENABLED}${MSTEAMS_CONFIG_LINES}
    },
    "signal": {
      "enabled": ${SIGNAL_ENABLED}${SIGNAL_NUMBER_LINE}
    }
  },
  "agents": {
    "defaults": {
      ${MODEL_CONFIG},
      "workspace": "${WORKSPACE}",
      "timeoutSeconds": ${AGENT_TIMEOUT},
      "timezone": "${AGENT_TIMEZONE}",
      "memorySearch": {
        "enabled": ${ENABLE_MEMORY}
      }${TOOLS_CONFIG}
    }
  },
  "skills": {
    "entries": {}
  }${MODELS_SECTION}
}
EOF
    echo "Configuration generated at ${CONFIG_FILE}"
}

# Always regenerate config to pick up env var changes
generate_config

# Report enabled channels
echo ""
echo "=== Channels ==="
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
    echo "✓ Telegram: enabled"
else
    echo "○ Telegram: disabled (set TELEGRAM_BOT_TOKEN)"
fi

if [ "${WHATSAPP_ENABLED}" = "true" ]; then
    if [ ! -f "${CONFIG_DIR}/credentials/whatsapp/default/creds.json" ]; then
        echo "✓ WhatsApp: enabled (needs linking - run: docker exec -it <container> node dist/index.js channels login)"
    else
        echo "✓ WhatsApp: enabled (linked)"
    fi
else
    echo "○ WhatsApp: disabled (set WHATSAPP_ENABLED=true)"
fi

if [ -n "${DISCORD_BOT_TOKEN}" ]; then
    echo "✓ Discord: enabled"
else
    echo "○ Discord: disabled (set DISCORD_BOT_TOKEN)"
fi

if [ -n "${SLACK_APP_TOKEN}" ] && [ -n "${SLACK_BOT_TOKEN}" ]; then
    echo "✓ Slack: enabled"
else
    echo "○ Slack: disabled (set SLACK_APP_TOKEN and SLACK_BOT_TOKEN)"
fi

if [ -n "${MSTEAMS_APP_ID}" ] && [ -n "${MSTEAMS_APP_PASSWORD}" ]; then
    echo "✓ MS Teams: enabled"
else
    echo "○ MS Teams: disabled (set MSTEAMS_APP_ID and MSTEAMS_APP_PASSWORD)"
fi

if [ -n "${SIGNAL_NUMBER}" ]; then
    if command -v signal-cli &> /dev/null; then
        echo "✓ Signal: enabled"
    else
        echo "○ Signal: disabled (signal-cli not installed)"
    fi
else
    echo "○ Signal: disabled (set SIGNAL_NUMBER)"
fi

# Report configured providers
echo ""
echo "=== LLM Providers ==="
PROVIDER_COUNT=0

if [ -n "${ANTHROPIC_API_KEY}" ]; then
    echo "✓ Anthropic: configured"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ -n "${MINIMAX_API_KEY}" ]; then
    echo "✓ MiniMax: configured"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ -n "${OPENAI_API_KEY}" ]; then
    echo "✓ OpenAI: configured"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ -n "${OPENROUTER_API_KEY}" ]; then
    echo "✓ OpenRouter: configured"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ -n "${MOONSHOT_API_KEY}" ]; then
    echo "✓ Moonshot: configured"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ -n "${GLM_API_KEY}" ]; then
    echo "✓ GLM: configured"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ -n "${OPENCODE_BASE_URL}" ]; then
    echo "✓ OpenCode (local): ${OPENCODE_BASE_URL}"
    PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
fi

if [ ${PROVIDER_COUNT} -eq 0 ]; then
    echo "WARNING: No LLM provider configured!"
    echo "Set at least one of: ANTHROPIC_API_KEY, OPENAI_API_KEY, MINIMAX_API_KEY, OPENROUTER_API_KEY"
fi

# Report selected model
echo ""
echo "=== Model ==="
if [ -n "${CLAWDBOT_MODEL}" ]; then
    echo "Model: ${CLAWDBOT_MODEL} (explicit)"
elif [ -n "${MINIMAX_API_KEY}" ]; then
    echo "Model: minimax/MiniMax-M2.1 (auto-selected)"
elif [ -n "${ANTHROPIC_API_KEY}" ]; then
    echo "Model: anthropic/claude-sonnet-4 (auto-selected)"
elif [ -n "${OPENAI_API_KEY}" ]; then
    echo "Model: openai/gpt-4o (auto-selected)"
elif [ -n "${OPENROUTER_API_KEY}" ]; then
    echo "Model: openrouter/anthropic/claude-sonnet-4 (auto-selected)"
elif [ -n "${MOONSHOT_API_KEY}" ]; then
    echo "Model: moonshot/moonshot-v1-128k (auto-selected)"
elif [ -n "${GLM_API_KEY}" ]; then
    echo "Model: glm/glm-4-plus (auto-selected)"
elif [ -n "${OPENCODE_BASE_URL}" ]; then
    echo "Model: opencode/${OPENCODE_MODEL:-llama3.1} (auto-selected)"
else
    echo "Model: anthropic/claude-sonnet-4 (default - needs API key)"
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
WEBCHAT_INDEX="/app/dist/control-ui/index.html"
if [ -f "${WEBCHAT_INDEX}" ]; then
    # Inject script that sets the token in localStorage before the app initializes
    # The app reads settings from localStorage and uses the token for WebSocket auth
    INJECT_SCRIPT="<script>(function(){try{var k='clawdbot.control.settings.v1',s=localStorage.getItem(k),o=s?JSON.parse(s):{};if(!o.token){o.token='${AUTH_TOKEN}';localStorage.setItem(k,JSON.stringify(o));}}catch(e){}})();</script>"
    sed -i "s|</head>|${INJECT_SCRIPT}</head>|" "${WEBCHAT_INDEX}"
    echo "  Auth token injected into WebChat UI"
fi

# Start the gateway
cd /app
exec node dist/index.js gateway
