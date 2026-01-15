---
name: Webhooks
description: Send HTTP requests to configured URLs when events trigger for integration with Slack, IFTTT, Zapier
category: notification
---

# Feature: Webhooks

Send HTTP requests to configured URLs when events trigger. Enable integrations with Slack, IFTTT, Zapier, custom webhooks.

## Table of Contents

1. [Summary](#summary)
2. [Benefit](#benefit)
3. [Priority & Complexity](#priority--complexity)
4. [Feasibility](#feasibility)
   - [Claude Code](#claude-code)
   - [Audio Player](#audio-player)
   - [External Dependencies](#external-dependencies)
5. [Usage in ccbell Plugin](#usage-in-ccbell-plugin)
6. [Repository Impact](#repository-impact)
   - [cc-plugins](#cc-plugins)
   - [ccbell](#ccbell)
7. [Implementation Plan](#implementation-plan)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
8. [External Dependencies](#external-dependencies-1)
9. [Research Details](#research-details)
10. [Research Sources](#research-sources)

## Summary

Send HTTP requests to configured URLs when events trigger. Enable integrations with Slack, IFTTT, Zapier, custom webhooks for team awareness and automation.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Notify entire channels when Claude completes tasks |
| :memo: Use Cases | Automation triggers, multi-device notifications |
| :dart: Value Proposition | CI/CD integration, existing pipeline connections |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🔴 High | |
| :construction: Complexity | 🟡 Medium | |
| :warning: Risk Level | 🟡 Medium | |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `webhooks` command with list/add/test/remove options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash, WebFetch tools for HTTP requests |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay (macOS) | macOS native audio player | |
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

Uses Go's `net/http` package for HTTP requests.

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:webhooks add "Slack" <url>`, `/ccbell:webhooks test stop` |
| :wrench: Configuration | Adds `webhooks` array with name, url, events, method, headers |
| :gear: Default Behavior | Sends webhook after/before playing sound |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `webhooks.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `webhooks` array |
| `audio/player.go` | :speaker: Audio playback logic (no change) |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add/update command documentation
4. Add/update hooks configuration
5. Add new sound files if applicable

### ccbell

Steps required in ccbell repository:

1. Add webhooks array to config structure
2. Create internal/webhook/webhook.go
3. Implement WebhookManager with Send() and Test() methods
4. Add retry logic (3 attempts with backoff)
5. Add webhooks command with list/add/test/remove options
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | net/http | HTTP client | ❌ |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New webhooks command can be added.

### Claude Code Hooks

No new hooks needed - webhooks integrated into main flow.

### Audio Playback

Webhooks sent independently of audio playback.

### Webhook Platform Options Research

#### 1. Telegram Bot API (Recommended - Free, Feature-Rich)

- **URL**: https://core.telegram.org/bots/api
- **Cost**: Completely free
- **Features**:
  - Send messages, photos, videos, documents, polls
  - Inline keyboards and callback buttons
  - Message formatting (Markdown, HTML)
  - Group and channel support
  - No message rate limits for bots
- **Webhook Setup**:
  - Create bot via @BotFather
  - Set webhook: `https://api.telegram.org/bot<TOKEN>/setWebhook?url=<YOUR_URL>`
  - Receive updates as JSON POST requests
- **Best For**: Personal notifications, group alerts, rich media notifications

#### 2. Slack Incoming Webhooks (Recommended - Team Integration)

- **URL**: https://api.slack.com/messaging/webhooks
- **Cost**: Free for standard usage
- **Features**:
  - Rich message formatting with Block Kit
  - Attachments with colors and fields
  - Message buttons and interactive components
  - Thread replies and file uploads
  - Enterprise grid support
- **Webhook Setup**:
  - Create Slack App in api.slack.com
  - Enable Incoming Webhooks
  - Select channel and copy webhook URL
- **Example Payload**:
```json
{
  "text": "Claude finished task",
  "blocks": [
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*Claude finished*\\nTask completed successfully"}
    }
  ]
}
```
- **Best For**: Team notifications, workflow integrations, CI/CD alerts

#### 3. WhatsApp Business API (Meta)

- **URL**: https://developers.facebook.com/docs/whatsapp/cloud-api
- **Cost**: Tiered pricing (free tier available)
- **Features**:
  - Text messages with formatting
  - Media attachments (images, documents, video)
  - Interactive buttons and lists
  - Template messages for notifications
  - Two-way conversations
- **Setup Requirements**:
  - Meta Business account
  - WhatsApp Business API access
  - Phone number verification
- **Best For**: Personal notifications, high-priority alerts

#### 4. n8n Webhooks (Self-Hosted Automation)

- **URL**: https://n8n.io/
- **Cost**: Free self-hosted, cloud tiers available
- **Features**:
  - Visual workflow builder
  - 400+ integrations
  - Conditional logic and error handling
  - Data transformation
  - Self-hosted for full control
- **Webhook Handling**:
  - Receive webhooks from ccbell
  - Transform and route to any service
  - Chain multiple actions
- **Example Workflows**:
  - ccbell webhook → n8n → Slack + Email + SMS
  - ccbell webhook → n8n → Database logging
  - ccbell webhook → n8n → Custom API calls
- **Best For**: Complex automation, multi-channel routing, data enrichment

#### 5. IFTTT Maker Webhooks (Simple Automation)

- **URL**: https://ifttt.com/maker_webhooks
- **Cost**: Free (limited), Pro tiers available
- **Features**:
  - Simple trigger → action model
  - 700+ service integrations
  - Email, SMS, notifications via IFTTT app
  - Applet creation without coding
- **Webhook Format**:
  - Event URL: `https://maker.ifttt.com/trigger/{event}/with/key/{key}`
  - GET or POST requests supported
  - Values passed as JSON
- **Example**:
```
POST https://maker.ifttt.com/trigger/ccbell_complete/with/key/xxx
Content-Type: application/json
{"value1": "Claude finished", "value2": "Task details"}
```
- **Best For**: Simple notifications, IFTTT ecosystem integration, mobile alerts

#### 6. Zapier Webhooks (Commercial Automation)

- **URL**: https://zapier.com/apps/webhook/integrations
- **Cost**: Free tier (limited), paid plans from $69/mo
- **Features**:
  - 5,000+ app integrations
  - Multi-step Zaps
  - Filters and conditional logic
  - Built-in data formatting
  - Scheduled triggers
- **Webhook Handling**:
  - Catch hook trigger in Zapier
  - Connect to 5,000+ apps
  - Auto-forward to email, SMS, Slack, etc.
- **Best For**: Enterprise integrations, complex multi-step workflows

#### 7. Discord Webhooks (Recommended - Developer Friendly)

- **URL**: https://discord.com/developers/docs/resources/webhook
- **Cost**: Completely free
- **Features**:
  - Rich embeds with colors, images, fields
  - Username and avatar customization
  - Thread support
  - Message editing and deletion
  - File attachments
- **Webhook Setup**:
  - Server Settings → Integrations → Webhooks
  - Copy webhook URL
- **Example Embed**:
```json
{
  "content": null,
  "embeds": [{
    "title": "Claude Finished",
    "description": "Task completed successfully",
    "color": 5763714,
    "fields": [
      {"name": "Duration", "value": "2m 34s"},
      {"name": "Files", "value": "5 modified"}
    ]
  }]
}
```
- **Best For**: Developer notifications, gaming communities, indie teams

#### 8. Microsoft Teams Webhooks (Deprecated)

- **Status**: Incoming Webhooks deprecated December 2025
- **Migration**: Use Microsoft Power Automate or Graph API
- **Alternatives**:
  - Microsoft Power Automate (cloud flows)
  - Teams Graph API webhooks
  - Azure Logic Apps
- **Graph API Setup**:
  - Register Azure AD application
  - Subscribe to team/channel resources
  - Use Delta subscriptions for changes
- **Best For**: Legacy enterprise systems (migration needed)

#### 9. Make.com (formerly Integromat)

- **URL**: https://www.make.com/
- **Cost**: Free tier (1,000 ops/month), paid from $9/mo
- **Features**:
  - Visual scenario builder
  - 1,500+ app integrations
  - Advanced data operations
  - Error handling and debugging
  - Real-time execution
- **Webhook Handling**:
  - HTTP Request module to receive webhooks
  - Connect to any service
  - Complex routing and transformations
- **Best For**: Visual workflow design, enterprise integrations

#### 10. Custom HTTP Endpoints

- **Go net/http**: Native support
- **Use Cases**:
  - Internal dashboards
  - Custom notification systems
  - Logging platforms
  - Home automation (Home Assistant, Node-RED)

#### 11. Activepieces (Open-Source AI Automation)
- **URL**: https://www.activepieces.com/
- **Cost**: Free self-hosted, cloud tiers available
- **Features**:
  - Open-source workflow automation
  - AI-powered automation capabilities
  - Visual flow builder
  - 100+ integrations
  - TypeScript/Python code snippets
- **Webhook Handling**:
  - HTTP trigger support
  - Conditional logic
  - Data transformation
- **Best For**: AI-focused automation, modern deployments

#### 12. Windmill (Open-Source Alternative)
- **URL**: https://www.windmill.dev/
- **Cost**: Free self-hosted, cloud tiers available
- **Features**:
  - Open-source workflow automation
  - Python/TypeScript/Go/Bash scripts
  - Self-hosted with full control
  - Scheduling and webhooks
  - UI for script management
- **Webhook Handling**:
  - Receive webhooks as triggers
  - Run custom scripts on webhook
  - Multi-step workflows
- **Best For**: Developer-focused automation, script-heavy workflows

#### 13. Node-RED (Low-Code Flow-Based)
- **URL**: https://nodered.org/
- **Cost**: Completely free, open-source
- **Features**:
  - Flow-based visual programming
  - Browser-based editor
  - 4,000+ nodes available
  - Lightweight runtime
  - MQTT, HTTP, WebSocket support
- **Webhook Handling**:
  - HTTP In node for receiving webhooks
  - Visual flow chaining
  - Integration with any service
- **Best For**: IoT integrations, visual debugging, low-code approach

#### 14. Pipedream (Developer Automation)
- **URL**: https://pipedream.com/
- **Cost**: Free tier available, paid from $50/mo
- **Features**:
  - Connect 1,500+ apps
  - Pre-built components
  - No server management
  - Real-time triggers
  - Custom code support
- **Webhook Handling**:
  - Receive webhooks via HTTP source
  - Connect to any app
  - Data transformation
- **Best For**: Quick integrations, no-infrastructure approach

#### 15. Bit Flows (Self-Hosted WordPress)
- **URL**: https://bit-flows.com/
- **Cost**: Free self-hosted
- **Features**:
  - WordPress-based automation
  - No separate server needed
  - Visual workflow builder
  - WordPress integration focus
- **Webhook Handling**:
  - Receive webhooks via WordPress
  - Trigger WordPress actions
  - Connect to external services
- **Best For**: WordPress users, low-cost self-hosted

#### 16. Shakudo (Data Workflow Platform)
- **URL**: https://www.shakudo.io/
- **Cost**: Cloud and self-hosted options
- **Features**:
  - AI workflow automation
  - n8n integration partnership
  - Data pipeline orchestration
  - Multiple framework support
- **Webhook Handling**:
  - HTTP endpoints for triggers
  - Connect to n8n workflows
  - Data transformation pipelines
- **Best For**: Data teams, AI/ML workflows, enterprise automation

#### 17. Lindy (AI Agent Platform)
- **URL**: https://www.lindy.ai/
- **Cost**: Free tier, paid plans available
- **Features**:
  - AI-powered workflow automation
  - 20+ AI agents for different tasks
  - Customizable workflows
  - Email, calendar, and task management
- **Webhook Handling**:
  - Receive webhooks as triggers
  - AI-powered response handling
  - Multi-channel notifications
- **Best For**: AI-assisted automation, productivity workflows

### Webhook Security Considerations

| Aspect | Recommendation |
|--------|----------------|
| **Authentication** | Use API keys, tokens, or HMAC signatures |
| **HTTPS** | Always use HTTPS for production webhooks |
| **Secret Keys** | Verify webhook signatures where supported |
| **Rate Limiting** | Implement exponential backoff on failures |
| **Timeout** | Set reasonable timeouts (5-10 seconds) |
| **Retry Logic** | 3 attempts with increasing delays |

### Webhook Payload Best Practices

```json
{
  "event": "command_completed",
  "timestamp": "2026-01-15T10:30:00Z",
  "data": {
    "hook_id": "ccbell-hook-001",
    "event_type": "stop",
    "message": "Claude finished",
    "duration_seconds": 45,
    "files_modified": 3
  }
}
```

### Webhook Features Summary

- Multiple webhook configurations per event type
- Event filtering (fire on specific events only)
- Custom headers and authentication
- Retry logic with exponential backoff
- Payload transformation support
- Rich media support (Slack, Discord, Telegram)
- Multi-channel routing via n8n/IFTTT/Zapier
- Self-hosted alternatives (Activepieces, Windmill, Node-RED, Shakudo)
- Developer-focused options (Pipedream, custom endpoints)
- AI-powered automation (Lindy, Activepieces AI)

## Research Sources

| Source | Description |
|--------|-------------|
| [Telegram Bot API](https://core.telegram.org/bots/api) | :books: Telegram bot documentation |
| [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks) | :books: Slack webhook integration guide |
| [WhatsApp Business API](https://developers.facebook.com/docs/whatsapp/cloud-api) | :books: WhatsApp cloud API docs |
| [n8n Webhooks](https://n8n.io/) | :books: n8n workflow automation |
| [IFTTT Maker Webhooks](https://ifttt.com/maker_webhooks) | :books: IFTTT Maker Webhooks documentation |
| [Zapier Webhooks](https://zapier.com/apps/webhook/integrations) | :books: Zapier webhook triggers |
| [Discord Webhooks](https://discord.com/developers/docs/resources/webhook) | :books: Discord webhook API docs |
| [Microsoft Teams Graph API](https://learn.microsoft.com/en-us/graph/api/resources/webhooks) | :books: Teams Graph API webhooks |
| [Make.com Webhooks](https://www.make.com/) | :books: Make automation platform |
| [Activepieces](https://www.activepieces.com/) | :books: Open-source AI-powered automation |
| [Windmill](https://www.windmill.dev/) | :books: Developer-focused script automation |
| [Node-RED](https://nodered.org/) | :books: Low-code flow-based automation |
| [Pipedream](https://pipedream.com/) | :books: Developer automation platform |
| [Bit Flows](https://bit-flows.com/) | :books: WordPress-based self-hosted automation |
| [Shakudo](https://www.shakudo.io/) | :books: AI workflow automation platform |
| [Lindy AI](https://www.lindy.ai/) | :books: AI agent platform for automation |
| [Go net/http package](https://pkg.go.dev/net/http) | :books: HTTP client |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main flow |
