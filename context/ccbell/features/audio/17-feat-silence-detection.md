# Feature: Silence Detection Before Playback

Skip playing sounds if the environment is already noisy.

## Summary

Monitor ambient noise levels and skip notification sounds when the environment is already loud, preventing audio clutter and annoyance.

## Motivation

- Avoid adding to existing noise in loud environments
- More intelligent notifications that respect context
- Reduce notification fatigue in busy settings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | High |
| **Estimated Effort** | 7-10 days |

---

## Technical Feasibility

### Current Architecture Analysis

The current `cmd/ccbell/main.go` is a short-lived process that:
1. Reads config
2. Checks conditions (quiet hours, cooldown)
3. Plays sound
4. Exits

**Key Finding**: Silence detection requires a persistent monitoring process or external tool.

### Audio Level Detection

| Platform | Tool | Native Support | Feasibility |
|----------|------|----------------|-------------|
| macOS | `afinfo` + sox | Yes | ✅ Easy |
| Linux | `ffmpeg` | Yes | ✅ Easy |
| Both | `sox` | Yes | ✅ Cross-platform |

### Implementation with FFmpeg

```bash
# Get current input level (microphone)
ffmpeg -f avfoundation -i ":0" -af "volumedetect" -f null /dev/null

# Or with pulse audio
ffmpeg -f pulse -i default -af "volumedetect" -f null /dev/null
```

### Threshold Configuration

```go
type SilenceConfig struct {
    Enabled      bool    `json:"enabled"`
    ThresholdDB  float64 `json:"threshold_db"`  // -50.0 to 0.0
    CheckSeconds int     `json:"check_seconds"` // How long to sample
    Device       string  `json:"device"`        // Input device
}
```

### Commands

```bash
/ccbell:silence status           # Current ambient level
/ccbell:silence calibrate        # Set threshold based on environment
/ccbell:silence set -40db        # Set manual threshold
/ccbell:silence disable          # Disable silence detection
```

---

## Audio Player Compatibility

Silence detection runs independently of audio playback:
- Uses microphone/input device to detect ambient noise
- Does not interact with afplay/mpv/paplay/aplay/ffplay
- Decision to play/not play is made before calling player

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Already supported player |
| sox | Optional | Free | Alternative for level detection |
| microphone | Hardware | Free | Built-in on most systems |

---

## Implementation

### Persistent Monitor

```go
type SilenceMonitor struct {
    thresholdDB  float64
    checkSeconds int
    device       string
    running      bool
}

func (m *SilenceMonitor) Start() error {
    m.running = true
    go m.monitorLoop()
    return nil
}

func (m *SilenceMonitor) IsNoisy() (bool, error) {
    // Sample audio input for check_seconds
    // Return true if ambient level > thresholdDB
}
```

### Integration Point

```go
// In main.go, before playing sound
if cfg.SilenceDetection != nil && cfg.SilenceDetection.Enabled {
    noisy, err := silenceMonitor.IsNoisy()
    if err != nil {
        log.Warn("Silence detection failed: %v", err)
    } else if noisy {
        log.Debug("Skipping notification - environment is noisy")
        return nil
    }
}
```

---

## References

### Research Sources

- [FFmpeg volumedetect filter](https://ffmpeg.org/ffmpeg-filters.html#volumedetect)
- [SoX input detection](http://sox.sourceforge.net/sox.html)
- [PulseAudio monitoring](https://freedesktop.org/software/pulseaudio/pulseaudio/doxygen/)

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point for silence check
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For adding silence config
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - For persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg/avfoundation |
| Linux | ✅ Supported | Via ffmpeg/pulseaudio |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
