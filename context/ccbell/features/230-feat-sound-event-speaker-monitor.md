# Feature: Sound Event Speaker Monitor

Play sounds for speaker/audio output events.

## Summary

Monitor speaker activity, output device changes, and audio stream events, playing sounds for speaker events.

## Motivation

- Audio stream feedback
- Device switching alerts
- Output change awareness
- Volume confirmation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Speaker Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Changed | Output device switched | Headphones plugged |
| Stream Started | Audio playback began | Music started |
| Stream Stopped | Audio playback ended | Music paused |
| Stream Paused | Audio paused | Pause pressed |
| High Volume | Volume at maximum | 100% reached |

### Configuration

```go
type SpeakerMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    SoundOnDevice    bool              `json:"sound_on_device"`
    SoundOnStream    bool              `json:"sound_on_stream"`
    MaxVolumeAlert   float64           `json:"max_volume_alert"` // 1.0 default
    WatchApps        []string          `json:"watch_apps"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 2 default
}

type SpeakerEvent struct {
    AppName     string
    EventType   string // "device_changed", "stream_started", "stream_stopped", "stream_paused"
    DeviceName  string
    StreamName  string
}
```

### Commands

```bash
/ccbell:speaker status            # Show speaker status
/ccbell:speaker device on         # Enable device sounds
/ccbell:speaker stream on         # Enable stream sounds
/ccbell:speaker add Spotify       # Add app to watch
/ccbell:speaker sound device <sound>
/ccbell:speaker sound stream <sound>
/ccbell:speaker test              # Test speaker sounds
```

### Output

```
$ ccbell:speaker status

=== Sound Event Speaker Monitor ===

Status: Enabled
Device Sounds: Yes
Stream Sounds: Yes

Current Output:
  Device: AirPods Pro
  Status: Connected
  Volume: 65%
  Active Stream: Spotify

Active Streams: 1

[1] Spotify
    Track: "Song Name"
    Artist: "Artist Name"
    Status: Playing
    Sound: bundled:stop

Output Devices: 3

[1] AirPods Pro (Current)
    Status: Connected
    Sound: bundled:stop

[2] Built-in Speakers
    Status: Available
    Sound: bundled:stop

[3] HDMI Display
    Status: Disconnected
    Sound: bundled:stop

Recent Events:
  [1] AirPods Pro: Device Connected (30 min ago)
  [2] Spotify: Stream Started (1 hour ago)
  [3] Built-in Speakers: Device Disconnected (2 hours ago)

Sound Settings:
  Device Changed: bundled:stop
  Stream Started: bundled:stop
  Stream Stopped: bundled:stop

[Configure] [Add App] [Test All]
```

---

## Audio Player Compatibility

Speaker monitoring doesn't play sounds directly:
- Monitoring feature using audio APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Speaker Monitor

```go
type SpeakerMonitor struct {
    config       *SpeakerMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastDevice   string
    activeStreams map[string]bool
}

func (m *SpeakerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeStreams = make(map[string]bool)
    m.lastDevice = m.getCurrentDevice()
    go m.monitor()
}

func (m *SpeakerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSpeaker()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SpeakerMonitor) checkSpeaker() {
    // Check current output device
    currentDevice := m.getCurrentDevice()
    if currentDevice != m.lastDevice {
        m.onDeviceChanged(currentDevice)
        m.lastDevice = currentDevice
    }

    // Check active audio streams
    activeStreams := m.getActiveStreams()

    for app, isActive := range activeStreams {
        wasActive := m.activeStreams[app]
        m.activeStreams[app] = isActive

        if isActive && !wasActive {
            m.onStreamStarted(app)
        } else if !isActive && wasActive {
            m.onStreamStopped(app)
        }
    }
}

func (m *SpeakerMonitor) getCurrentDevice() string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSOutputDevice()
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxOutputDevice()
    }
    return ""
}

func (m *SpeakerMonitor) getMacOSOutputDevice() string {
    cmd := exec.Command("system_profiler", "SPAudioDataType")
    output, err := cmd.Output()
    if err != nil {
        return ""
    }

    lines := strings.Split(string(output), "\n")
    for i, line := range lines {
        if strings.Contains(line, "Output:") {
            if i+1 < len(lines) {
                return strings.TrimSpace(lines[i+1])
            }
        }
    }

    return "Unknown"
}

func (m *SpeakerMonitor) getLinuxOutputDevice() string {
    cmd := exec.Command("pulseaudio", "--check")
    err := cmd.Run()

    if err == nil {
        // PulseAudio is running
        cmd = exec.Command("pactl", "get-default-sink")
        output, err := cmd.Output()
        if err == nil {
            return strings.TrimSpace(string(output))
        }
    }

    // Fallback to ALSA
    cmd = exec.Command("amixer", "sget", "Master")
    output, err := cmd.Output()
    if err != nil {
        return "default"
    }

    return "default"
}

func (m *SpeakerMonitor) getActiveStreams() map[string]bool {
    streams := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        streams = m.getMacOSStreams()
    } else if runtime.GOOS == "linux" {
        streams = m.getLinuxStreams()
    }

    // Filter to watched apps
    if len(m.config.WatchApps) > 0 {
        filtered := make(map[string]bool)
        for app, active := range streams {
            for _, watched := range m.config.WatchApps {
                if strings.Contains(strings.ToLower(app), strings.ToLower(watched)) {
                    filtered[app] = active
                    break
                }
            }
        }
        return filtered
    }

    return streams
}

func (m *SpeakerMonitor) getMacOSStreams() map[string]bool {
    streams := make(map[string]bool)

    // Check for active audio processes
    cmd := exec.Command("ps", "ax")
    output, err := cmd.Output()
    if err != nil {
        return streams
    }

    audioApps := []string{"Spotify", "iTunes", "VLC", "Safari", "Chrome", "Firefox"}
    for _, app := range audioApps {
        if strings.Contains(string(output), app) {
            streams[app] = true
        }
    }

    return streams
}

func (m *SpeakerMonitor) getLinuxStreams() map[string]bool {
    streams := make(map[string]bool)

    // Check PulseAudio/sink inputs
    cmd := exec.Command("pactl", "list", "sink-inputs")
    output, err := cmd.Output()
    if err != nil {
        return streams
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Spotify") || strings.Contains(line, "vlc") ||
           strings.Contains(line, "chromium") || strings.Contains(line, "firefox") {
            streams["audio-app"] = true
        }
    }

    return streams
}

func (m *SpeakerMonitor) onDeviceChanged(device string) {
    if !m.config.SoundOnDevice {
        return
    }

    sound := m.config.Sounds["device_changed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SpeakerMonitor) onStreamStarted(appName string) {
    if !m.config.SoundOnStream {
        return
    }

    sound := m.config.Sounds["stream_started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SpeakerMonitor) onStreamStopped(appName string) {
    sound := m.config.Sounds["stream_stopped"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| system_profiler | System Tool | Free | macOS audio info |
| pactl | PulseAudio | Free | Linux audio control |
| amixer | ALSA | Free | Linux mixer control |

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
| macOS | Supported | Uses system_profiler |
| Linux | Supported | Uses pactl/amixer |
| Windows | Not Supported | ccbell only supports macOS/Linux |
