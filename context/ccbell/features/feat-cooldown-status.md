# Feature: Cooldown Status Display ⏱️

## Summary

Display how much time remains before each event can trigger again.

## Benefit

- **Reduced confusion**: Users understand why notifications aren't firing
- **Faster troubleshooting**: Visual countdown helps adjust cooldown settings
- **Better control**: Knowing exact timing helps plan workflow
- **Improved trust**: Transparent behavior makes ccbell predictable

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Category** | Display |

## Technical Feasibility

### Status Output

```
$ /ccbell:status cooldown

=== Cooldown Status ===

stop:               Ready (0s remaining)
permission_prompt:  Ready (0s remaining)
idle_prompt:        23s remaining (until 14:32:45)
subagent:           Ready (0s remaining)
```

### Implementation

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
```

### Commands

```bash
/ccbell:status              # Full status including cooldown
/ccbell:status cooldown     # Cooldown-specific status
/ccbell:cooldown reset      # Reset all cooldowns
```

## Configuration

No config changes - enhances status display.

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **State** | Add | `GetCooldownRemaining()` method |
| **Commands** | Modify | Enhance `status` command |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/status.md** | Update | Add cooldown section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
- [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)

---

[Back to Feature Index](index.md)
