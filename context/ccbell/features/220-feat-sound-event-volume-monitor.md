# Feature: Sound Event Volume Monitor

Play sounds for system volume changes.

## Summary

Monitor system volume changes, detecting mute toggles, volume adjustments, and output device switches, playing sounds for volume events.

## Motivation

- Volume change feedback
- Mute toggle confirmation
- Output device switching
- Volume limit alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Volume Events

| Event | Description | Example |
|-------|-------------|---------|
| Volume Up | Volume increased | Pressed F12 |
| Volume Down | Volume decreased | Pressed F11 |
| Mute On | Sound muted | Pressed F10 |
| Mute Off | Sound unmuted | Pressed F10 |
| Output Changed | Audio device switched | Headphones plugged |
| Volume Max | Maximum volume reached | At 100% |

### Configuration

```go
type VolumeMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    MuteSounds      bool              `json:"mute_sounds"`
    VolumeSounds    bool              `json:"volume_sounds"`
    DeviceSounds    bool              `json:"device_sounds"`
    MaxVolumeAlert  float64           `json:"max_volume_alert"` // 100 default
    Sounds          map[string]string `json:"sounds"`
}

type VolumeEvent struct {
    Volume     float64 // 0.0 - 1.0
    Muted      bool
    Device     string
    Delta      float64 // Change amount
}
```

### Commands

```bash
/ccbell:volume status             # Show volume status
/ccbell:volume mute on            # Enable mute sounds
/ccbell:volume device on          # Enable device change sounds
/ccbell:volume sound up <sound>
/ccbell:volume sound down <sound>
/ccbell:volume sound mute <sound>
/ccbell:volume test               # Test volume sounds
```

### Output

```
$ ccbell:volume status

=== Sound Event Volume Monitor ===

Status: Enabled
Mute Sounds: Yes
Volume Sounds: Yes
Device Sounds: Yes

Current Volume:
  Level: 65%
  Status: Unmuted
  Device: Built-in Speakers

Device History:
  [1] Built-in Speakers (Current)
  [2] AirPods Pro (Disconnected 1 hour ago)
  [3] USB Headset (Disconnected 3 hours ago)

Sound Settings:
  Volume Up: bundled:stop
  Volume Down: bundled:stop
  Mute On: bundled:stop
  Mute Off: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Volume monitoring doesn't play sounds directly:
- Monitoring feature using system audio APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Volume Monitor

```go
type VolumeMonitor struct {
    config       *VolumeMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastVolume   float64
    lastMuted    bool
    lastDevice   string
}

func (m *VolumeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastVolume = m.getCurrentVolume()
    m.lastMuted = m.isMuted()
    m.lastDevice = m.getCurrentDevice()
    go m.monitor()
}

func (m *VolumeMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkVolume()
        case <-m.stopCh:
            return
        }
    }
}

func (m *VolumeMonitor) checkVolume() {
    currentVolume := m.getCurrentVolume()
    currentMuted := m.isMuted()
    currentDevice := m.getCurrentDevice()

    delta := currentVolume - m.lastVolume

    // Check volume up
    if delta > 0.05 && m.config.VolumeSounds {
        m.onVolumeUp(delta)
    }

    // Check volume down
    if delta < -0.05 && m.config.VolumeSounds {
        m.onVolumeDown(-delta)
    }

    // Check mute toggle
    if currentMuted != m.lastMuted && m.config.MuteSounds {
        if currentMuted {
            m.onMuteOn()
        } else {
            m.onMuteOff()
        }
    }

    // Check max volume
    if currentVolume >= m.config.MaxVolumeAlert && m.lastVolume < m.config.MaxVolumeAlert {
        m.onMaxVolume()
    }

    // Check device change
    if currentDevice != m.lastDevice && m.config.DeviceSounds {
        m.onDeviceChanged(currentDevice)
    }

    m.lastVolume = currentVolume
    m.lastMuted = currentMuted
    m.lastDevice = currentDevice
}

func (m *VolumeMonitor) getCurrentVolume() float64 {
    if runtime.GOOS == "darwin" {
        return m.getMacOSVolume()
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxVolume()
    }

    return 0
}

func (m *VolumeMonitor) getMacOSVolume() float64 {
    // macOS: osascript for volume
    cmd := exec.Command("osascript", "-e", "output volume of (get volume settings)")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    vol, _ := strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
    return vol / 100
}

func (m *VolumeMonitor) getLinuxVolume() float64 {
    // Linux: amixer or pactl
    cmd := exec.Command("amixer", "sget", "Master")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    // Parse: "[65%]"
    match := regexp.MustCompile(`\[(\d+)%\]`).FindStringSubmatch(string(output))
    if match != nil {
        vol, _ := strconv.ParseFloat(match[1], 64)
        return vol / 100
    }

    return 0
}

func (m *VolumeMonitor) isMuted() bool {
    if runtime.GOOS == "darwin" {
        return m.isMacOSMuted()
    }

    if runtime.GOOS == "linux" {
        return m.isLinuxMuted()
    }

    return false
}

func (m *VolumeMonitor) isMacOSMuted() bool {
    cmd := exec.Command("osascript", "-e", "output muted of (get volume settings)")
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.TrimSpace(string(output)) == "true"
}

func (m *VolumeMonitor) isLinuxMuted() bool {
    cmd := exec.Command("amixer", "sget", "Master")
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.Contains(string(output), "[off]")
}

func (m *VolumeMonitor) getCurrentDevice() string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSDevice()
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxDevice()
    }

    return ""
}

func (m *VolumeMonitor) getMacOSDevice() string {
    cmd := exec.Command("system_profiler", "SPAudioDataType")
    output, err := cmd.Output()
    if err != nil {
        return ""
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Output:") {
            return strings.TrimSpace(strings.TrimPrefix(line, "Output:"))
        }
    }

    return "Built-in Speakers"
}

func (m *VolumeMonitor) getLinuxDevice() string {
    cmd := exec.Command("pactl", "get-default-sink")
    output, err := cmd.Output()
    if err != nil {
        return "default"
    }

    return strings.TrimSpace(string(output))
}

func (m *VolumeMonitor) onVolumeUp(delta float64) {
    sound := m.config.Sounds["up"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *VolumeMonitor) onVolumeDown(delta float64) {
    sound := m.config.Sounds["down"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *VolumeMonitor) onMuteOn() {
    sound := m.config.Sounds["mute_on"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *VolumeMonitor) onMuteOff() {
    sound := m.config.Sounds["mute_off"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *VolumeMonitor) onMaxVolume() {
    sound := m.config.Sounds["max"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *VolumeMonitor) onDeviceChanged(device string) {
    sound := m.config.Sounds["device_changed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| osascript | System Tool | Free | macOS audio control |
| amixer | ALSA | Free | Linux mixer control |
| pactl | PulseAudio | Free | Audio device control |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses osascript |
| Linux | Supported | Uses amixer/pactl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
