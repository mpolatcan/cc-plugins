# Feature: Cooldown Status Display ⏱️

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Display how much time remains before each event can trigger again.

## Motivation

- User knows when next notification will play
- Understand why some events don't trigger
- Debug cooldown configuration

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Current Cooldown Tracking

The current `internal/state/state.go` stores cooldown timestamps.

**Key Finding**: Adding status display is a simple calculation.

### Status Output

```
$ /ccbell:status cooldown

=== Cooldown Status ===

stop:               Ready (0s remaining)
permission_prompt:  Ready (0s remaining)
idle_prompt:        23s remaining (until 14:32:45)
subagent:           Ready (0s remaining)

Global cooldown:    Disabled
```

### Implementation

```go
func displayCooldownStatus(state *State, cfg *Config) {
    fmt.Println("=== Cooldown Status ===\n")

    for eventType := range config.ValidEvents {
        eventCfg := cfg.GetEventConfig(eventType)
        cooldown := *eventCfg.Cooldown

        if cooldown == 0 {
            fmt.Printf("%-20s Ready (0s remaining)\n", eventType+":")
            continue
        }

        remaining := state.GetCooldownRemaining(eventType)
        if remaining <= 0 {
            fmt.Printf("%-20s Ready (0s remaining)\n", eventType+":")
        } else {
            fmt.Printf("%-20s %ds remaining (until %s)\n",
                eventType+":",
                remaining,
                time.Now().Add(time.Duration(remaining)*time.Second).Format("15:04:05"))
        }
    }
}
```

### Commands

```bash
/ccbell:status              # Full status including cooldown
/ccbell:status cooldown     # Cooldown-specific status
/ccbell:cooldown reset      # Reset all cooldowns
/ccbell:cooldown check stop # Check specific event
```

---

## Audio Player Compatibility

Cooldown display doesn't interact with audio playback:
- Purely informational feature
- No player changes required
- Reads state, doesn't play audio

---

## Implementation

### State Extension

```go
func (s *State) GetCooldownRemaining(eventType string) int {
    if s.Cooldowns == nil {
        return 0
    }

    endTime, ok := s.Cooldowns[eventType]
    if !ok {
        return 0
    }

    remaining := int(time.Until(endTime).Seconds())
    if remaining < 0 {
        return 0
    }

    return remaining
}
```

### Pretty Formatting

```go
func formatDuration(seconds int) string {
    if seconds < 60 {
        return fmt.Sprintf("%ds", seconds)
    }
    if seconds < 3600 {
        return fmt.Sprintf("%dm %ds", seconds/60, seconds%60)
    }
    return fmt.Sprintf("%dh %dm", seconds/3600, (seconds%3600)/60)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### ccbell Implementation Research

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Cooldown storage
- [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Time calculation pattern
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event cooldown config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time calculations |
| Linux | ✅ Supported | Time calculations |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
