# Feature: Success Sound

Custom sound for successful operations.

## Summary

Play a positive sound when operations complete successfully (config saved, sound installed, etc.).

## Motivation

- Audio confirmation of success
- Better user experience
- Distinguish successes from other events

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Success Events

| Operation | Current | Success Sound? |
|-----------|---------|----------------|
| Config saved | Silent | ✅ Play sound |
| Sound installed | Silent | ✅ Play sound |
| Profile switched | Silent | ✅ Play sound |
| Plugin validated | Silent | ✅ Play sound |

### Configuration

```json
{
  "success_sound": {
    "enabled": true,
    "sound": "bundled:success",
    "volume": 0.5,
    "play_on": {
      "config_saved": true,
      "sound_installed": true,
      "profile_switched": true,
      "validation_passed": true
    }
  }
}
```

### Implementation

```go
func runSuccessEvent(eventType string) error {
    err := runOperation(eventType)

    if err == nil {
        playSuccessSound(eventType)
    }

    return err
}

func playSuccessSound(operation string) {
    cfg, _, _ := config.Load(homeDir)

    if cfg.SuccessSound == nil || !cfg.SuccessSound.Enabled {
        return
    }

    if !cfg.SuccessSound.PlayOn[operation] {
        return
    }

    sound := cfg.SuccessSound.Sound
    player := audio.NewPlayer(pluginRoot)
    soundPath, _ := player.ResolveSoundPath(sound, "success")

    player.Play(soundPath, cfg.SuccessSound.Volume)
}
```

### Commands

```bash
/ccbell:success test           # Test success sound
/ccbell:success set bundled:success
/ccbell:success disable        # Disable success sounds
/ccbell:success list           # List success event types
```

### Integration Points

```go
// In configure command
func runConfigure() error {
    // ... save config ...

    playSuccessSound("config_saved")
    return nil
}

// In validate command
func runValidate() error {
    // ... validate ...

    playSuccessSound("validation_passed")
    return nil
}
```

### Output

```
$ /ccbell:configure
Configuration saved successfully
[Plays success sound]

$ ccbell validate
✓ Audio player found (mpv)
✓ Config valid
✓ All sounds present
Validation passed
[Plays success sound]
```

---

## Audio Player Compatibility

Success sounds use existing audio player:
- Same `player.Play()` method
- Same format support
- No player changes required

---

## Implementation

### Success Event Types

```go
var successEvents = map[string]bool{
    "config_saved":     true,
    "sound_installed":  true,
    "profile_switched": true,
    "validation_passed": true,
    "pack_installed":   true,
    "profile_created":  true,
}
```

### Config Extension

```go
type SuccessSoundConfig struct {
    Enabled  bool              `json:"enabled"`
    Sound    string            `json:"sound"`
    Volume   float64           `json:"volume"`
    PlayOn   map[string]bool   `json:"play_on"`
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Success config
- [Commands](https://github.com/mpolatcan/ccbell/blob/main/commands/) - Command integration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via afplay |
| Linux | ✅ Supported | Via mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
