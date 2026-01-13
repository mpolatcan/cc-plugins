# Feature: Quick Disable

Temporary pause without full disable. Quick toggle for short periods.

## Summary

Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration. Quick toggle via command.

## Technical Feasibility

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
