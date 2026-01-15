# Clawdbot Docker Image

Docker image for [Clawdbot](https://github.com/clawdbot/clawdbot) - your personal AI assistant.

Built for use with [Umbrel](https://umbrel.com) and other self-hosted platforms.

## Quick Start

```bash
docker run -d \
  -p 18789:18789 \
  -p 18790:18790 \
  -e ANTHROPIC_API_KEY=your-key \
  -e TELEGRAM_BOT_TOKEN=your-bot-token \
  -v clawdbot-data:/root/.clawdbot \
  -v clawdbot-workspace:/root/clawd \
  ghcr.io/zot24/clawdbot-docker:latest
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Your Anthropic API key for Claude |
| `TELEGRAM_BOT_TOKEN` | No | Telegram bot token from @BotFather |
| `OPENAI_API_KEY` | No | OpenAI API key (for embeddings) |
| `CLAWDBOT_GATEWAY_PORT` | No | Gateway port (default: 18789) |
| `CLAWDBOT_WEBCHAT_PORT` | No | WebChat UI port (default: 18790) |

## Ports

- **18789**: Gateway WebSocket API
- **18790**: WebChat UI

## Volumes

- `/root/.clawdbot`: Configuration and credentials
- `/root/clawd`: Workspace, memory, and skills

## Building Locally

```bash
docker build -t clawdbot:local .
```

## License

This Docker image builds [Clawdbot](https://github.com/clawdbot/clawdbot) from source.
See the original repository for licensing information.
