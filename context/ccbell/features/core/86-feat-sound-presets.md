# Feature: Sound Presets

Save and load sound configurations as presets.

## Summary

Create named presets for quick sound configuration switching.

## Motivation

- Different presets for different work contexts
- Quick switching between sound themes
- Share configurations with team

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Preset Structure

```go
type SoundPreset struct {
    Name        string                 `json:"name"`
    Description string                 `json:"description"`
    Events      map[string]EventConfig `json:"events"`
    CreatedAt   time.Time              `json:"created_at"`
    UpdatedAt   time.Time              `json:"updated_at"`
}

type PresetStore struct {
    Presets    map[string]*SoundPreset `json:"presets"`
    ActivePreset string                `json:"active_preset"`
}
```

### Configuration

```json
{
  "preset": "work",
  "presets": {
    "work": {
      "name": "Work Mode",
      "description": "Quiet sounds for office",
      "events": {
        "stop": { "sound": "bundled:soft", "volume": 0.3 },
        "permission_prompt": { "sound": "bundled:gentle", "volume": 0.2 },
        "idle_prompt": { "enabled": false },
        "subagent": { "sound": "bundled:subtle", "volume": 0.3 }
      }
    },
    "home": {
      "name": "Home Mode",
      "description": "Full notifications",
      "events": {
        "stop": { "sound": "custom:bell", "volume": 0.7 },
        "permission_prompt": { "sound": "bundled:alert", "volume": 0.6 },
        "idle_prompt": { "sound": "bundled:notify", "volume": 0.5 },
        "subagent": { "sound": "bundled:complete", "volume": 0.6 }
      }
    }
  }
}
```

### Commands

```bash
/ccbell:preset list                # List all presets
/ccbell:preset use work            # Switch to work preset
/ccbell:preset create meeting      # Create from current
/ccbell:preset create meeting --copy work
/ccbell:preset export meeting      # Export preset
/ccbell:preset import meeting.json # Import preset
/ccbell:preset delete meeting      # Remove preset
/ccbell:preset rename work focus   # Rename preset
/ccbell:preset info meeting        # Show preset details
```

### Output

```
$ ccbell:preset list

=== Sound Presets ===

[1] work              (Active)
    Description: Quiet sounds for office
    Events: 3 enabled, 1 disabled
    Last used: 2 hours ago

[2] home
    Description: Full notifications
    Events: 4 enabled
    Last used: 2 days ago

[3] meeting
    Description: Silent except critical
    Events: 1 enabled, 3 disabled
    Last used: 1 week ago

Showing 3 presets
[Use] [Edit] [Export] [Delete] [Create New]
```

---

## Audio Player Compatibility

Presets don't play sounds:
- Configuration management feature
- No player changes required

---

## Implementation

### Preset Creation

```go
func (p *PresetManager) CreateFromCurrent(name, description string) (*SoundPreset, error) {
    preset := &SoundPreset{
        Name:        name,
        Description: description,
        Events:      make(map[string]EventConfig),
        CreatedAt:   time.Now(),
        UpdatedAt:   time.Now(),
    }

    // Copy current event configurations
    for event, cfg := range p.config.Events {
        preset.Events[event] = EventConfig{
            Enabled: derefBool(cfg.Enabled, true),
            Sound:   cfg.Sound,
            Volume:  derefFloat(cfg.Volume, 0.5),
        }
    }

    p.store.Presets[name] = preset
    return preset, p.savePresets()
}
```

### Preset Application

```go
func (p *PresetManager) Apply(presetName string) error {
    preset, ok := p.store.Presets[presetName]
    if !ok {
        return fmt.Errorf("preset not found: %s", presetName)
    }

    // Apply preset events to current config
    for event, eventCfg := range preset.Events {
        if _, exists := p.config.Events[event]; !exists {
            p.config.Events[event] = &config.EventConfig{}
        }
        p.config.Events[event].Enabled = &eventCfg.Enabled
        p.config.Events[event].Sound = eventCfg.Sound
        p.config.Events[event].Volume = &eventCfg.Volume
    }

    p.store.ActivePreset = presetName
    return p.config.Save()
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event configuration
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Config loading
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
