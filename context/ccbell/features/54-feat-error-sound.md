# Feature: Error Sound

Custom sound for error conditions.

## Summary

Play a distinct sound when ccbell encounters errors (missing audio player, invalid config, etc.).

## Motivation

- Audible feedback on failures
- Distinguish errors from normal notifications
- Debug configuration issues

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Error Conditions

| Error | Current Behavior | Error Sound? |
|-------|------------------|--------------|
| No audio player | Log error | ✅ Play sound |
| Invalid config | Log error | ✅ Play sound |
| Missing sound file | Log error | ✅ Play sound |
| Quiet hours | Silent skip | ❌ Silent |
| Cooldown | Silent skip | ❌ Silent |

### Implementation

```go
func runWithErrorSound(eventType string) error {
    err := runEvent(eventType)

    if err != nil && shouldPlayErrorSound(err) {
        log.Warn("Error occurred: %v, playing error sound", err)
        playErrorSound()
    }

    return err
}

func shouldPlayErrorSound(err error) bool {
    switch err.(type) {
    case *NoAudioPlayerError:
        return true
    case *SoundFileNotFoundError:
        return true
    case *ConfigValidationError:
        return true
    default:
        return false
    }
}
```

### Error Sound Types

```go
var errorSoundMap = map[string]string{
    "no_player":    "bundled:error-no-player",
    "missing_file": "bundled:error-missing",
    "config_error": "bundled:error-config",
    "generic":      "bundled:error-generic",
}
```

### Configuration

```json
{
  "error_sound": {
    "enabled": true,
    "sound": "bundled:error",
    "volume": 0.7,
    "play_on": {
      "no_audio_player": true,
      "missing_sound_file": true,
      "config_error": true
    }
  }
}
```

### Commands

```bash
/ccbell:error test           # Test error sound
/ccbell:error set bundled:error
/ccbell:error disable        # Disable error sounds
/ccbell:error list           # List error types
```

### Output

```
$ ccbell stop
Error: no audio player found
[Plays error sound]
```

---

## Audio Player Compatibility

Error sounds use existing audio player:
- Same `player.Play()` method
- May fail if no audio player available
- No player changes required

---

## Implementation

### Error Types

```go
type CCBellError interface {
    error
    ErrorType() string
}

type NoAudioPlayerError struct {
    Message string
}

func (e *NoAudioPlayerError) Error() string {
    return e.Message
}

func (e *NoAudioPlayerError) ErrorType() string {
    return "no_player"
}
```

### Error Sound Playback

```go
func playErrorSound(err CCBellError) error {
    cfg, _, _ := config.Load(homeDir)

    if cfg.ErrorSound == nil || !cfg.ErrorSound.Enabled {
        return nil
    }

    errorType := err.ErrorType()
    if !cfg.ErrorSound.PlayOn[errorType] {
        return nil
    }

    sound := cfg.ErrorSound.Sound
    player := audio.NewPlayer(pluginRoot)
    soundPath, _ := player.ResolveSoundPath(sound, "error")

    return player.Play(soundPath, cfg.ErrorSound.Volume)
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
- [Error handling](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Main error handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Error config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via afplay |
| Linux | ✅ Supported | Via mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
