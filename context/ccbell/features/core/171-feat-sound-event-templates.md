# Feature: Sound Event Templates

Reusable configuration templates for events.

## Summary

Create and apply templates to quickly configure events with pre-defined settings.

## Motivation

- Quick configuration
- Consistency across events
- Preset management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Template Types

| Type | Description | Example |
|------|-------------|---------|
| Built-in | Default templates | "quiet", "loud", "minimal" |
| Custom | User-defined templates | "meeting", "focus" |
| Imported | External templates | Shared configs |

### Configuration

```go
type TemplateConfig struct {
    Enabled     bool              `json:"enabled"`
    Templates   map[string]*EventTemplate `json:"templates"`
}

type EventTemplate struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Sound       string   `json:"sound,omitempty"`
    Volume      *float64 `json:"volume,omitempty"`
    Cooldown    *int     `json:"cooldown,omitempty"`
    QuietHours  *QuietHours `json:"quiet_hours,omitempty"`
    Tags        []string `json:"tags"` // For discovery
    BuiltIn     bool     `json:"built_in"` // System template
}
```

### Commands

```bash
/ccbell:template list               # List templates
/ccbell:template create "Focus" --sound bundled:stop --volume 0.3 --cooldown 60
/ccbell:template apply <template> <event>  # Apply template to event
/ccbell:template apply-all <template>       # Apply to all events
/ccbell:template export <template>          # Export template
/ccbell:template import <path>              # Import template
/ccbell:template delete <id>                # Delete custom template
/ccbell:template duplicate <id> <new_name>  # Copy template
```

### Output

```
$ ccbell:template list

=== Sound Event Templates ===

Built-in: 3 | Custom: 2

[Built-in] Quiet
    Description: Minimal notifications
    Volume: 0.3
    Cooldown: 60s
    [Apply] [Duplicate]

[Built-in] Loud
    Description: Maximum attention
    Volume: 1.0
    Cooldown: 0s
    [Apply] [Duplicate]

[Built-in] Minimal
    Description: Essential only
    Volume: 0.5
    Cooldown: 30s
    [Apply] [Duplicate]

[Custom] Meeting
    Description: For meetings
    Volume: 0.4
    Cooldown: 120s
    Tags: work, meeting
    [Apply] [Edit] [Export] [Delete]

[Custom] Focus
    Description: Deep work
    Volume: 0.3
    Cooldown: 60s
    Tags: work, focus
    [Apply] [Edit] [Export] [Delete]

[Configure] [Create] [Import]
```

---

## Audio Player Compatibility

Templates don't play sounds:
- Configuration feature
- No player changes required

---

## Implementation

### Template Application

```go
type TemplateManager struct {
    config   *TemplateConfig
}

func (m *TemplateManager) Apply(templateID, eventType string, cfg *config.Config) error {
    tmpl, ok := m.config.Templates[templateID]
    if !ok {
        return fmt.Errorf("template not found: %s", templateID)
    }

    eventCfg, exists := cfg.Events[eventType]
    if !exists {
        eventCfg = &config.Event{}
        cfg.Events[eventType] = eventCfg
    }

    // Apply template values
    if tmpl.Sound != "" {
        eventCfg.Sound = tmpl.Sound
    }
    if tmpl.Volume != nil {
        eventCfg.Volume = tmpl.Volume
    }
    if tmpl.Cooldown != nil {
        eventCfg.Cooldown = tmpl.Cooldown
    }

    return nil
}

func (m *TemplateManager) ApplyAll(templateID string, cfg *config.Config) error {
    for eventType := range config.ValidEvents {
        if err := m.Apply(templateID, eventType, cfg); err != nil {
            return fmt.Errorf("failed to apply to %s: %w", eventType, err)
        }
    }
    return nil
}

func (m *TemplateManager) FindByTag(tag string) []*EventTemplate {
    var results []*EventTemplate
    for _, tmpl := range m.config.Templates {
        if contains(tmpl.Tags, tag) {
            results = append(results, tmpl)
        }
    }
    return results
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
- [Profiles](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Similar preset concept

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
