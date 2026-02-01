# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Pre-built base image for faster builds (`Dockerfile.base`)
- Daily security scanning with Trivy
- Auto-rebuild base image on critical CVEs
- Build optimization: amd64 only for main, both platforms for releases

## [2.0.0] - 2026-02-01

### Changed
- **BREAKING:** Renamed from Clawdbot to OpenClaw
  - User/group renamed from `clawdbot` to `openclaw`
  - Config paths changed from `/home/clawdbot` to `/home/openclaw`
  - Config file renamed from `clawdbot.json` to `openclaw.json`
  - Environment variables renamed from `CLAWDBOT_*` to `OPENCLAW_*`
  - Source URL changed to `github.com/openclaw/openclaw`
- Fixed config schema: model now uses object format with `primary` key
- Removed invalid config fields (`timezone`, `tools` from agents.defaults)
- Release watcher now runs daily instead of every 2 days

### Added
- Local test script (`test.sh`) for pre-PR validation

## [1.5.0] - 2026-01-26

### Changed
- Install Go 1.24 from official source (Debian's version too old for sag)

### Security
- Container now runs as dedicated non-root user (`clawdbot`, UID 1000)
- Fixed user creation by renaming existing `node` user

## [1.4.0] - 2026-01-23

### Added
- Text-to-Speech support via [sag](https://github.com/steipete/sag) (ElevenLabs)
- Speech-to-Text support via OpenAI Whisper
- `ELEVENLABS_API_KEY` and `SAG_VOICE_ID` environment variables

### Fixed
- Free disk space before Docker build to fix GitHub runner exhaustion

## [1.3.0] - 2026-01-19

### Added
- Auto-build on upstream clawdbot releases (`watch-releases.yml`)
- Multi-stage Dockerfile for better caching
- Enhanced runtime dependencies

### Changed
- Use GitHub Actions cache for version tracking
- Reduced release check frequency to every 2 days

### Fixed
- Permissions for reusable workflow calls

## [1.2.0] - 2026-01-17

### Added
- Support for user-provided `clawdbot.json` with env var injection
- Full channel support: Telegram, WhatsApp, Discord, Slack, MS Teams, Signal
- Full provider support: Anthropic, OpenAI, OpenRouter, MiniMax, Moonshot, GLM, local models

### Fixed
- Custom provider config now includes required `models` array
- Playwright install command in Dockerfile

## [1.1.0] - 2026-01-16

### Added
- MiniMax provider support (Chinese LLM with Anthropic API compatibility)
- Telegram user allowlist (`TELEGRAM_ALLOWED_USERS`)
- Local development configuration setup (`local/` directory)

### Changed
- Updated local dev docs for Docker workflow

## [1.0.3] - 2026-01-15

### Fixed
- WebChat index.html path
- localStorage key for WebChat token injection

### Security
- Added token validation to prevent injection attacks

## [1.0.2] - 2026-01-15

### Fixed
- WebChat authentication by injecting token into UI

## [1.0.1] - 2026-01-14

### Added
- UI build step in Dockerfile

### Fixed
- Healthcheck port configuration
- Gateway config for Docker deployment
- `gateway.bind` config validation error

## [1.0.0] - 2026-01-14

### Added
- Initial release
- Docker image for Clawdbot AI assistant
- Built for Umbrel and self-hosted platforms
- GitHub Container Registry publishing
- Multi-platform support (amd64, arm64)
- Gateway with WebChat UI
- Environment-based configuration
- Playwright/Chromium for browser automation
- FFmpeg for audio/video processing
- ImageMagick for image manipulation

[Unreleased]: https://github.com/zot24/openclaw-docker/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/zot24/openclaw-docker/compare/v1.5.0...v2.0.0
[1.5.0]: https://github.com/zot24/openclaw-docker/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/zot24/openclaw-docker/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/zot24/openclaw-docker/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/zot24/openclaw-docker/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/zot24/openclaw-docker/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/zot24/openclaw-docker/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/zot24/openclaw-docker/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/zot24/openclaw-docker/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/zot24/openclaw-docker/releases/tag/v1.0.0
