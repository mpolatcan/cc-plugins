# Feature: Event Aliases 🔄

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

Define custom event names that map to existing events for flexibility.

## Motivation

- Custom event naming for workflows
- Group multiple events under one name
- Simplified command interface

---

## Benefit

- **Personalized workflow**: Developers can use terminology that matches their mental model
- **Simplified commands**: Short aliases reduce typing and cognitive load
- **Team standardization**: Teams can share configuration templates with consistent naming
- **Easier onboarding**: New team members learn "build-complete" instead of memorizing event IDs

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Category** | Configuration |

---

## Technical Feasibility

### Alias Configuration

```go
type EventAlias struct {
    Alias     string   `json:"alias"`
    Target    string   `json:"target"`      // stop, permission_prompt, etc.
    Sound     string   `json:"sound"`       // Override sound
    Volume    float64  `json:"volume"`      // Override volume
    Enabled   bool     `json:"enabled"`
}

type AliasStore struct {
    Aliases map[string]*EventAlias `json:"aliases"`
}
```

### Configuration

```json
{
  "aliases": {
    "done": {
      "alias": "done",
      "target": "stop",
      "enabled": true
    },
    "attention": {
      "alias": "attention",
      "target": "permission_prompt",
      "sound": "custom:loud-bell",
      "volume": 0.8,
      "enabled": true
    },
    "complete": {
      "alias": "complete",
      "target": "subagent",
      "enabled": true
    }
  }
}
```

### Commands

```bash
/ccbell:alias list                # List all aliases
/ccbell:alias add done stop       # Alias 'done' -> 'stop'
/ccbell:alias add urgent permission_prompt --sound custom:loud
/ccbell:alias remove done         # Remove alias
/ccbell:alias enable done         # Enable alias
/ccbell:alias disable done        # Disable alias
/ccbell:alias run done            # Test alias
```

### Output

```
$ ccbell:alias list

=== Event Aliases ===

[1] done -> stop
    Enabled: Yes
    Sound: bundled:stop (default)

[2] urgent -> permission_prompt
    Enabled: Yes
    Sound: custom:loud-bell (override)

[3] complete -> subagent
    Enabled: No
    Sound: bundled:subagent (default)

[Add] [Edit] [Remove] [Test]
```

---

## Audio Player Compatibility

Event aliases don't play sounds:
- Routing feature
- Uses existing player for final event

---

## Implementation

### Alias Resolution

```go
func (a *AliasManager) Resolve(eventType string) (string, *EventConfig, error) {
    // Check if it's an alias
    alias, isAlias := a.aliases[eventType]
    if !isAlias {
        // Not an alias, use as-is
        return eventType, nil, nil
    }

    if !alias.Enabled {
        return "", nil, fmt.Errorf("alias '%s' is disabled", eventType)
    }

    // Get target event config
    targetCfg := a.config.GetEventConfig(alias.Target)

    // Apply overrides
    if alias.Sound != "" {
        targetCfg.Sound = alias.Sound
    }
    if alias.Volume > 0 {
        targetCfg.Volume = &alias.Volume
    }

    return alias.Target, targetCfg, nil
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
| **Config** | Add | Add `aliases` section with name → event mappings |
| **Core Logic** | Modify | Add `ResolveAlias(input string) string` function |
| **Main Flow** | Modify | Check aliases before looking up event config |
| **Commands** | Add | New `alias` command (list, add, remove, enable, disable) |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/alias.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference alias configuration |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/aliases.go:**
```go
type AliasConfig struct {
    Aliases map[string]*Alias `json:"aliases,omitempty"`
}

type Alias struct {
    Event     string `json:"event"`
    Enabled   *bool  `json:"enabled,omitempty"`
    CreatedAt string `json:"created_at,omitempty"`
}

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

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "alias" {
        handleAliasCommand(os.Args[2:])
        return
    }

    // In main flow, resolve aliases
    eventType := os.Args[1]
    eventType = ccbell.ResolveAlias(eventType)
}
```

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event configuration
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event validation

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/alias.md` for alias management |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `aliases` section to config (see Configuration section)
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/alias.md` (new file with list, add, remove, enable, disable commands)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/alias.md` with all alias commands
- [ ] Document alias configuration format
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
