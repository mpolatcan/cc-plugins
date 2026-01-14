# Feature: Batch Configuration

Configure multiple events simultaneously.

## Summary

Apply configuration changes to multiple events at once, reducing repetitive configuration steps.

## Motivation

- Change volume for all events at once
- Enable/disable multiple events together
- Bulk apply sound pack to all events

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Batch Operations

The current `internal/config/config.go` handles individual event configuration.

**Key Finding**: Batch operations can modify multiple events in a single pass.

### Batch Commands

```bash
# Set volume for all events
/ccbell:configure batch volume 0.6

# Enable all events
/ccbell:configure batch enable

# Disable all non-critical events
/ccbell:configure batch disable idle_prompt

# Set same sound for all events
/ccbell:configure batch sound bundled:stop

# Apply profile to specific events
/ccbell:configure batch profile work --events stop,permission_prompt

# Reset to defaults
/ccbell:configure batch reset
```

### Implementation

```go
func batchConfigure(cfg *config.Config, operation string, args ...string) error {
    switch operation {
    case "volume":
        vol, _ := strconv.ParseFloat(args[0], 64)
        for _, event := range config.ValidEvents {
            if cfg.Events[event] == nil {
                cfg.Events[event] = &config.Event{}
            }
            cfg.Events[event].Volume = &vol
        }

    case "enable":
        for event := range config.ValidEvents {
            if cfg.Events[event] == nil {
                cfg.Events[event] = &config.Event{}
            }
            enabled := true
            cfg.Events[event].Enabled = &enabled
        }

    case "disable":
        events := parseEvents(args)
        for _, event := range events {
            if cfg.Events[event] == nil {
                cfg.Events[event] = &config.Event{}
            }
            enabled := false
            cfg.Events[event].Enabled = &enabled
        }

    case "sound":
        sound := args[0]
        for event := range config.ValidEvents {
            if cfg.Events[event] == nil {
                cfg.Events[event] = &config.Event{}
            }
            cfg.Events[event].Sound = sound
        }
    }

    return nil
}
```

### Interactive Mode

```
$ /ccbell:configure batch

=== Batch Configuration ===

Select operation:
  [1] Set volume for all events
  [2] Enable all events
  [3] Disable specific events
  [4] Set same sound for all
  [5] Apply profile to events
  [6] Reset events to defaults

Select [1-6]: 1

Enter volume (0.0-1.0): 0.6

Applying volume 0.6 to all events...
  stop: ✓
  permission_prompt: ✓
  idle_prompt: ✓
  subagent: ✓

Save changes? [y/n]: y
```

---

## Audio Player Compatibility

Batch configuration doesn't interact with audio playback:
- Purely config modification
- No player changes required
- Changes take effect on next event

---

## Implementation

### Config Merge

```go
func batchApply(cfg *Config, batch BatchOperation) error {
    for _, event := range batch.Events {
        if err := applyEventConfig(cfg.Events[event], batch.Changes); err != nil {
            return fmt.Errorf("event %s: %w", event, err)
        }
    }
    return nil
}
```

### Safety Checks

```go
// Preview before applying
func batchPreview(cfg *Config, batch BatchOperation) {
    log.Printf("Would modify %d events:", len(batch.Events))
    for _, event := range batch.Events {
        log.Printf("  %s: %+v", event, batch.Changes)
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config schema
- [Config merge](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L206-L220) - Merge pattern
- [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) - Event list

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Config only |
| Linux | ✅ Supported | Config only |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
