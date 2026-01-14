# Feature: Sound Event Audio Device Monitor

Play sounds for audio device changes and routing.

## Summary

Monitor audio device connections, disconnections, and routing changes, playing sounds for audio device events.

## Motivation

- Device connection feedback
- Audio route awareness
- Headphone detection
- Input/output switching

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
| Device Connected | Audio device added | USB mic |
| Device Disconnected | Audio device removed | Headphones unplugged |
| Default Changed | Default device changed | Switched to HDMI |
| Volume Changed | Volume adjusted | Volume muted |

### Configuration

```go
type AudioDeviceMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchDeviceTypes   []string          `json:"watch_device_types"` // "input", "output"
    SoundOnConnect     bool              `json:"sound_on_connect"`
    SoundOnDisconnect  bool              `json:"sound_on_disconnect"`
    SoundOnDefaultChange bool            `json:"sound_on_default_change"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type AudioDeviceEvent struct {
    DeviceName   string
    DeviceType   string // "input", "output"
    DeviceID     string
    EventType    string // "connected", "disconnected", "default_change"
    IsDefault    bool
}
```

### Commands

```bash
/ccbell:audio-device status            # Show audio device status
/ccbell:audio-device add input         # Add device type to watch
/ccbell:audio-device remove input
/ccbell:audio-device sound connect <sound>
/ccbell:audio-device sound disconnect <sound>
/ccbell:audio-device test              # Test audio device sounds
```

### Output

```
$ ccbell:audio-device status

=== Sound Event Audio Device Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Input Devices: 2

[1] Built-in Microphone
    ID: device_123
    Connected: Yes
    Default: Yes
    Sound: bundled:stop

[2] USB Microphone
    ID: device_456
    Connected: No
    Last Seen: 2 hours ago
    Sound: bundled:stop

Output Devices: 3

[1] Built-in Speakers
    ID: output_123
    Connected: Yes
    Default: No
    Sound: bundled:stop

[2] AirPods Pro
    ID: output_789
    Connected: Yes
    Default: Yes
    Sound: bundled:stop

[3] HDMI Display
    ID: output_111
    Connected: No
    Sound: bundled:stop

Recent Events:
  [1] AirPods Pro: Connected (5 min ago)
       Default output changed
  [2] USB Microphone: Disconnected (2 hours ago)
  [3] Built-in Speakers: Default Changed (5 hours ago)

Sound Settings:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Default Change: bundled:stop

[Configure] [Add Type] [Test All]
```

---

## Audio Player Compatibility

Audio device monitoring doesn't play sounds directly:
- Monitoring feature using audio system commands
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
    deviceState     map[string]*DeviceInfo
    lastDefaultInput  string
    lastDefaultOutput string
}

type DeviceInfo struct {
    Name      string
    ID        string
    DeviceType string
    Connected bool
    IsDefault bool
}
```

```go
func (m *AudioDeviceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*DeviceInfo)
    go m.monitor()
}

func (m *AudioDeviceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkAudioDevices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *AudioDeviceMonitor) checkAudioDevices() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinAudioDevices()
    } else {
        m.checkLinuxAudioDevices()
    }
}

func (m *AudioDeviceMonitor) checkDarwinAudioDevices() {
    // Use system_profiler for audio devices
    cmd := exec.Command("system_profiler", "SPAudioDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse JSON (simplified)
    var result map[string]interface{}
    if err := json.Unmarshal(output, &result); err != nil {
        return
    }

    // Extract audio devices
    // This is a simplified implementation

    // Also check default device using SwitchAudioSource
    m.checkDarwinDefaultDevices()
}

func (m *AudioDeviceMonitor) checkDarwinDefaultDevices() {
    // Check default input
    cmd := exec.Command("SwitchAudioSource", "-t", "input", "-c")
    output, _ := cmd.Output()
    defaultInput := strings.TrimSpace(string(output))

    if defaultInput != m.lastDefaultInput && defaultInput != "" {
        m.onDefaultChanged("input", defaultInput)
        m.lastDefaultInput = defaultInput
    }

    // Check default output
    cmd = exec.Command("SwitchAudioSource", "-t", "output", "-c")
    output, _ = cmd.Output()
    defaultOutput := strings.TrimSpace(string(output))

    if defaultOutput != m.lastDefaultOutput && defaultOutput != "" {
        m.onDefaultChanged("output", defaultOutput)
        m.lastDefaultOutput = defaultOutput
    }
}

func (m *AudioDeviceMonitor) checkLinuxAudioDevices() {
    // Use aplay -l for playback devices
    cmd := exec.Command("aplay", "-l")
    output, err := cmd.Output()
    if err == nil {
        m.parseALSAOutput(string(output), "output")
    }

    // Use arecord -l for capture devices
    cmd = exec.Command("arecord", "-l")
    output, err = cmd.Output()
    if err == nil {
        m.parseALSAOutput(string(output), "input")
    }

    // Check default device using amixer or pactl
    m.checkLinuxDefaultDevices()
}

func (m *AudioDeviceMonitor) parseALSAOutput(output string, deviceType string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "card ") {
            // Parse: "card 0: PCH [HDA Intel PCH], device 0: ALC..."
            parts := strings.SplitN(line, ":", 2)
            if len(parts) < 2 {
                continue
            }

            cardInfo := strings.TrimSpace(parts[0])
            deviceInfo := strings.TrimSpace(parts[1])

            // Extract card number
            cardMatch := regexp.MustCompile(`card (\d+)`).FindStringSubmatch(cardInfo)
            if cardMatch == nil {
                continue
            }

            cardNum := cardMatch[1]
            deviceID := fmt.Sprintf("alsa:%s:%s", deviceType, cardNum)

            // Update device state
            m.updateDeviceState(deviceID, deviceInfo, deviceType, true)
        }
    }
}

func (m *AudioDeviceMonitor) checkLinuxDefaultDevices() {
    // Use pactl for PulseAudio
    cmd := exec.Command("pactl", "get-default-sink")
    output, err := cmd.Output()
    if err == nil {
        defaultSink := strings.TrimSpace(string(output))
        if defaultSink != m.lastDefaultOutput && defaultSink != "" {
            m.onDefaultChanged("output", defaultSink)
            m.lastDefaultOutput = defaultSink
        }
    }

    // Check default source
    cmd = exec.Command("pactl", "get-default-source")
    output, err = cmd.Output()
    if err == nil {
        defaultSource := strings.TrimSpace(string(output))
        if defaultSource != m.lastDefaultInput && defaultSource != "" {
            m.onDefaultChanged("input", defaultSource)
            m.lastDefaultInput = defaultSource
        }
    }
}

func (m *AudioDeviceMonitor) updateDeviceState(deviceID string, name string, deviceType string, connected bool) {
    key := deviceID
    lastState := m.deviceState[key]

    if lastState == nil {
        // New device
        m.deviceState[key] = &DeviceInfo{
            Name:       name,
            ID:         deviceID,
            DeviceType: deviceType,
            Connected:  connected,
        }

        if connected {
            m.onDeviceConnected(name, deviceType)
        }
        return
    }

    // Detect changes
    if lastState.Connected && !connected {
        lastState.Connected = false
        m.onDeviceDisconnected(lastState.Name, deviceType)
    } else if !lastState.Connected && connected {
        lastState.Connected = true
        m.onDeviceConnected(name, deviceType)
    }

    lastState.Name = name
}

func (m *AudioDeviceMonitor) onDeviceConnected(name string, deviceType string) {
    if !m.config.SoundOnConnect {
        return
    }

    // Check device type filter
    if len(m.config.WatchDeviceTypes) > 0 {
        found := false
        for _, t := range m.config.WatchDeviceTypes {
            if t == deviceType {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AudioDeviceMonitor) onDeviceDisconnected(name string, deviceType string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    // Check device type filter
    if len(m.config.WatchDeviceTypes) > 0 {
        found := false
        for _, t := range m.config.WatchDeviceTypes {
            if t == deviceType {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AudioDeviceMonitor) onDefaultChanged(deviceType string, deviceName string) {
    if !m.config.SoundOnDefaultChange {
        return
    }

    sound := m.config.Sounds["default_change"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| system_profiler | System Tool | Free | macOS hardware info |
| SwitchAudioSource | System Tool | Free | macOS audio routing |
| aplay/arecord | System Tool | Free | ALSA audio tools |
| pactl | System Tool | Free | PulseAudio control |

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
| macOS | Supported | Uses system_profiler, SwitchAudioSource |
| Linux | Supported | Uses aplay, pactl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
