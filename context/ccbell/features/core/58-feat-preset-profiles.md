# Feature: Preset Profiles

Built-in profile templates for common use cases.

## Summary

Provide pre-configured profile templates for different work scenarios.

## Motivation

- Quick setup for common scenarios
- No need to configure from scratch
- Best practices baked in

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Built-in Profiles

| Profile | Description | Volume | Quiet Hours |
|---------|-------------|--------|-------------|
| `default` | Standard notifications | 0.5 | None |
| `focus` | Quiet, minimal interruptions | 0.3 | 22:00-07:00 |
| `loud` | High volume, no quiet hours | 0.8 | None |
| `meeting` | Very subtle, meeting-friendly | 0.2 | 09:00-17:00 |
| `silent` | Visual only, no sounds | 0 | 00:00-23:59 |
| `work` | Balanced work environment | 0.5 | 22:00-07:00 |

### Configuration

```json
{
  "profiles": {
    "default": { ... },
    "focus": {
      "events": {
        "stop": { "enabled": true, "volume": 0.3, "sound": "bundled:soft" },
        "permission_prompt": { "enabled": true, "volume": 0.2, "sound": "bundled:gentle" },
        "idle_prompt": { "enabled": false },
        "subagent": { "enabled": true, "volume": 0.3 }
      },
      "quiet_hours": { "start": "22:00", "end": "07:00" }
    }
  }
}
```

### Implementation

```go
var presetProfiles = map[string]*Profile{
    "default": {
        Events: map[string]*Event{
            "stop": {Enabled: ptrBool(true), Volume: ptrFloat(0.5)},
            "permission_prompt": {Enabled: ptrBool(true), Volume: ptrFloat(0.7)},
            "idle_prompt": {Enabled: ptrBool(true), Volume: ptrFloat(0.5)},
            "subagent": {Enabled: ptrBool(true), Volume: ptrFloat(0.5)},
        },
    },
    "focus": {
        Events: map[string]*Event{
            "stop": {Enabled: ptrBool(true), Volume: ptrFloat(0.3)},
            "permission_prompt": {Enabled: ptrBool(true), Volume: ptrFloat(0.2)},
            "idle_prompt": {Enabled: ptrBool(false)},
            "subagent": {Enabled: ptrBool(true), Volume: ptrFloat(0.3)},
        },
        QuietHours: &QuietHours{Start: "22:00", End: "07:00"},
    },
    // ... more presets
}
```

### Commands

```bash
/ccbell:profile list --presets        # List all profiles including presets
/ccbell:profile use focus             # Switch to focus profile
/ccbell:profile create from-preset work  # Create custom from preset
/ccbell:profile show focus            # Show focus profile config
```

### Interactive Selection

```
$ /ccbell:profile wizard

=== Choose a Profile Preset ===

[1] Default      - Standard notifications (volume: 0.5)
[2] Focus        - Quiet, minimal interruptions (volume: 0.3)
[3] Loud         - High volume, no quiet hours (volume: 0.8)
[4] Meeting      - Meeting-friendly (volume: 0.2)
[5] Silent       - No sounds, visual only (volume: 0)

Select [1-5] or [c] custom: 2

Activating focus profile...
```

---

## Audio Player Compatibility

Preset profiles don't interact with audio playback:
- Purely config-based
- Uses existing player for sounds
- No player changes required

---

## Implementation

### Preset Loading

```go
func LoadPreset(name string) *Profile {
    if preset, ok := presetProfiles[name]; ok {
        // Return copy to prevent modification
        return deepCopyProfile(preset)
    }
    return nil
}
```

### Profile Wizard

```go
func runProfileWizard() error {
    fmt.Println("=== Choose a Profile Preset ===")
    // Display presets
    // Get user selection
    // Activate selected profile
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Profile structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L40-L43) - Profile definition
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - Profile loading
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Quiet hours pattern

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Config only |
| Linux | ✅ Supported | Config only |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
