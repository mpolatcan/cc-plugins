# Feature: Sound Dry Run

Test sound configurations without actual playback.

## Summary

Preview sound configuration changes before applying them.

## Motivation

- Test changes safely
- Verify configuration validity
- Preview sound selection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Dry Run Modes

| Mode | Description | Output |
|------|-------------|--------|
| Validate | Check config validity | Pass/Fail |
| Preview | Show what would play | Sound path |
| Simulate | Mock playback | Logs only |
| Compare | Compare old vs new | Diff output |

### Implementation

```go
type DryRunConfig struct {
    Mode        string  `json:"mode"`          // validate, preview, simulate
    Event       string  `json:"event"`         // specific event
    Sound       string  `json:"sound"`         // test sound
    Volume      float64 `json:"volume"`        // test volume
    Cooldown    int     `json:"cooldown"`      // test cooldown
    ShowPath    bool    `json:"show_path"`     // show resolved path
    ShowPlayer  bool    `json:"show_player"`   // show player command
}

type DryRunResult struct {
    Valid       bool     `json:"valid"`
    SoundPath   string   `json:"sound_path"`
    PlayerCmd   string   `json:"player_command"`
    Checks      []Check  `json:"checks"`
    Warnings    []string `json:"warnings"`
    Errors      []string `json:"errors"`
}

type Check struct {
    Name    string `json:"name"`
    Status  string `json:"status"` // pass, fail, warn
    Message string `json:"message"`
}
```

### Commands

```bash
/ccbell:dry-run                     # Dry run all events
/ccbell:dry-run --mode validate     # Validate configuration
/ccbell:dry-run --mode preview      # Preview what would play
/ccbell:dry-run --mode simulate     # Simulate playback
/ccbell:dry-run event stop          # Test specific event
/ccbell:dry-run sound bundled:stop  # Test sound
/ccbell:dry-run --show-path         # Show resolved path
/ccbell:dry-run --show-command      # Show player command
```

### Output

```
$ ccbell:dry-run event stop

=== Dry Run: stop ===

Sound: bundled:stop
Volume: 50%
Cooldown: 0s

Checks:
  [✓] Config valid
  [✓] Sound exists: ~/.local/share/ccbell/sounds/bundled/stop.aiff
  [✓] Format supported: AIFF
  [✓] Player available: afplay (macOS)

Would execute:
  afplay -v 0.50 ~/.local/share/ccbell/sounds/bundled/stop.aiff

Result: VALID
```

---

## Audio Player Compatibility

Dry run doesn't play sounds:
- Validation and preview only
- No player changes required
- Shows what would be executed

---

## Implementation

### Validation Checks

```go
func (d *DryRunManager) validateConfig(eventType string) []Check {
    checks := []Check{}

    // Check config exists
    if d.config == nil {
        checks = append(checks, Check{
            Name:    "config_exists",
            Status:  "fail",
            Message: "Configuration not loaded",
        })
        return checks
    }

    // Check event config
    eventCfg := d.config.GetEventConfig(eventType)
    if eventCfg == nil {
        checks = append(checks, Check{
            Name:    "event_config",
            Status:  "fail",
            Message: fmt.Sprintf("Event '%s' not configured", eventType),
        })
    } else {
        checks = append(checks, Check{
            Name:    "event_config",
            Status:  "pass",
            Message: "Event configured",
        })
    }

    // Check sound
    soundSpec := eventCfg.Sound
    player := audio.NewPlayer(d.pluginRoot)
    if path, err := player.ResolveSoundPath(soundSpec, eventType); err != nil {
        checks = append(checks, Check{
            Name:    "sound_exists",
            Status:  "fail",
            Message: err.Error(),
        })
    } else {
        checks = append(checks, Check{
            Name:    "sound_exists",
            Status:  "pass",
            Message: fmt.Sprintf("Sound at: %s", path),
        })
    }

    return checks
}
```

### Command Preview

```go
func (d *DryRunManager) getPlayerCommand(soundPath string, volume float64) string {
    platform := detectPlatform()

    switch platform {
    case PlatformMacOS:
        return fmt.Sprintf("afplay -v %.2f %s", volume, soundPath)
    case PlatformLinux:
        return fmt.Sprintf("mpv --volume=%d %s", int(volume*100), soundPath)
    default:
        return "unknown"
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

- [Player initialization](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L73-79) - Platform detection
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Path resolution
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config validation

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
