# Feature: Startup Sound

Play a sound when Claude Code starts.

## Summary

Play a notification sound when Claude Code plugin loads.

## Motivation

- Confirm plugin loaded successfully
- Audio feedback on startup
- User knows ccbell is active

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Hook Integration

The current `hooks/hooks.json` already defines when ccbell runs.

**Key Finding**: Can add startup sound via hook or script.

### Hook Configuration

```json
{
  "hooks": [
    {
      "events": ["Startup"],
      "matcher": "*",
      "type": "command",
      "command": "ccbell startup"
    }
  ]
}
```

### Main Entry

```go
func main() {
    // Existing event handling
    eventType := flag.Arg(0)

    if eventType == "startup" {
        return runStartupSound()
    }

    // ... existing logic
}

func runStartupSound() error {
    cfg, _, err := config.Load(homeDir)
    if err != nil {
        return err
    }

    if cfg.StartupSound == nil || !cfg.StartupSound.Enabled {
        return nil
    }

    eventCfg := cfg.GetEventConfig("stop") // Or use startup-specific config
    soundPath, _ := player.ResolveSoundPath(eventCfg.Sound, "stop")

    log.Info("Playing startup sound")
    return player.Play(soundPath, *eventCfg.Volume)
}
```

### Configuration

```json
{
  "startup_sound": {
    "enabled": true,
    "sound": "bundled:subagent",
    "volume": 0.5,
    "delay_ms": 500
  }
}
```

### Commands

```bash
/ccbell:startup test         # Test startup sound
/ccbell:startup disable      # Disable startup sound
/ccbell:startup set bundled:stop
```

### Output

```
$ ccbell startup
ccbell v0.2.30 - Playing startup sound
[Plays sound]
Startup complete
```

---

## Audio Player Compatibility

Startup sound uses existing audio player:
- Same `player.Play()` method
- Same format support
- No player changes required

---

## Implementation

### Config Extension

```go
type StartupConfig struct {
    Enabled  bool    `json:"enabled"`
    Sound    string  `json:"sound"`
    Volume   float64 `json:"volume"`
    DelayMs  int     `json:"delay_ms"`
}
```

### Startup Flow

```go
func runStartupSound() error {
    cfg, _, err := config.Load(homeDir)
    if err != nil {
        return err
    }

    if cfg.StartupSound == nil || !cfg.StartupSound.Enabled {
        return nil
    }

    if cfg.StartupSound.DelayMs > 0 {
        time.Sleep(time.Duration(cfg.StartupSound.DelayMs) * time.Millisecond)
    }

    player := audio.NewPlayer(pluginRoot)
    soundPath, _ := player.ResolveSoundPath(cfg.StartupSound.Sound, "startup")

    return player.Play(soundPath, cfg.StartupSound.Volume)
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

- [Hooks configuration](https://github.com/mpolatcan/ccbell/blob/main/hooks/hooks.json) - Hook integration
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config extension

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via afplay |
| Linux | ✅ Supported | Via mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
