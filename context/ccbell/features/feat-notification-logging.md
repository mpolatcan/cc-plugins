---
name: Notification Logging
description: Maintain a detailed log of all notification events for debugging and analysis
---

# Feature: Notification Logging

Maintain a detailed log of all notification events for debugging and analysis.

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

Maintain a detailed log of all notification events for debugging and analysis. Provides historical visibility into notification behavior.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Review what notifications fired and when |
| :memo: Use Cases | Pattern recognition, audit trail, troubleshooting |
| :dart: Value Proposition | Data-driven optimization based on log data |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `🟢` |
| :construction: Complexity | `🟢` |
| :warning: Risk Level | `🟢` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `log` command with tail/show/clear/stats |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for log operations |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected by this feature |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:log` commands to view/manage logs |
| :wrench: Configuration | Adds `logging` section to config |
| :gear: Default Behavior | Logs notification events automatically |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `log.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `logging` section |
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

1. Add logging section to config structure
2. Create internal/logger/notification.go
3. Implement Logger with Append/Rotate methods
4. Add log command with tail/show/clear/stats options
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `➖` |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New log command can be added.

### Claude Code Hooks

No new hooks needed - logging integrated into main flow.

### Audio Playback

Not affected by this feature.

### Logging Implementation Patterns

#### Structured Logging (Recommended)
```go
type NotificationLog struct {
    ID           string    `json:"id"`
    Timestamp    time.Time `json:"timestamp"`
    EventType    string    `json:"event_type"`
    Sound        string    `json:"sound"`
    Volume       float64   `json:"volume"`
    Profile      string    `json:"profile,omitempty"`
    Duration     float64   `json:"duration_seconds,omitempty"`
    Suppressed   bool      `json:"suppressed"`
    Reason       string    `json:"reason,omitempty"`
    TokenCount   int       `json:"token_count,omitempty"`
}
```

#### Log Rotation with go-rotatelogs
- **URL**: https://github.com/lestrrat-go/rotatelogs
- **Features**:
  - Time-based rotation
  - Size-based rotation
  - Compression support
  - Cleanup policies
- **Install**: `go get github.com/lestrrat-go/rotatelogs`

```go
import "github.com/lestrrat-go/rotatelogs"

log, _ := rotatelogs.New(
    "/var/log/ccbell notifications.%Y%m%d%H%M.log",
    rotatelogs.WithMaxAge(24 * time.Hour),
    rotatelogs.WithRotationTime(time.Hour),
)
```

#### Log Analysis Commands
```bash
# View recent logs
/ccbell:log tail

# Filter by event type
/ccbell:log show --event stop

# Show statistics
/ccbell:log stats

# Export to JSON
/ccbell:log export --format json > ccbell.json

# Search for suppressed notifications
/ccbell:log show --suppressed
```

### Logging Features

- **Timestamp, event type, sound, volume tracking**
- **Suppression reasons** (quiet_hours, cooldown, throttling, DND)
- **Log rotation** with max size and file count
- **Statistics and query capabilities**
- **Structured output** (JSON, text)
- **Log compression** for disk efficiency
- **Real-time tail** with follow mode

### Log Query Patterns

| Query | Command |
|-------|---------|
| Last N entries | `/ccbell:log tail --count 100` |
| By event type | `/ccbell:log show --event stop` |
| Time range | `/ccbell:log show --from "2026-01-15 10:00" --to "2026-01-15 12:00"` |
| Suppressed only | `/ccbell:log show --suppressed` |
| Statistics | `/ccbell:log stats` |

## Research Sources

| Source | Description |
|--------|-------------|
| [lestrrat-go/rotatelogs](https://github.com/lestrrat-go/rotatelogs) | :books: Log rotation library |
| [Go log package](https://pkg.go.dev/log) | :books: Standard logging |
| [Zap Logger](https://github.com/uber-go/zap) | :books: High-performance structured logging |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main flow |
| [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: State management |
| [Logger pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go) | :books: Logger implementation |
