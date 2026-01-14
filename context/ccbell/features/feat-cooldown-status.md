# Feature: Cooldown Status Display ⏱️

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
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

## Benefit

- **Reduced confusion**: Users understand why notifications aren't firing instead of assuming bugs
- **Faster troubleshooting**: Visual countdown helps users adjust cooldown settings intuitively
- **Better control**: Knowing exact timing helps users plan their workflow around notifications
- **Improved trust**: Transparent behavior makes ccbell feel more predictable and reliable

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Category** | Display |

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **State** | Modify | Add `GetCooldownRemaining(eventType string) int` method |
| **Commands** | Modify | Enhance `status` command with cooldown display |
| **Core Logic** | No change | Uses existing cooldown tracking |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/status.md** | Update | Add cooldown status section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/state/state.go:**
```go
func (s *State) GetCooldownRemaining(eventType string) int {
    if s.Cooldowns == nil { return 0 }

    endTime, ok := s.Cooldowns[eventType]
    if !ok { return 0 }

    remaining := int(time.Until(endTime).Seconds())
    if remaining < 0 { return 0 }
    return remaining
}

func formatDuration(seconds int) string {
    if seconds < 60 {
        return fmt.Sprintf("%ds", seconds)
    }
    if seconds < 3600 {
        return fmt.Sprintf("%dm %ds", seconds/60, seconds%60)
    }
    return fmt.Sprintf("%dh %dm", seconds/3600, (seconds%3600)/60)
}

func (c *CCBell) DisplayCooldownStatus(state *State, cfg *Config) {
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
            fmt.Printf("%-20s %s remaining (until %s)\n",
                eventType+":",
                formatDuration(remaining),
                time.Now().Add(time.Duration(remaining)*time.Second).Format("15:04:05"))
        }
    }
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "status" {
        stateManager := state.NewManager(homeDir)
        state, _ := stateManager.Load()
        cfg, _ := config.Load(homeDir)
        c := NewCCBell(cfg)
        c.DisplayCooldownStatus(state, cfg)
        return
    }
}
```

---

## References

### ccbell Implementation Research

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Cooldown storage
- [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Time calculation pattern
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event cooldown config

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/status.md` with cooldown status display |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.2.31+
- **Config Schema Change**: No schema change, enhances status output
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/status.md` (update with cooldown status section)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Update `commands/status.md` with cooldown status display format
- [ ] Add example output showing remaining time per event
- [ ] When ccbell v0.2.31+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time calculations |
| Linux | ✅ Supported | Time calculations |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
