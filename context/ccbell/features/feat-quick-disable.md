# Feature: Quick Disable ⏸️

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

Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration. Quick toggle via command.

## Motivation

- Quick breaks without full config changes
- Meeting-mode instant toggle
- Focus session temporary silence
- No permanent state changes

---

## Benefit

- **Instant focus**: One command silences notifications temporarily
- **No config editing**: No need to modify config files for temporary changes
- **Auto-restores**: Notifications automatically resume after the timeout
- **Meeting-ready**: Quick toggle for calls without leaving ccbell disabled

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Notification Control |

---

## Technical Feasibility

### Current State Analysis

The current `internal/state/state.go` already handles:
- Cooldown tracking
- Persisted state across invocations

**Key Finding**: Quick disable can extend the state manager with a `quickDisableUntil` timestamp.

### Timer-Based Disable

```go
type QuickDisable struct {
    until   time.Time
    profile string
}

func (c *CCBell) QuickDisable(duration time.Duration) error {
    c.quickDisable = &QuickDisable{
        until:   time.Now().Add(duration),
        profile: c.config.ActiveProfile,
    }

    // Temporarily switch to silent
    c.config.ActiveProfile = "silent"

    // Save state
    return c.saveState()
}

func (c *CCBell) checkQuickDisable() {
    if c.quickDisable != nil && time.Now().After(c.quickDisable.until) {
        c.config.ActiveProfile = c.quickDisable.profile
        c.quickDisable = nil
        c.saveState()
    }
}
```

## Commands

```bash
/ccbell:quiet 15m      # Disable for 15 minutes
/ccbell:quiet 1h       # Disable for 1 hour
/ccbell:quiet 4h       # Disable for 4 hours
/ccbell:quiet status   # Show time remaining
/ccbell:quiet cancel   # Cancel quick disable
```

## Output

```
Quick disable active: 14:32 remaining
Will restore profile: default
```

---

## Feasibility Research

### Audio Player Compatibility

Quick disable doesn't interact with audio playback. It affects the decision to play sound.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Works with current architecture |
| Linux | ✅ Supported | Works with current architecture |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### State Storage

Extend `internal/state/state.go`:

```go
type State struct {
    LastPlayed   map[string]time.Time `json:"lastPlayed,omitempty"`
    Cooldowns    map[string]time.Time `json:"cooldowns,omitempty"`
    QuickDisable *QuickDisableState    `json:"quickDisable,omitempty"`
}

type QuickDisableState struct {
    Until   time.Time `json:"until"`
    Profile string    `json:"profile"`
}
```

### Integration Point

In `cmd/ccbell/main.go`, add check after config load:

```go
// Check quick disable
stateManager := state.NewManager(homeDir)
if state, err := stateManager.Load(); err == nil {
    if state.QuickDisable != nil && time.Now().Before(state.QuickDisable.Until) {
        log.Debug("Quick disable active, exiting")
        return nil
    }
}
```

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
| **State** | Add | Add `QuickDisableUntil` timestamp field |
| **Core Logic** | Add | Add `IsQuickDisabled() bool` and `SetQuickDisable(duration)` methods |
| **Commands** | Add | New `quiet` command (15m, 1h, 4h, status, cancel) |
| **Main Flow** | Modify | Check quick disable in `ShouldNotify()` |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/quiet.md** | Add | New command documentation |
| **commands/status.md** | Update | Add quick disable status |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/state/state.go:**
```go
type State struct {
    Cooldowns       map[string]time.Time `json:"cooldowns,omitempty"`
    QuickDisableUntil *time.Time        `json:"quick_disable_until,omitempty"`
}

func (s *State) IsQuickDisabled() bool {
    if s.QuickDisableUntil == nil {
        return false
    }
    return time.Now().Before(*s.QuickDisableUntil)
}

func (s *State) SetQuickDisable(duration time.Duration) {
    now := time.Now()
    s.QuickDisableUntil = &now
    *s.QuickDisableUntil = now.Add(duration)
}

func (s *State) CancelQuickDisable() {
    s.QuickDisableUntil = nil
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "quiet" {
        handleQuietCommand(os.Args[2:])
        return
    }

    // Check quick disable
    if state.IsQuickDisabled() {
        log.Info("Quick disable active until %s", state.QuickDisableUntil.Format("15:04"))
        return
    }
}

func handleQuietCommand(args []string) {
    stateManager := state.NewManager(homeDir)
    state, _ := stateManager.Load()

    switch args[0] {
    case "15m":
        state.SetQuickDisable(15 * time.Minute)
    case "1h":
        state.SetQuickDisable(1 * time.Hour)
    case "4h":
        state.SetQuickDisable(4 * time.Hour)
    case "cancel":
        state.CancelQuickDisable()
    case "status":
        if state.IsQuickDisabled() {
            fmt.Printf("Quick disabled until %s\n", state.QuickDisableUntil.Format("15:04"))
        } else {
            fmt.Println("Quick disabled: inactive")
        }
    }
    stateManager.Save(state)
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/quiet.md` for quick disable commands |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: No schema change, extends state with `quickDisableUntil` timestamp
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/quiet.md` (new file with 15m, 1h, 4h, status, cancel commands)
  - `plugins/ccbell/commands/status.md` (update to show quick disable status)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/quiet.md` with quick disable commands
- [ ] Update `commands/status.md` with quick disable status
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## References

### ccbell Implementation Research

- [Current state management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Base to extend with quick disable state
- [State file location](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - `~/.claude/ccbell.state` pattern
- [Time parsing](https://pkg.go.dev/time) - Go time package for duration handling

---

[Back to Feature Index](index.md)
