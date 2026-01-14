# Feature: Minimal Mode 🎯

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

Simplified configuration mode with fewer options for users who want simplicity.

## Motivation

- Lower barrier to entry
- Fewer decisions to make
- "It just works" experience

---

## Benefit

- **Faster onboarding**: New users get value immediately without configuration
- **Reduced decision fatigue**: No overwhelming array of options
- **Opinionated defaults**: Sensible defaults work well for most use cases
- **Accessible to non-technical users**: Lower technical barrier to entry

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Onboarding |

---

## Technical Feasibility

### Minimal Configuration

```json
{
  "minimal": {
    "enabled": true,
    "volume": 0.5,
    "quiet_hours": "22:00-07:00"
  }
}
```

### Conversion to Full Config

```go
func expandMinimalConfig(minimal *MinimalConfig) *Config {
    cfg := &Config{
        Enabled:       true,
        ActiveProfile: "default",
        QuietHours: &QuietHours{
            Start: "22:00",
            End:   "07:00",
        },
        Events: map[string]*Event{
            "stop": {
                Enabled: ptrBool(true),
                Sound:   "bundled:stop",
                Volume:  ptrFloat(minimal.Volume),
                Cooldown: ptrInt(0),
            },
            "permission_prompt": {
                Enabled: ptrBool(true),
                Sound:   "bundled:permission_prompt",
                Volume:  ptrFloat(minimal.Volume * 1.2),
                Cooldown: ptrInt(0),
            },
            "idle_prompt": {
                Enabled: ptrBool(true),
                Sound:   "bundled:idle_prompt",
                Volume:  ptrFloat(minimal.Volume * 0.8),
                Cooldown: ptrInt(0),
            },
            "subagent": {
                Enabled: ptrBool(true),
                Sound:   "bundled:subagent",
                Volume:  ptrFloat(minimal.Volume),
                Cooldown: ptrInt(0),
            },
        },
    }

    if minimal.QuietHours != "" {
        // Parse "HH:MM-HH:MM" format
        parts := strings.Split(minimal.QuietHours, "-")
        if len(parts) == 2 {
            cfg.QuietHours.Start = strings.TrimSpace(parts[0])
            cfg.QuietHours.End = strings.TrimSpace(parts[1])
        }
    }

    return cfg
}
```

### Interactive Setup

```
$ ccbell --wizard

=== ccbell Setup ===

Quick setup - answer a few questions

1. Volume level (1-10) [5]: 6

2. Quiet hours? (no loud sounds)
   Enter time range, e.g., "22:00-07:00" or "n" for none [22:00-07:00]:

3. All set! Creating config...

✓ Config created
✓ Sounds ready
✓ Run 'ccbell test all' to test
```

### Commands

```bash
/ccbell:wizard                   # Interactive minimal setup
/ccbell:wizard --volume 5        # Non-interactive
/ccbell:wizard --quiet-hours 22:00-07:00
/ccbell:wizard --full            # Exit minimal, go to full config
```

### Config Switching

```json
{
  "mode": "minimal",  // or "full"
  "minimal": {
    "volume": 0.6,
    "quiet_hours": "22:00-07:00"
  },
  "full": {
    // Full config available when mode=full
  }
}
```

### Validation in Minimal Mode

```go
func validateMinimal(config *MinimalConfig) error {
    if config.Volume < 0 || config.Volume > 1 {
        return errors.New("volume must be 0.0-1.0")
    }

    if config.QuietHours != "" {
        if !timeFormatRegex.MatchString(config.QuietHours) {
            return errors.New("invalid quiet hours format (use HH:MM-HH:MM)")
        }
    }

    return nil
}
```

---

## Audio Player Compatibility

Minimal mode doesn't interact with audio playback:
- Purely config transformation
- Uses existing player for sounds
- No player changes required

---

## Implementation

### Mode Detection

```go
func LoadConfig(homeDir string) (*Config, error) {
    cfg := Default()

    // Check for minimal config first
    minimalPath := filepath.Join(homeDir, ".claude", "ccbell-minimal.json")
    if data, err := os.ReadFile(minimalPath); err == nil {
        var minimal MinimalConfig
        if err := json.Unmarshal(data, &minimal); err == nil {
            // Convert and return expanded config
            return expandMinimalConfig(&minimal), nil
        }
    }

    // Load full config
    // ... existing logic
}
```

### Help in Minimal Mode

```
$ ccbell:help

Minimal Mode Commands:
  status          - Show current status
  test all        - Test all sounds
  volume          - Show/adjust volume
  quiet           - Configure quiet hours
  upgrade         - Switch to full configuration

Full help: ccbell:help --full
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
| **Config** | Add | Add `mode` field (minimal/full) and `minimal` preset section |
| **Core Logic** | Add | Add `GetMinimalConfig()` preset generator |
| **Commands** | Add | New `wizard` command for interactive setup |
| **New File** | Add | `internal/config/minimal.go` for preset configs |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/wizard.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference wizard option |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/minimal.go:**
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
    questions := []Question{
        {"Enable sounds?", &c.config.Enabled},
        {"Which events?", &c.config.Events},
        {"Default sound?", &c.soundSelection},
        {"Volume (0.0-1.0)?", &c.volume},
    }

    for _, q := range questions {
        q.Ask()
    }

    c.config = GetMinimalConfig()
    c.config.Events["stop"].Volume = ptr(c.volume)
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "wizard" {
        cfg := &config.Config{}
        ccbell := NewCCBell(cfg)
        ccbell.RunWizard()
        cfg.Save()
        return
    }
}
```

---

## References

### ccbell Implementation Research

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - Config expansion
- [Default config](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L64-L77) - Default values
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Quiet hours pattern

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/wizard.md` for interactive setup |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `mode` field (minimal/full) and `minimal` config section
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/wizard.md` (new file for interactive wizard)
  - `plugins/ccbell/commands/configure.md` (update to reference wizard)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/wizard.md` with interactive setup flow
- [ ] Update `commands/configure.md` to reference wizard option
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Config only |
| Linux | ✅ Supported | Config only |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
