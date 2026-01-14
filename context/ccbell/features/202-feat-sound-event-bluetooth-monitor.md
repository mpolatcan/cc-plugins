# Feature: Sound Event Bluetooth Monitor

Play sounds for Bluetooth device events.

## Summary

Play sounds when Bluetooth devices connect or disconnect.

## Motivation

- Device awareness
- Audio device switching
- Connection notifications

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
| Device Connected | BT device paired | Headphones connected |
| Device Disconnected | BT device unpaired | Headphones disconnected |
| Audio Connected | Audio device connected | AirPods connected |
| Audio Disconnected | Audio device disconnected | AirPods disconnected |

### Configuration

```go
type BluetoothMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchDevices  []*BTDeviceWatch `json:"watch_devices"`
    WatchTypes    []string          `json:"watch_types"` // "audio", "input", "all"
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int              `json:"poll_interval_sec"` // 10 default
}

type BTDeviceWatch struct {
    Address     string  `json:"address"` // MAC address or ID
    Name        string  `json:"name"` // Device name
    Type        string  `json:"type"` // "audio", "input", "other"
    Sound       string  `json:"sound"`
    Enabled     bool    `json:"enabled"`
}

type BTDevice struct {
    Address     string
    Name        string
    Connected   bool
    Type        string
    Battery     int // Percentage if available
}
```

### Commands

```bash
/ccbell:bluetooth status            # Show Bluetooth status
/ccbell:bluetooth list              # List paired devices
/ccbell:bluetooth add "AirPods" --address XX:XX:XX:XX:XX:XX
/ccbell:bluetooth sound connected <sound>
/ccbell:bluetooth sound disconnected <sound>
/ccbell:bluetooth sound audio <sound>
/ccbell:bluetooth remove "AirPods"
/ccbell:bluetooth test              # Test Bluetooth sounds
```

### Output

```
$ ccbell:bluetooth status

=== Sound Event Bluetooth Monitor ===

Status: Enabled
Poll Interval: 10s

Paired Devices: 8
Connected: 2

[1] AirPods Pro
    Address: AA:BB:CC:DD:EE:FF
    Type: audio
    Status: Connected
    Battery: 85%
    Sound: bundled:stop
    [Edit] [Remove]

[2] Magic Keyboard
    Address: 11:22:33:44:55:66
    Type: input
    Status: Connected
    Sound: bundled:stop
    [Edit] [Remove]

[3] Beats Studio3
    Address: 77:88:99:AA:BB:CC
    Type: audio
    Status: Disconnected
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] AirPods Pro: Connected (5 min ago)
  [2] Magic Keyboard: Connected (2 hours ago)

[Configure] [List] [Test All]
```

---

## Audio Player Compatibility

Bluetooth monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Bluetooth Monitor

```go
type BluetoothMonitor struct {
    config   *BluetoothMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastStates map[string]*BTDevice
}

func (m *BluetoothMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStates = make(map[string]*BTDevice)
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
    devices := m.listBluetoothDevices()

    for _, device := range devices {
        m.evaluateDevice(device)
    }
}

func (m *BluetoothMonitor) listBluetoothDevices() []*BTDevice {
    var devices []*BTDevice

    // macOS: system_profiler
    cmd := exec.Command("system_profiler", "SPBluetoothDataType")
    output, err := cmd.Output()
    if err == nil {
        devices = m.parseMacOSBluetooth(string(output))
        return devices
    }

    // Linux: bluetoothctl
    cmd = exec.Command("bluetoothctl", "devices", "Connected")
    output, err = cmd.Output()
    if err == nil {
        devices = m.parseBluetoothCTL(string(output), true)
    }

    // Also get all paired devices
    cmd = exec.Command("bluetoothctl", "paired-devices")
    output, err = cmd.Output()
    if err == nil {
        pairedDevices := m.parseBluetoothCTL(string(output), false)
        for _, pd := range pairedDevices {
            // Mark as disconnected if not in connected list
            found := false
            for _, d := range devices {
                if d.Address == pd.Address {
                    found = true
                    break
                }
            }
            if !found {
                pd.Connected = false
                devices = append(devices, pd)
            }
        }
    }

    return devices
}

func (m *BluetoothMonitor) parseBluetoothCTL(output string, connectedOnly bool) []*BTDevice {
    var devices []*BTDevice

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, " ", 3)
        if len(parts) < 3 {
            continue
        }

        address := parts[1]
        name := strings.Trim(parts[2], " \"")

        device := &BTDevice{
            Address:   address,
            Name:      name,
            Connected: connectedOnly,
        }

        // Determine type (simplified)
        if strings.Contains(strings.ToLower(name), "headphone") ||
           strings.Contains(strings.ToLower(name), "airpod") ||
           strings.Contains(strings.ToLower(name), "speaker") {
            device.Type = "audio"
        } else if strings.Contains(strings.ToLower(name), "keyboard") ||
                  strings.Contains(strings.ToLower(name), "mouse") {
            device.Type = "input"
        } else {
            device.Type = "other"
        }

        devices = append(devices, device)
    }

    return devices
}

func (m *BluetoothMonitor) evaluateDevice(device *BTDevice) {
    lastState := m.lastStates[device.Address]

    // New device detected
    if lastState == nil {
        if device.Connected {
            m.onDeviceConnected(device)
        }
        m.lastStates[device.Address] = device
        return
    }

    // Connection state changed
    if device.Connected && !lastState.Connected {
        m.onDeviceConnected(device)
    } else if !device.Connected && lastState.Connected {
        m.onDeviceDisconnected(device)
    }

    m.lastStates[device.Address] = device
}

func (m *BluetoothMonitor) onDeviceConnected(device *BTDevice) {
    // Find configured sound
    sound := m.findSoundForDevice(device, "connected")
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BluetoothMonitor) onDeviceDisconnected(device *BTDevice) {
    sound := m.findSoundForDevice(device, "disconnected")
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BluetoothMonitor) findSoundForDevice(device *BTDevice, eventType string) string {
    // Check specific device config
    for _, watch := range m.config.WatchDevices {
        if watch.Address == device.Address || watch.Name == device.Name {
            return watch.Sound
        }
    }

    // Check type-based sound
    if device.Type == "audio" && eventType == "connected" {
        return m.config.Sounds["audio_connected"]
    }

    // Return default
    return m.config.Sounds[eventType]
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| bluetoothctl | System Tool | Free | Linux Bluetooth |
| system_profiler | System Tool | Free | macOS Bluetooth |

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
| macOS | ✅ Supported | Uses system_profiler |
| Linux | ✅ Supported | Uses bluetoothctl |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
