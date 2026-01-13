# Feature: Quick Disable

Temporary pause without full disable. Quick toggle for short periods.

## Summary

Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration. Quick toggle via command.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

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

## References

- [Current state management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
