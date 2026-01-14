# Feature: Sound Templates

Create reusable sound templates.

## Summary

Define templates for consistent sound configuration across events.

## Motivation

- Standardize configurations
- Quick setup for new events
- Configuration inheritance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Template Structure

```go
type SoundTemplate struct {
    Name        string            `json:"name"`
    Description string            `json:"description"`
    Volume      float64           `json:"volume"`
    Cooldown    int               `json:"cooldown"` // seconds
    Effects     []string          `json:"effects"`  // fade, reverb, etc.
    QuietHours  QuietHoursConfig  `json:"quiet_hours"`
    CreatedAt   time.Time         `json:"created_at"`
}

type TemplateConfig struct {
    Templates   map[string]*SoundTemplate `json:"templates"`
    DefaultTemplate string                `json:"default_template"`
}
```

### Default Templates

| Template | Volume | Cooldown | Use Case |
|----------|--------|----------|----------|
| Subtle | 0.3 | 5s | Office environments |
| Normal | 0.5 | 2s | Default notifications |
| Loud | 0.8 | 0s | High-priority alerts |
| Silent | 0.0 | 0s | No sound (placeholder) |

### Commands

```bash
/ccbell:template list                   # List templates
/ccbell:template create mytemplate      # Create template
/ccbell:template apply subtle           # Apply template
/ccbell:template apply subtle stop      # Apply to event
/ccbell:template edit mytemplate        # Edit template
/ccbell:template delete mytemplate      # Remove template
/ccbell:template set-default normal     # Set default
/ccbell:template export mytemplate      # Export template
```

### Output

```
$ ccbell:template list

=== Sound Templates ===

[1] Subtle (Default)
    Volume: 30%
    Cooldown: 5s
    Effects: fade-in(100ms)
    Events: 2 configured
    [Apply] [Edit] [Export] [Delete]

[2] Normal
    Volume: 50%
    Cooldown: 2s
    Effects: -
    Events: 1 configured
    [Apply] [Edit] [Export] [Delete]

[3] Loud
    Volume: 80%
    Cooldown: 0s
    Effects: -
    Events: 1 configured
    [Apply] [Edit] [Export] [Delete]

[Create New] [Set Default]
```

---

## Audio Player Compatibility

Templates don't play sounds:
- Configuration feature
- No player changes required

---

## Implementation

### Template Creation

```go
func (t *TemplateManager) Create(name string, config *SoundConfig) (*SoundTemplate, error) {
    template := &SoundTemplate{
        Name:        name,
        Description: fmt.Sprintf("Template created from current config"),
        Volume:      derefFloat(config.Volume, 0.5),
        Cooldown:    derefInt(config.Cooldown, 0),
        CreatedAt:   time.Now(),
    }

    t.templates[name] = template
    return template, t.saveTemplates()
}
```

### Template Application

```go
func (t *TemplateManager) Apply(templateName string, eventType string) error {
    template, ok := t.templates[templateName]
    if !ok {
        return fmt.Errorf("template not found: %s", templateName)
    }

    eventCfg := t.config.GetEventConfig(eventType)
    eventCfg.Volume = &template.Volume
    eventCfg.Cooldown = &template.Cooldown

    return t.config.Save()
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Template inheritance
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event configuration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
