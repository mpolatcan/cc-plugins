# Feature: Event Aliases 🔄

## Summary

Define custom event names that map to existing events for flexibility.

## Benefit

- **Personalized workflow**: Use terminology matching your mental model
- **Simplified commands**: Short aliases reduce typing
- **Team standardization**: Share config templates with consistent naming
- **Easier onboarding**: "build-complete" vs event IDs

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Category** | Configuration |

## Technical Feasibility

### Configuration

```json
{
  "aliases": {
    "done": { "target": "stop", "enabled": true },
    "urgent": { "target": "permission_prompt", "sound": "custom:loud", "enabled": true }
  }
}
```

### Implementation

```go
func (c *CCBell) ResolveAlias(input string) string {
    if c.config.Aliases == nil { return input }

    if alias, ok := c.config.Aliases[input]; ok {
        if alias.Enabled == nil || *alias.Enabled {
            return alias.Event
        }
    }
    return input
}
```

### Commands

```bash
/ccbell:alias list                # List all aliases
/ccbell:alias add done stop       # Alias 'done' -> 'stop'
/ccbell:alias remove done         # Remove alias
/ccbell:alias enable done         # Enable alias
/ccbell:alias disable done        # Disable alias
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `aliases` section |
| **Core Logic** | Add | `ResolveAlias()` function |
| **Commands** | Add | `alias` command |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/alias.md** | Add | New command doc |
| **commands/configure.md** | Update | Reference aliases |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)

---

[Back to Feature Index](index.md)
