---
name: Session Hook Sounds
description: Add sound notifications for SessionStart and SessionEnd Claude Code hook events
---

# Feature: Session Hook Sounds

Add sound notifications for SessionStart and SessionEnd Claude Code hook events.

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

Extend ccbell to play sounds for session lifecycle events: SessionStart and SessionEnd. Know when a Claude Code session begins and ends without looking at the terminal.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Know when sessions start/end without looking at terminal |
| :memo: Use Cases | Long-running tasks, workflow tracking, productivity awareness |
| :dart: Value Proposition | Complete auditory coverage of Claude Code workflow |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🟢 Low |
| :construction: Complexity | 🟢 Low |
| :warning: Risk Level | 🟢 Low |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `session` command to manage session sounds |
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
| :hand: User Interaction | Users run `/ccbell:session configure` to enable/disable session sounds |
| :wrench: Configuration | Adds `session` section with session_start and session_end events |
| :gear: Default Behavior | Both session sounds disabled by default |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Add SessionStart and SessionEnd hook definitions |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `session.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Add session_start.aiff and session_end.aiff |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (add session event routing) |
| `config/config.go` | :wrench: Add `session` configuration section |
| `audio/player.go` | :speaker: Audio playback logic (no change needed) |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add SessionStart and SessionEnd hook definitions to hooks.json
4. Add session.md command documentation
5. Add session_start.aiff and session_end.aiff sound files
6. Commit and push

### ccbell

Steps required in ccbell repository:

1. Add session section to config structure
2. Update main.go to route session_start and session_end events
3. Update version in main.go
4. Tag and release vX.X.X
5. Sync version to cc-plugins

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

### Claude Code Session Hook Events

Claude Code supports session lifecycle hooks:

| Event | Trigger | Use Case |
|-------|---------|----------|
| `SessionStart` | Claude Code session begins | Session started notification |
| `SessionEnd` | Claude Code session ends | Session completed notification |

### Why Only Session Hooks?

Other hook events like `PreToolUse` and `PostToolUse` fire on EVERY tool call (potentially 100+ times per session), which would create audio chaos. Session hooks are:
- Infrequent (once per session)
- Meaningful (session lifecycle events)
- Non-intrusive (user won't be overwhelmed)

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

New hooks.json with session hooks:

```json
{
  "Stop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh stop", "timeout": 10 }] }],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh permission_prompt", "timeout": 10 }] },
    { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh idle_prompt", "timeout": 10 }] }
  ],
  "SubagentStop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh subagent", "timeout": 10 }] }],
  "SessionStart": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh session_start", "timeout": 10 }] }],
  "SessionEnd": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ccbell.sh session_end", "timeout": 10 }] }]
}
```

### Configuration Schema

New `session` configuration section:

```json
{
  "session": {
    "session_start": {
      "enabled": false,
      "sound": "bundled:session_start",
      "volume": 0.5
    },
    "session_end": {
      "enabled": false,
      "sound": "bundled:session_end",
      "volume": 0.5
    }
  }
}
```

### Sound Design

| Event | Suggested Sound |
|-------|-----------------|
| SessionStart | Gentle startup chime |
| SessionEnd | Soft exit sound |

### Go Implementation

#### Config Update

```go
type SessionConfig struct {
    Enabled  bool    `json:"enabled,omitempty"`
    Sound    string  `json:"sound,omitempty"`
    Volume   float64 `json:"volume,omitempty"`
}

type Config struct {
    // ... existing fields ...
    Session *SessionConfig `json:"session,omitempty"`
}
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
}
```

### Command Interface

New `/ccbell:session` command:

```
/ccbell:session          # Show current session configurations
/ccbell:session enable   # Enable session sounds
/ccbell:session disable  # Disable session sounds
/ccbell:session configure # Interactive setup for session sounds
```

## Research Sources

| Source | Description |
|--------|-------------|
| [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks) | :books: Official hooks reference |
| [Hook Development Skill](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md) | :books: Hook event types |
| [Current hooks.json](https://github.com/mpolatcan/cc-plugins/blob/main/plugins/ccbell/hooks/hooks.json) | :books: Current hook configuration |
| [Current main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main entry point |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Configuration handling |
