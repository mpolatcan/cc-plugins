# Feature: Minimal Mode 🎯

## Summary

Simplified configuration mode with fewer options for users who want simplicity.

## Benefit

- **Faster onboarding**: New users get value immediately
- **Reduced decision fatigue**: No overwhelming array of options
- **Opinionated defaults**: Sensible defaults for most use cases
- **Accessible to non-technical users**: Lower technical barrier

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Onboarding |

## Technical Feasibility

### Configuration

```json
{
  "mode": "minimal",
  "minimal": {
    "volume": 0.5,
    "quiet_hours": "22:00-07:00"
  }
}
```

### Interactive Setup

```
$ ccbell --wizard

=== ccbell Setup ===

1. Volume level (1-10) [5]: 6
2. Quiet hours? [22:00-07:00]:
3. All set!
```

### Implementation

```go
func GetMinimalConfig() *Config {
    return &Config{
        Enabled: ptr(true),
        Events: map[string]*Event{
            "stop": {
                Enabled: ptr(true),
                Sound:   ptr("bundled:default"),
                Cooldown: ptr(60),
            },
        },
    }
}

func (c *CCBell) RunWizard() {
    // Interactive questions for volume, quiet hours, events
}
```

### Commands

```bash
/ccbell:wizard                   # Interactive minimal setup
/ccbell:wizard --volume 5        # Non-interactive
/ccbell:wizard --full            # Exit to full config
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `mode`, `minimal` sections |
| **Core Logic** | Add | `GetMinimalConfig()`, `RunWizard()` |
| **Commands** | Add | `wizard` command |
| **New File** | Add | `internal/config/minimal.go` |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/wizard.md** | Add | New command doc |
| **commands/configure.md** | Update | Reference wizard |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102)
- [Default config](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L64-L77)
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go)

---

[Back to Feature Index](index.md)
