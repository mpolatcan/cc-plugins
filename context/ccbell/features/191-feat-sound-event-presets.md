# Feature: Sound Event Presets

Quick configuration presets.

## Summary

Apply predefined configuration presets for common scenarios.

## Motivation

- Quick setup
- Common scenarios
- Easy switching

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Preset Types

| Preset | Description | Settings |
|--------|-------------|----------|
| Work | Office settings | Normal volume, no quiet hours |
| Home | Home settings | Lower volume, evening quiet |
| Meeting | Meeting mode | Silent except important |
| Focus | Deep work | All sounds off |
| Night | Night mode | Very quiet, late quiet hours |

### Configuration

```go
type PresetConfig struct {
    Enabled       bool              `json:"enabled"`
    Presets       map[string]*Preset `json:"presets"`
    CurrentPreset string            `json:"current_preset"`
}

type Preset struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Config      *PresetConfigValues `json:"config"`
    Icon        string   `json:"icon,omitempty"` // emoji or icon name
}

type PresetConfigValues struct {
    GlobalEnabled bool              `json:"global_enabled"`
    Events        map[string]*Event `json:"events"`
    QuietHours    *QuietHours       `json:"quiet_hours,omitempty"`
    DefaultVolume float64           `json:"default_volume"`
}
```

### Commands

```bash
/ccbell:preset list                 # List presets
/ccbell:preset apply work           # Apply work preset
/ccbell:preset apply night          # Apply night preset
/ccbell:preset current              # Show current preset
/ccbell:preset create "Custom" --volume 0.5 --quiet 22:00-07:00
/ccbell:preset delete <name>        # Delete custom preset
/ccbell:preset export <name>        # Export preset
```

### Output

```
$ ccbell:preset list

=== Sound Event Presets ===

Current: Work

Built-in Presets:
  [1] Work
      Office settings with normal volume
      [Apply] [Details]

  [2] Home
      Lower volume, evening quiet hours
      [Apply] [Details]

  [3] Meeting
      Silent except high priority
      [Apply] [Details]

  [4] Focus
      All sounds disabled
      [Apply] [Details]

  [5] Night
      Very quiet, late quiet hours
      [Apply] [Details]

Custom Presets: 2
  [6] Custom 1
      [Apply] [Edit] [Export] [Delete]

[Configure] [Create] [Apply]
```

---

## Audio Player Compatibility

Presets don't play sounds:
- Configuration feature
- No player changes required

---

## Implementation

### Preset Manager

```go
type PresetManager struct {
    config   *PresetConfig
    cfg      *config.Config
}

func (m *PresetManager) Apply(presetID string) error {
    preset, ok := m.config.Presets[presetID]
    if !ok {
        return fmt.Errorf("preset not found: %s", presetID)
    }

    // Apply global settings
    m.cfg.Enabled = preset.Config.GlobalEnabled
    m.cfg.ActiveProfile = "default"

    // Apply event configs
    for eventType, eventCfg := range preset.Config.Events {
        m.cfg.Events[eventType] = eventCfg
    }

    // Apply quiet hours
    if preset.Config.QuietHours != nil {
        m.cfg.QuietHours = preset.Config.QuietHours
    }

    // Apply default volume
    if preset.Config.DefaultVolume > 0 {
        for _, event := range m.cfg.Events {
            if event.Volume == nil {
                event.Volume = ptrFloat(preset.Config.DefaultVolume)
            }
        }
    }

    m.config.CurrentPreset = presetID
    return m.save()
}

func (m *PresetManager) Create(name string, settings *PresetConfigValues) error {
    presetID := strings.ToLower(strings.ReplaceAll(name, " ", "_"))

    if _, exists := m.config.Presets[presetID]; exists {
        return fmt.Errorf("preset already exists: %s", name)
    }

    m.config.Presets[presetID] = &Preset{
        ID:          presetID,
        Name:        name,
        Description: fmt.Sprintf("Custom preset: %s", name),
        Config:      settings,
    }

    return m.save()
}

func (m *PresetManager) GetBuiltInPresets() []*Preset {
    return []*Preset{
        {
            ID:   "work",
            Name: "Work",
            Description: "Office settings with normal volume",
            Config: &PresetConfigValues{
                GlobalEnabled:  true,
                DefaultVolume:  0.5,
                QuietHours:     &QuietHours{Start: "", End: ""},
            },
        },
        {
            ID:   "home",
            Name: "Home",
            Description: "Lower volume, evening quiet hours",
            Config: &PresetConfigValues{
                GlobalEnabled:  true,
                DefaultVolume:  0.3,
                QuietHours:     &QuietHours{Start: "22:00", End: "07:00"},
            },
        },
        // More built-in presets...
    }
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
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Time-based logic

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
