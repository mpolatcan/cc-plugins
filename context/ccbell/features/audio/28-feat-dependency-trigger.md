# Feature: Dependency Trigger

Trigger notifications based on external script execution.

## Summary

Allow external scripts to trigger ccbell notifications via a simple interface, enabling integration with non-Claude tools.

## Motivation

- Integrate with CI/CD pipelines
- Trigger notifications from shell scripts
- Cross-tool notification hub

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Trigger Interface

The current `cmd/ccbell/main.go` already accepts event type as argument:
```bash
ccbell stop
ccbell permission_prompt
ccbell idle_prompt
ccbell subagent
```

**Key Finding**: External scripts can already trigger notifications.

### Enhanced Trigger Options

```bash
# Basic trigger
ccbell trigger stop

# With custom message
ccbell trigger stop --message "Build complete"

# With custom volume
ccbell trigger stop --volume 0.8

# From custom sound
ccbell trigger stop --sound /path/to/sound.aiff

# With profile
ccbell trigger stop --profile alerts
```

### Script Integration Examples

```bash
#!/bin/bash
# CI/CD pipeline notification
if [ "$BUILD_STATUS" = "success" ]; then
    ccbell trigger stop --message "Build $BUILD_NUMBER succeeded"
else
    ccbell trigger stop --message "Build $BUILD_NUMBER failed"
fi

# Cron job notification
0 9 * * 1-5 ccbell trigger idle_prompt --message "Weekly reminder"
```

### Implementation

```go
func main() {
    triggerCmd := flag.Bool("trigger", false, "Trigger notification (for external scripts)")
    // ... existing flags ...

    if *triggerCmd {
        // Trigger mode - simplified flow
        log.Debug("External trigger: %s", eventType)
    }
}
```

### Security Considerations

```go
// Validate trigger source
func validateTrigger() error {
    // Optional: verify from expected IP/host
    // Optional: require API key
}
```

---

## Audio Player Compatibility

Dependency trigger uses existing audio player:
- Same playback mechanism as normal events
- Same format support
- No player changes required

---

## Implementation

### Flag Addition

```go
var triggerMode = flag.Bool("trigger", false, "Run in trigger mode for external scripts")
var messageFlag = flag.String("message", "", "Custom message for trigger")
var triggerVolume = flag.Float64("volume", -1, "Volume for this trigger")
var triggerProfile = flag.String("profile", "", "Profile for this trigger")

// In trigger mode, skip normal validation
if *triggerMode {
    return runTrigger(eventType, *messageFlag, *triggerVolume, *triggerProfile)
}
```

### Trigger Function

```go
func runTrigger(eventType, message string, volume float64, profile string) error {
    // Load minimal config
    cfg, _, err := config.Load(homeDir)
    if err != nil {
        return err
    }

    // Apply overrides
    if profile != "" {
        cfg.ActiveProfile = profile
    }

    // Resolve sound and play
    eventCfg := cfg.GetEventConfig(eventType)
    soundPath, _ := player.ResolveSoundPath(eventCfg.Sound, eventType)

    effectiveVolume := *eventCfg.Volume
    if volume >= 0 {
        effectiveVolume = volume
    }

    return player.Play(soundPath, effectiveVolume)
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

- [Main.go entry point](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Trigger integration point
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - For trigger config
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - For playback

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | CLI interface |
| Linux | ✅ Supported | CLI interface |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
