# Feature: Sound Event Bluetooth Monitor

Play sounds for Bluetooth device connections and disconnections.

## Summary

Monitor Bluetooth devices, connections, and audio routing changes, playing sounds for Bluetooth events.

## Motivation

- Device connection feedback
- Audio route detection
- Peripheral awareness
- Headphone auto-connect alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Bluetooth Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | Device paired/connected | AirPods connected |
| Device Disconnected | Device disconnected | AirPods disconnected |
| Audio Route Changed | Audio output switched | Switched to Bluetooth |
| Battery Update | Device battery level | AirPods 80% |

### Configuration

```go
type BluetoothMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchDevices     []string          `json:"watch_devices"` // Device names
    SoundOnConnect   bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool             `json:"sound_on_disconnect"`
    SoundOnRouteChange bool           `json:"sound_on_route_change"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type BluetoothEvent struct {
    DeviceName   string
    DeviceAddress string
    EventType    string // "connected", "disconnected", "route_change"
    BatteryLevel int
    AudioDevice  string
}
```

### Commands

```bash
/ccbell:bluetooth status            # Show bluetooth status
/ccbell:bluetooth add "AirPods"     # Add device to watch
/ccbell:bluetooth remove "AirPods"
/ccbell:bluetooth sound connect <sound>
/ccbell:bluetooth sound disconnect <sound>
/ccbell:bluetooth test              # Test bluetooth sounds
```

### Output

```
$ ccbell:bluetooth status

=== Sound Event Bluetooth Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Watched Devices: 2

[1] AirPods Pro
    Connected: Yes
    Battery: 80%
    Address: AA:BB:CC:DD:EE:FF
    Sound: bundled:stop

[2] Sony WH-1000XM4
    Connected: No
    Battery: 45%
    Address: 11:22:33:44:55:66
    Sound: bundled:stop

Current Audio Route: AirPods Pro

Recent Events:
  [1] AirPods Pro: Connected (5 min ago)
  [2] Sony WH-1000XM4: Disconnected (1 hour ago)
  [3] Audio Route Changed (5 min ago)
       Switched to AirPods Pro

Sound Settings:
  Connect: bundled:stop
  Disconnect: bundled:stop
  Route Change: bundled:stop

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Bluetooth monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Bluetooth Monitor

```go
type BluetoothMonitor struct {
    config           *BluetoothMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    deviceState      map[string]*DeviceState
    lastAudioDevice  string
}

type DeviceState struct {
    Name       string
    Address    string
    Connected  bool
    Battery    int
    LastSeen   time.Time
}

func (m *BluetoothMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*DeviceState)
    go m.monitor()
}

func (m *BluetoothMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDevices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BluetoothMonitor) checkDevices() {
    devices := m.getBluetoothDevices()

    for _, device := range devices {
        m.evaluateDevice(device)
    }

    m.checkAudioRoute()
}

func (m *BluetoothMonitor) getBluetoothDevices() []*DeviceInfo {
    var devices []*DeviceInfo

    if runtime.GOOS == "darwin" {
        return m.getDarwinBluetoothDevices()
    }
    return m.getLinuxBluetoothDevices()
}

func (m *BluetoothMonitor) getDarwinBluetoothDevices() []*DeviceInfo {
    var devices []*DeviceInfo

    // Get connected devices
    cmd := exec.Command("system_profiler", "SPBluetoothDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    // Parse JSON output (simplified - real implementation would parse properly)
    var result map[string]interface{}
    if err := json.Unmarshal(output, &result); err != nil {
        return devices
    }

    // Extract device info from parsed JSON
    // This is a simplified version - real implementation would traverse the structure

    return devices
}

func (m *BluetoothMonitor) getLinuxBluetoothDevices() []*DeviceInfo {
    var devices []*DeviceInfo

    // Use bluetoothctl to list devices
    cmd := exec.Command("bluetoothctl", "devices")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.SplitN(line, " ", 3)
        if len(parts) < 3 {
            continue
        }

        devices = append(devices, &DeviceInfo{
            Address: parts[1],
            Name:    strings.TrimSpace(parts[2]),
        })
    }

    // Check connection status
    for _, device := range devices {
        device.Connected = m.isDeviceConnected(device.Address)
    }

    return devices
}

func (m *BluetoothMonitor) isDeviceConnected(address string) bool {
    cmd := exec.Command("bluetoothctl", "info", address)
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.Contains(string(output), "Connected: yes")
}

func (m *BluetoothMonitor) evaluateDevice(device *DeviceInfo) {
    key := device.Address
    lastState := m.deviceState[key]

    if lastState == nil {
        // First time seeing this device
        m.deviceState[key] = &DeviceState{
            Name:      device.Name,
            Address:   device.Address,
            Connected: device.Connected,
            LastSeen:  time.Now(),
        }

        if device.Connected {
            m.onDeviceConnected(device)
        }
        return
    }

    // Detect changes
    if !lastState.Connected && device.Connected {
        m.onDeviceConnected(device)
    } else if lastState.Connected && !device.Connected {
        m.onDeviceDisconnected(lastState)
    }

    // Update state
    lastState.Connected = device.Connected
    lastState.LastSeen = time.Now()
}

func (m *BluetoothMonitor) checkAudioRoute() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinAudioRoute()
    } else {
        m.checkLinuxAudioRoute()
    }
}

func (m *BluetoothMonitor) checkDarwinAudioRoute() {
    cmd := exec.Command("SwitchAudioSource", "-t", "output", "-c")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentDevice := strings.TrimSpace(string(output))

    if m.lastAudioDevice != "" && m.lastAudioDevice != currentDevice {
        if strings.Contains(strings.ToLower(currentDevice), "bluetooth") ||
           strings.Contains(strings.ToLower(m.lastAudioDevice), "bluetooth") {
            m.onAudioRouteChange(currentDevice)
        }
    }

    m.lastAudioDevice = currentDevice
}

func (m *BluetoothMonitor) checkLinuxAudioRoute() {
    // Use pactl for PulseAudio systems
    cmd := exec.Command("pactl", "get-default-sink")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentSink := strings.TrimSpace(string(output))

    if m.lastAudioDevice != "" && m.lastAudioDevice != currentSink {
        if strings.Contains(strings.ToLower(currentSink), "blue") ||
           strings.Contains(strings.ToLower(m.lastAudioDevice), "blue") {
            m.onAudioRouteChange(currentSink)
        }
    }

    m.lastAudioDevice = currentSink
}

func (m *BluetoothMonitor) onDeviceConnected(device *DeviceInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    // Check if this device is being watched
    if len(m.config.WatchDevices) > 0 {
        found := false
        for _, watchName := range m.config.WatchDevices {
            if strings.Contains(strings.ToLower(device.Name), strings.ToLower(watchName)) {
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

func (m *BluetoothMonitor) onDeviceDisconnected(state *DeviceState) {
    if !m.config.SoundOnDisconnect {
        return
    }

    // Check if this device is being watched
    if len(m.config.WatchDevices) > 0 {
        found := false
        for _, watchName := range m.config.WatchDevices {
            if strings.Contains(strings.ToLower(state.Name), strings.ToLower(watchName)) {
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

func (m *BluetoothMonitor) onAudioRouteChange(device string) {
    if !m.config.SoundOnRouteChange {
        return
    }

    sound := m.config.Sounds["route_change"]
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
| bluetoothctl | System Tool | Free | Linux Bluetooth |
| SwitchAudioSource | System Tool | Free | macOS audio routing |
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
| macOS | Supported | Uses system_profiler |
| Linux | Supported | Uses bluetoothctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
