---
name: Extra Hook Sounds
description: Add sound notifications for additional Claude Code hook events (SessionStart, SessionEnd, PreToolUse, PostToolUse, UserPromptSubmit)
---

# Feature: Extra Hook Sounds

Add sound notifications for additional Claude Code hook events beyond the current Stop, Notification, and SubagentStop support.

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

Extend ccbell to play sounds for additional Claude Code hook events: SessionStart, SessionEnd, PreToolUse, PostToolUse, and UserPromptSubmit. This enables users to have auditory awareness of more workflow events.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Know when sessions start/end without looking at terminal |
| :memo: Use Cases | Long-running tasks, workflow tracking, productivity awareness |
| :dart: Value Proposition | Complete auditory coverage of Claude Code workflow |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🟡 Medium |
| :construction: Complexity | 🟢 Low |
| :warning: Risk Level | 🟢 Low |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `hooks` command to manage extra hook sounds |
| :hook: Hooks | Add new hook definitions to hooks.json |
| :toolbox: Tools | Read, Write, Bash tools for hook configuration |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay (macOS) | macOS native audio player |
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | AIFF, MP3, WAV supported |

### External Dependencies

Are external tools or libraries required?

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ➖ |

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:hooks configure` to enable/disable extra hook sounds |
| :wrench: Configuration | Adds `hooks` section with event → sound mappings |
| :gear: Default Behavior | All extra hook sounds disabled by default |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Add new hook definitions for extra events |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `hooks.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Add new sounds for extra hooks |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (add hook event routing) |
| `config/config.go` | :wrench: Add `hooks` configuration section |
| `audio/player.go` | :speaker: Audio playback logic (no change needed) |
| `internal/hooks/hooks.go` | :hook: Hook event handling |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add new hook definitions to hooks.json
4. Add hooks.md command documentation
5. Add new sound files for extra hooks
6. Commit and push

### ccbell

Steps required in ccbell repository:

1. Add hooks section to config structure
2. Create internal/hooks/hooks.go for event handling
3. Update main.go to route new hook events
4. Add `--hook` flag to specify which hook event triggered
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ➖ |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Available Hook Events

Claude Code supports the following hook events:

| Event | Trigger | Use Case for Sound |
|-------|---------|-------------------|
| `SessionStart` | Claude Code session begins | Session started notification |
| `SessionEnd` | Claude Code session ends | Session completed notification |
| `Stop` | Main agent considers stopping | ✅ Already supported |
| `SubagentStop` | Subagent considers stopping | ✅ Already supported |
| `Notification` | Permission/idle prompts | ✅ Already supported |
| `PreToolUse` | Before any tool is called | Tool execution started |
| `PostToolUse` | After a tool completes | Tool execution finished |
| `UserPromptSubmit` | User submits a prompt | User input received |
| `PreCompact` | Before transcript compaction | Internal event |

### Current Hook Configuration

Current ccbell hooks.json:

```json
{
  "Stop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh stop", "timeout": 10 }] }],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh permission_prompt", "timeout": 10 }] },
    { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh idle_prompt", "timeout": 10 }] }
  ],
  "SubagentStop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh subagent", "timeout": 10 }] }]
}
```

### Proposed Hook Configuration

New hooks.json with extra hook sounds:

```json
{
  "Stop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh stop", "timeout": 10 }] }],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh permission_prompt", "timeout": 10 }] },
    { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh idle_prompt", "timeout": 10 }] }
  ],
  "SubagentStop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh subagent", "timeout": 10 }] }],
  "SessionStart": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh session_start", "timeout": 10 }] }],
  "SessionEnd": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh session_end", "timeout": 10 }] }],
  "PreToolUse": [{ "matcher": ".*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh pretooluse", "timeout": 5 }] }],
  "PostToolUse": [{ "matcher": ".*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh posttooluse", "timeout": 5 }] }],
  "UserPromptSubmit": [{ "matcher": ".*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh user_prompt", "timeout": 10 }] }]
}
```

### Configuration Schema

New `hooks` configuration section:

```json
{
  "hooks": {
    "session_start": {
      "enabled": false,
      "sound": "bundled:session_start",
      "volume": 0.5,
      "cooldown": 0
    },
    "session_end": {
      "enabled": false,
      "sound": "bundled:session_end",
      "volume": 0.5,
      "cooldown": 0
    },
    "pretooluse": {
      "enabled": false,
      "sound": "bundled:pretooluse",
      "volume": 0.3,
      "cooldown": 1
    },
    "posttooluse": {
      "enabled": false,
      "sound": "bundled:posttooluse",
      "volume": 0.3,
      "cooldown": 1
    },
    "user_prompt": {
      "enabled": false,
      "sound": "bundled:user_prompt",
      "volume": 0.5,
      "cooldown": 0
    }
  }
}
```

### Sound Design Considerations

| Hook Event | Suggested Sound | Cooldown |
|------------|-----------------|----------|
| SessionStart | Gentle startup chime | 0s |
| SessionEnd | Soft exit sound | 0s |
| PreToolUse | Very subtle click | 1s |
| PostToolUse | Very subtle click | 1s |
| UserPromptSubmit | Notification-like | 0s |

**Note:** PreToolUse and PostToolUse fire very frequently (on every tool call), so sounds should be:
- Very short in duration
- Lower volume
- Longer cooldowns enabled by default

### Go Implementation

#### Config Update

```go
type HookConfig struct {
    Enabled  bool    `json:"enabled,omitempty"`
    Sound    string  `json:"sound,omitempty"`
    Volume   float64 `json:"volume,omitempty"`
    Cooldown int     `json:"cooldown,omitempty"`
}

type Config struct {
    // ... existing fields ...
    Hooks map[string]*HookConfig `json:"hooks,omitempty"`
}

// Extra hook events
const (
    HookSessionStart    = "session_start"
    HookSessionEnd      = "session_end"
    HookPreToolUse      = "pretooluse"
    HookPostToolUse     = "posttooluse"
    HookUserPromptSubmit = "user_prompt"
)
```

#### Main.go Update

```go
// Add new event types
var validEvents = map[string]bool{
    "stop":              true,
    "permission_prompt": true,
    "idle_prompt":       true,
    "subagent":          true,
    "session_start":     true,
    "session_end":       true,
    "pretooluse":        true,
    "posttooluse":       true,
    "user_prompt":       true,
}
```

### Command Interface

New `/ccbell:hooks` command:

```
/ccbell:hooks          # Show current hook configurations
/ccbell:hooks enable   # Enable a specific hook sound
/ccbell:hooks disable  # Disable a specific hook sound
/ccbell:hooks configure # Interactive setup for hook sounds
```

### Research Sources

| Source | Description |
|--------|-------------|
| [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks) | :books: Official hooks reference |
| [Hook Development Skill](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md) | :books: Hook event types |
| [Current hooks.json](https://github.com/mpolatcan/cc-plugins/blob/main/plugins/ccbell/hooks/hooks.json) | :books: Current hook configuration |
| [Current main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main entry point |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Configuration handling |
