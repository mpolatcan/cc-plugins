# Feature: Output Device Selection

Choose which audio output device to use for notifications.

## Summary

Allow users to select a specific audio output device (e.g., headphones, speakers, HDMI) for ccbell notifications instead of using the system default.

## Motivation

- Multi-monitor setups with different audio outputs
- Use headphones for notifications while speakers are for music
- Route notifications to a specific device for clarity

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Current Audio Player Analysis

The current `internal/audio/player.go` uses:
- **macOS**: `afplay` - Uses system default device only
- **Linux**: `mpv`, `paplay`, `aplay`, `ffplay` - Variable device support

**Key Finding**: Native players have limited device selection capabilities.

### Platform Options

| Platform | Tool | Device Support | Feasibility |
|----------|------|----------------|-------------|
| macOS | `afplay` | System default only | ⚠️ Limited |
| macOS | `sox` | Full device listing | ✅ Requires install |
| Linux (PulseAudio) | `paplay` | Device names | ✅ Via `pactl` |
| Linux (ALSA) | `aplay` | Device indices | ⚠️ Complex |
| Linux | `mpv` | `--audio-device` flag | ✅ Cross-distro |

### macOS Implementation

```bash
# List audio devices (requires blackhole or third-party)
System Preferences > Sound > Output

# afplay uses system default - no device selection possible
```

For full device selection on macOS, use SoX:
```bash
# Install: brew install sox
play -q -d coreaudio "Built-in Output" sound.aiff
```

### Linux Implementation (PulseAudio)

```bash
# List available sinks
pactl list short sinks

# Play to specific sink
paplay --device=sink_name sound.aiff

# mpv with audio device
mpv --audio-device=pulse/sink_name sound.aiff
```

### Configuration

```json
{
  "output": {
    "device": "auto",
    "device_name": " Speakers",
    "fallback_to_default": true
  }
}
```

### Commands

```bash
/ccbell:output list     # List available devices
/ccbell:output set "Headphones"  # Set output device
/ccbell:output reset    # Reset to system default
/ccbell:output test     # Test current output
```

---

## Audio Player Compatibility

### macOS

| Player | Device Selection | Notes |
|--------|------------------|-------|
| afplay | ❌ No | System default only |
| sox | ✅ Yes | Requires `brew install sox` |
| ffplay | ⚠️ Limited | Via CoreAudio API |

### Linux

| Player | Device Selection | Notes |
|--------|------------------|-------|
| mpv | ✅ Yes | `--audio-device` flag |
| paplay | ✅ Yes | Via PulseAudio |
| aplay | ⚠️ Limited | Device index only |
| ffplay | ✅ Yes | Via ALSA/PulseAudio |

---

## Implementation

### Device Discovery

```go
func listAudioDevices() ([]AudioDevice, error) {
    switch detectPlatform() {
    case PlatformMacOS:
        return listMacOSDevices()
    case PlatformLinux:
        return listLinuxDevices()
    }
}

func listLinuxDevices() ([]AudioDevice, error) {
    // Use pactl to list PulseAudio sinks
    cmd := exec.Command("pactl", "list", "short", "sinks")
    // Parse output for device names
}
```

### Player Integration

```go
func (p *Player) PlayWithDevice(soundPath string, volume float64, device string) error {
    switch p.platform {
    case PlatformMacOS:
        // Use sox if installed, else fallback to afplay
        return p.playMacOSWithDevice(soundPath, volume, device)
    case PlatformLinux:
        return p.playLinuxWithDevice(soundPath, volume, device)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pactl | Native (Linux) | Free | PulseAudio command-line |
| sox | Optional (macOS) | Free | `brew install sox` |

---

## References

### Research Sources

- [PulseAudio pactl](https://freedesktop.org/software/pulseaudio/pulseaudio/doxygen/ man_pactl.html)
- [SoX audio tool](http://sox.sourceforge.net/)
- [mpv audio-device](https://mpv.io/manual/stable/#options-audio-device)

### ccbell Implementation Research

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Shows players used (afplay, mpv, paplay, aplay, ffplay)
- [Player args](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L48-L62) - Shows argument patterns to extend
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91) - Platform detection logic

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ⚠️ Partial | Requires sox for device selection |
| Linux | ✅ Full | Via pactl/mpv audio-device |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
