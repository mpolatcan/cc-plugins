# Feature: Sound Event Audio Device Monitor

Play sounds for audio device connections, disconnections, and default device changes.

## Summary

Monitor audio devices for connection status, device changes, and volume events, playing sounds for audio device events.

## Motivation

- Device awareness
- Connection feedback
- Default device alerts
- Input/output switching
- Audio device health

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Audio Device Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | Audio device plugged | Headphones |
| Device Disconnected | Device unplugged | Headphones |
| Default Changed | Default device switched | HDMI |
| Volume Changed | Volume adjusted | 50% -> 75% |
| Muted | Audio muted | muted |
| Unmuted | Audio unmuted | unmuted |

### Configuration

```go
type AudioDeviceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDevices      []string          `json:"watch_devices"` // "Built-in", "*"
    WatchInput        bool              `json:"watch_input"` // true default
    WatchOutput       bool              `json:"watch_output"` // true default
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnDefault    bool              `json:"sound_on_default"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:audio status                # Show audio status
/ccbell:audio add "Built-in"        # Add device to watch
/ccbell:audio sound connect <sound>
/ccbell:audio sound disconnect <sound>
/ccbell:audio test                  # Test audio sounds
```

### Output

```
$ ccbell:audio status

=== Sound Event Audio Device Monitor ===

Status: Enabled
Watch Input: Yes
Watch Output: Yes

Audio Devices:

[1] Built-in Microphone (Input)
    Status: CONNECTED
    Default: Yes
    Volume: 75%
    Sound: bundled:audio-mic

[2] Built-in Output (Output)
    Status: CONNECTED
    Default: Yes
    Volume: 50%
    Balanced: 50%/50%
    Sound: bundled:audio-output

[3] USB Headphones (Output)
    Status: CONNECTED
    Default: No
    Volume: 80%
    Sound: bundled:audio-headphones

[4] AirPods Pro (Input/Output)
    Status: DISCONNECTED *** DISCONNECTED ***
    Last Connected: 2 hours ago
    Sound: bundled:audio-airpods *** OFFLINE ***

Default Device: Built-in Output

Recent Audio Events:
  [1] AirPods Pro: Disconnected (2 hours ago)
       Battery: 20%
       Sound: bundled:audio-disconnect
  [2] USB Headphones: Connected (3 hours ago)
       Connected via USB
       Sound: bundled:audio-connect
  [3] Built-in Output: Volume Changed (5 hours ago)
       50% -> 75%

Audio Statistics:
  Input Devices: 2
  Output Devices: 2
  Connected: 3
  Disconnected: 1

Sound Settings:
  Connect: bundled:audio-connect
  Disconnect: bundled:audio-disconnect
  Default: bundled:audio-default
  Volume: bundled:audio-volume

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Audio device monitoring doesn't play sounds directly:
- Monitoring feature using system_profiler/pulseaudio
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
    Name        string
    Type        string // "input", "output", "both"
    Status      string // "connected", "disconnected", "unknown"
    IsDefault   bool
    Volume      int
    UID         string
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
    m.checkDeviceState()
}

func (m *AudioDeviceMonitor) checkDeviceState() {
    devices := m.listAudioDevices()

    for _, device := range devices {
        if !m.shouldWatchDevice(device.Name) {
            continue
        }
        m.processDeviceStatus(device)
    }
}

func (m *AudioDeviceMonitor) listAudioDevices() []*AudioDeviceInfo {
    if runtime.GOOS == "darwin" {
        return m.listDarwinAudioDevices()
    }
    return m.listLinuxAudioDevices()
}

func (m *AudioDeviceMonitor) listDarwinAudioDevices() []*AudioDeviceInfo {
    var devices []*AudioDeviceInfo

    // Use system_profiler to get audio devices
    cmd := exec.Command("system_profiler", "SPAudioDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    // Parse JSON output (simplified - real parsing would use json package)
    outputStr := string(output)

    // Extract device names from output
    re := regexp.MustEach(`"deviceName":\s*"([^"]+)"`)
    matches := re.FindAllStringSubmatch(outputStr, -1)

    deviceNames := make(map[string]bool)
    for _, match := range matches {
        if len(match) >= 2 {
            deviceNames[match[1]] = true
        }
    }

    // Use lsbuf or other tools for more details
    for name := range deviceNames {
        device := &AudioDeviceInfo{
            Name:   name,
            Status: "connected",
        }

        // Get volume if available
        cmd = exec.Command("osascript", "-e",
            fmt.Sprintf(`output volume of (get volume settings)`))
        volOutput, _ := cmd.Output()
        if len(volOutput) > 0 {
            device.Volume, _ = strconv.Atoi(strings.TrimSpace(string(volOutput)))
        }

        devices = append(devices, device)
    }

    // Also check using audio check
    cmd = exec.Command("system_profiler", "SPAudioDataType")
    output, _ = cmd.Output()
    outputStr = string(output)

    // Parse more details
    if strings.Contains(outputStr, "Input") {
        inputDevice := &AudioDeviceInfo{
            Name:   "Built-in Microphone",
            Type:   "input",
            Status: "connected",
        }
        devices = append(devices, inputDevice)
    }

    if strings.Contains(outputStr, "Output") {
        outputDevice := &AudioDeviceInfo{
            Name:   "Built-in Output",
            Type:   "output",
            Status: "connected",
        }
        devices = append(devices, outputDevice)
    }

    return devices
}

func (m *AudioDeviceMonitor) listLinuxAudioDevices() []*AudioDeviceInfo {
    var devices []*AudioDeviceInfo

    // Try PulseAudio tools first
    if m.commandExists("pactl") {
        devices = m.listPulseAudioDevices()
    }

    // Fallback to ALSA tools
    if len(devices) == 0 && m.commandExists("aplay") {
        devices = m.listALSADevices()
    }

    return devices
}

func (m *AudioDeviceMonitor) listPulseAudioDevices() []*AudioDeviceInfo {
    var devices []*AudioDeviceInfo

    // List sinks (output devices)
    cmd := exec.Command("pactl", "list", "short", "sinks")
    output, err := cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                device := &AudioDeviceInfo{
                    Name:   parts[1],
                    Type:   "output",
                    Status: "connected",
                }
                devices = append(devices, device)
            }
        }
    }

    // List sources (input devices)
    cmd = exec.Command("pactl", "list", "short", "sources")
    output, err = cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                device := &AudioDeviceInfo{
                    Name:   parts[1],
                    Type:   "input",
                    Status: "connected",
                }
                devices = append(devices, device)
            }
        }
    }

    // Get default device
    cmd = exec.Command("pactl", "get-default-sink")
    defaultSink, _ := cmd.Output()
    defaultSinkName := strings.TrimSpace(string(defaultSink))

    for _, device := range devices {
        if device.Name == defaultSinkName {
            device.IsDefault = true
        }
    }

    return devices
}

func (m *AudioDeviceMonitor) listALSADevices() []*AudioDeviceInfo {
    var devices []*AudioDeviceInfo

    // List ALSA cards
    cmd := exec.Command("aplay", "-l")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "card") {
            // Parse: card 0: PCH [HDA Intel PCH], device 0: ALC...
            parts := strings.SplitN(line, ":", 2)
            if len(parts) >= 2 {
                name := strings.TrimSpace(parts[1])
                device := &AudioDeviceInfo{
                    Name:   name,
                    Type:   "output",
                    Status: "connected",
                }
                devices = append(devices, device)
            }
        }
    }

    return devices
}

func (m *AudioDeviceMonitor) commandExists(cmd string) bool {
    _, err := exec.LookPath(cmd)
    return err == nil
}

func (m *AudioDeviceMonitor) shouldWatchDevice(name string) bool {
    if len(m.config.WatchDevices) == 0 {
        return true
    }

    for _, d := range m.config.WatchDevices {
        if d == "*" || name == d || strings.Contains(name, d) {
            return true
        }
    }

    return false
}

func (m *AudioDeviceMonitor) processDeviceStatus(device *AudioDeviceInfo) {
    lastInfo := m.deviceState[device.Name]

    if lastInfo == nil {
        m.deviceState[device.Name] = device
        if device.Status == "connected" && m.config.SoundOnConnect {
            m.onDeviceConnected(device)
        }
        return
    }

    // Check for connection changes
    if device.Status != lastInfo.Status {
        if device.Status == "connected" {
            if m.config.SoundOnConnect {
                m.onDeviceConnected(device)
            }
        } else if device.Status == "disconnected" {
            if m.config.SoundOnDisconnect {
                m.onDeviceDisconnected(device)
            }
        }
    }

    // Check for default device changes
    if device.IsDefault && !lastInfo.IsDefault {
        if m.config.SoundOnDefault {
            m.onDefaultChanged(device)
        }
    }

    m.deviceState[device.Name] = device
}

func (m *AudioDeviceMonitor) onDeviceConnected(device *AudioDeviceInfo) {
    key := fmt.Sprintf("connect:%s", device.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AudioDeviceMonitor) onDeviceDisconnected(device *AudioDeviceInfo) {
    key := fmt.Sprintf("disconnect:%s", device.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *AudioDeviceMonitor) onDefaultChanged(device *AudioDeviceInfo) {
    key := fmt.Sprintf("default:%s", device.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["default"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
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
| system_profiler | System Tool | Free | macOS system profiler |
| pactl | System Tool | Free | PulseAudio control |
| aplay | System Tool | Free | ALSA player |

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
| Linux | Supported | Uses pactl (PulseAudio), aplay (ALSA) |
