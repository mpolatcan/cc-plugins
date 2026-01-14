# Feature: Sound Event Audio Device Monitor

Play sounds for audio device changes, connection status, and default device switches.

## Summary

Monitor audio devices for connection events, default device changes, and volume changes, playing sounds for audio events.

## Motivation

- Device awareness
- Audio routing feedback
- Peripheral detection
- Volume change alerts
- Sound system health

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Audio Device Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | Audio device added | headphones |
| Device Disconnected | Audio device removed | unplugged |
| Default Changed | Default output switched | HDMI -> headphone |
| Volume Changed | Volume level changed | mute/unmute |
| Device Added | New device detected | new sink |
| Device Removed | Device disappeared | device gone |

### Configuration

```go
type AudioDeviceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchTypes        []string          `json:"watch_types"` // "output", "input", "sink", "source"
    WatchDevices      []string          `json:"watch_devices"` // "HDMI", "Headphones", "*"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnDefault    bool              `json:"sound_on_default"`
    VolumeThreshold   int               `json:"volume_threshold"` // 0 for mute detection
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:audio status                   # Show audio status
/ccbell:audio add "Headphones"         # Add device to watch
/ccbell:audio add type output          # Add device type
/ccbell:audio sound connect <sound>
/ccbell:audio sound disconnect <sound>
/ccbell:audio test                     # Test audio sounds
```

### Output

```
$ ccbell:audio status

=== Sound Event Audio Device Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Default Change Sounds: Yes

Watched Types: 2
Watched Devices: 2

Audio Devices:

[1] Built-in Speakers (output)
    Status: Active
    Default: Yes
    Volume: 75%
    Sound: bundled:audio-speakers

[2] AirPods Pro (output)
    Status: Connected
    Default: No
    Volume: 50%
    Battery: 85%
    Sound: bundled:audio-airpods

[3] USB Microphone (input)
    Status: Connected
    Default: No
    Volume: 80%
    Sound: bundled:audio-mic

[4] HDMI (output)
    Status: Disconnected
    Default: No
    Sound: bundled:audio-hdmi

Recent Events:
  [1] AirPods Pro: Connected (5 min ago)
       Battery: 85%
  [2] HDMI: Disconnected (1 hour ago)
       Cable unplugged
  [3] Built-in Speakers: Volume Changed (2 hours ago)
       50% -> 75%
  [4] AirPods Pro: Set as Default (3 hours ago)
       Switched to AirPods Pro

Audio Statistics:
  Connections Today: 5
  Disconnections: 3
  Default Changes: 2

Sound Settings:
  Connect: bundled:audio-connect
  Disconnect: bundled:audio-disconnect
  Default: bundled:audio-default

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Audio device monitoring doesn't play sounds directly:
- Monitoring feature using pactl/pulseaudio, system_profiler
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Audio Device Monitor

```go
type AudioDeviceMonitor struct {
    config          *AudioDeviceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*AudioDeviceInfo
    lastEventTime   map[string]time.Time
}

type AudioDeviceInfo struct {
    Name       string
    Type       string // "output", "input", "sink", "source"
    Status     string // "connected", "disconnected", "active"
    Default    bool
    Volume     int    // percentage
    DefaultDevice string
}

func (m *AudioDeviceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*AudioDeviceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *AudioDeviceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDeviceState()

    for {
        select {
        case <-ticker.C:
            m.checkDeviceState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *AudioDeviceMonitor) snapshotDeviceState() {
    if m.isPulseAudioAvailable() {
        m.listPulseDevices()
    } else {
        m.listCoreAudioDevices()
    }
}

func (m *AudioDeviceMonitor) checkDeviceState() {
    var currentDevices map[string]*AudioDeviceInfo

    if m.isPulseAudioAvailable() {
        currentDevices = m.listPulseDevices()
    } else {
        currentDevices = m.listCoreAudioDevices()
    }

    // Check for new devices
    for id, device := range currentDevices {
        lastDevice := m.deviceState[id]
        if lastDevice == nil {
            m.deviceState[id] = device
            if m.shouldWatchDevice(device.Name) {
                m.onDeviceConnected(device)
            }
            continue
        }

        // Check status changes
        if lastDevice.Status != device.Status {
            if device.Status == "connected" {
                m.onDeviceConnected(device)
            } else if device.Status == "disconnected" {
                m.onDeviceDisconnected(lastDevice)
            }
        }

        // Check default change
        if !lastDevice.Default && device.Default {
            if m.config.SoundOnDefault {
                m.onDefaultChanged(device)
            }
        }

        // Check volume change
        if lastDevice.Volume != device.Volume {
            if device.Volume == m.config.VolumeThreshold {
                m.onVolumeChanged(device)
            }
        }

        m.deviceState[id] = device
    }

    // Check for removed devices
    for id, lastDevice := range m.deviceState {
        if _, exists := currentDevices[id]; !exists {
            delete(m.deviceState, id)
            if lastDevice.Status == "connected" {
                m.onDeviceDisconnected(lastDevice)
            }
        }
    }
}

func (m *AudioDeviceMonitor) isPulseAudioAvailable() bool {
    cmd := exec.Command("which", "pactl")
    err := cmd.Run()
    return err == nil
}

func (m *AudioDeviceMonitor) listPulseDevices() map[string]*AudioDeviceInfo {
    devices := make(map[string]*AudioDeviceInfo)

    // List sinks (outputs)
    cmd := exec.Command("pactl", "list", "sinks", "short")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) >= 2 {
            name := parts[1]
            id := fmt.Sprintf("sink:%s", name)

            info := &AudioDeviceInfo{
                Name:   name,
                Type:   "sink",
                Status: "connected",
            }

            // Get more details
            details := m.getPulseDeviceDetails("sink", name)
            if details != nil {
                info.Default = details.Default
                info.Volume = details.Volume
            }

            devices[id] = info
        }
    }

    // List sources (inputs)
    cmd = exec.Command("pactl", "list", "sources", "short")
    output, _ = cmd.Output()

    lines = strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) >= 2 {
            name := parts[1]
            id := fmt.Sprintf("source:%s", name)

            info := &AudioDeviceInfo{
                Name:   name,
                Type:   "source",
                Status: "connected",
            }

            devices[id] = info
        }
    }

    return devices
}

func (m *AudioDeviceMonitor) getPulseDeviceDetails(deviceType, name string) *AudioDeviceInfo {
    cmd := exec.Command("pactl", "list", fmt.Sprintf("%ss", deviceType), "long")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    // Parse output to find device
    inDevice := false
    info := &AudioDeviceInfo{}

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, fmt.Sprintf("Name: %s", name)) {
            inDevice = true
            continue
        }

        if inDevice {
            if strings.HasPrefix(line, "Sink #") || strings.HasPrefix(line, "Source #") {
                if !strings.Contains(line, name) {
                    inDevice = false
                    continue
                }
            }

            if strings.HasPrefix(line, "Mute: ") {
                info.Status = "disconnected"
            } else if strings.HasPrefix(line, "Volume:") {
                re := regexp.MustEach(`(\d+)%`)
                // Parse volume
            } else if line == "" {
                inDevice = false
            }
        }
    }

    return info
}

func (m *AudioDeviceMonitor) listCoreAudioDevices() map[string]*AudioDeviceInfo {
    devices := make(map[string]*AudioDeviceInfo)

    cmd := exec.Command("system_profiler", "SPAudioDataType")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    // Parse system_profiler output
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, ":") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) == 2 {
                name := strings.TrimSpace(parts[1])
                id := fmt.Sprintf("audio:%s", name)

                deviceType := "output"
                if strings.Contains(strings.ToLower(line), "input") {
                    deviceType = "input"
                }

                devices[id] = &AudioDeviceInfo{
                    Name:   name,
                    Type:   deviceType,
                    Status: "connected",
                }
            }
        }
    }

    return devices
}

func (m *AudioDeviceMonitor) onDeviceConnected(device *AudioDeviceInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    if !m.shouldWatchDevice(device.Name) {
        return
    }

    key := fmt.Sprintf("connect:%s:%s", device.Type, device.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AudioDeviceMonitor) onDeviceDisconnected(device *AudioDeviceInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s:%s", device.Type, device.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AudioDeviceMonitor) onDefaultChanged(device *AudioDeviceInfo) {
    if !m.config.SoundOnDefault {
        return
    }

    key := fmt.Sprintf("default:%s:%s", device.Type, device.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["default"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *AudioDeviceMonitor) onVolumeChanged(device *AudioDeviceInfo) {
    // Optional: sound for mute/unmute
}

func (m *AudioDeviceMonitor) shouldWatchDevice(name string) bool {
    if len(m.config.WatchDevices) == 0 {
        return true
    }

    for _, d := range m.config.WatchDevices {
        if d == "*" || strings.Contains(strings.ToLower(name), strings.ToLower(d)) {
            return true
        }
    }

    return false
}

func (m *AudioDeviceMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pactl | System Tool | Free | PulseAudio control |
| system_profiler | System Tool | Free | macOS hardware info |
| pmset | System Tool | Free | Power management |

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
| Linux | Supported | Uses pactl (PulseAudio) |
