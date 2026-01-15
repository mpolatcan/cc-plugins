---
name: Webhooks
description: Send HTTP requests to configured URLs when events trigger for integration with Slack, IFTTT, Zapier
---

# Webhooks

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
| :rocket: Priority | `[High]` |
| :construction: Complexity | `[Medium]` |
| :warning: Risk Level | `[Medium]` |

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
| :speaker: afplay | Not affected - webhooks sent alongside/independently |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

Uses Go's `net/http` package for HTTP requests.

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
| None | net/http | HTTP client | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New webhooks command can be added.

### Claude Code Hooks

No new hooks needed - webhooks integrated into main flow.

### Audio Playback

Webhooks sent independently of audio playback.

### Other Findings

Webhook features:
- Multiple webhook configurations
- Event filtering per webhook
- Custom headers support
- Retry logic with exponential backoff
- JSON payload with event data

## Research Sources

| Source | Description |
|--------|-------------|
| [Go net/http package](https://pkg.go.dev/net/http) | :books: HTTP client |
| [Slack Webhooks](https://api.slack.com/messaging/webhooks) | :books: Slack integration |
| [IFTTT Webhooks](https://ifttt.com/maker_webhooks) | :books: IFTTT integration |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main flow |
