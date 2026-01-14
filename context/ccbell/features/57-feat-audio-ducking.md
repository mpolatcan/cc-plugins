# Feature: Audio Ducking

Lower other audio when playing notifications.

## Summary

Temporarily reduce volume of other applications when playing notification sounds.

## Motivation

- Notifications are more audible
- No need to manually lower music/other audio
- Better notification clarity

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Ducking Methods

| Platform | Method | Native Support | Feasibility |
|----------|--------|----------------|-------------|
| macOS | `osascript` | Yes | ✅ Easy |
| Linux (PulseAudio) | `pacmd` | Yes | ✅ Easy |
| Linux (ALSA) | `amixer` | Yes | ⚠️ Moderate |
| Both | FFmpeg filter | Yes | ✅ Cross-platform |

### macOS Implementation (AppleScript)

```bash
# Get current output volume
osascript -e 'output volume of (get volume settings)'

# Set volume (for ducking)
osascript -e 'set volume output volume 30'
```

### Linux Implementation (PulseAudio)

```bash
# Get current sink input volume
pacmd list-sink-inputs | grep index

# Set volume for specific application
pacmd move-sink-input 1 0  # Move to different sink
pactl set-sink-input-volume 1 30%
```

### FFmpeg Ducking Filter

```bash
# Side-chain compression
ffmpeg -i main.aiff -i music.mp3 -filter_complex "[0:a][1:a]sidechaincompress=threshold=0.5:ratio=4[out]" -map "[out]" output.aiff
```

### Configuration

```json
{
  "ducking": {
    "enabled": true,
    "ducking_volume": 0.3,
    "restore_volume": 1.0,
    "attack_ms": 10,
    "release_ms": 100
  }
}
```

### Implementation

```go
type Ducker struct {
    originalVolume float64
    duckingVolume  float64
    attackTime     time.Duration
    releaseTime    time.Duration
}

func (d *Ducker) Start() error {
    // Store original volume
    d.originalVolume = d.getSystemVolume()

    // Lower volume
    return d.setSystemVolume(d.duckingVolume)
}

func (d *Ducker) Stop() error {
    // Restore original volume with fade
    time.Sleep(d.attackTime)

    return d.setSystemVolume(d.originalVolume)
}
```

---

## Audio Player Compatibility

Audio ducking affects system volume:
- Works with all audio players
- Doesn't modify player code
- Uses OS-level volume control

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `osascript` | Native (macOS) | Free | Built-in |
| `pacmd` | Native (PulseAudio) | Free | Built-in |
| `pactl` | Native (PulseAudio) | Free | Built-in |

---

## References

### Research Sources

- [macOS volume AppleScript](https://developer.apple.com/library/archive/technotes/tn2007/tn2007.html)
- [PulseAudio ducking](https://freedesktop.org/software/pulseaudio/pulseaudio/doxygen/)
- [FFmpeg sidechaincompress](https://ffmpeg.org/ffmpeg-filters.html#sidechaincompress)

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback integration
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91) - Platform-specific code

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via AppleScript |
| Linux | ⚠️ Partial | PulseAudio supported |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
