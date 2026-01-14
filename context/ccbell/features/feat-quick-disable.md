# Feature: Quick Disable ⏸️

## Summary

Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration. Quick toggle via command.

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

## Technical Feasibility

### Configuration

```json
{
  "quick_disable": {
    "enabled": true,
    "default_duration": "1h"
  }
}
```

### Implementation

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
    c.config.ActiveProfile = "silent"
    return c.saveState()
}

func (c *CCBell) IsQuickDisabled() bool {
    if c.quickDisable == nil {
        return false
    }
    return time.Now().Before(c.quickDisable.until)
}

func (c *CCBell) CancelQuickDisable() {
    if c.quickDisable != nil {
        c.config.ActiveProfile = c.quickDisable.profile
        c.quickDisable = nil
        c.saveState()
    }
}
```

### Commands

```bash
/ccbell:quiet 15m       # Disable for 15 minutes
/ccbell:quiet 1h        # Disable for 1 hour
/ccbell:quiet 4h        # Disable for 4 hours
/ccbell:quiet status    # Show time remaining
/ccbell:quiet cancel    # Cancel quick disable
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **State** | Add | Add `QuickDisableUntil` timestamp field |
| **Core Logic** | Add | Add `IsQuickDisabled() bool` and `SetQuickDisable(duration)` methods |
| **Commands** | Add | New `quiet` command (15m, 1h, 4h, status, cancel) |
| **Main Flow** | Modify | Check quick disable in `ShouldNotify()` |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/quiet.md** | Add | New command documentation |
| **commands/status.md** | Update | Add quick disable status |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
- [State file location](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)

---

[Back to Feature Index](index.md)
