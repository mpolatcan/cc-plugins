# Feature: Sound Event Bluetooth Monitor

Play sounds for Bluetooth device connections and adapter changes.

## Summary

Monitor Bluetooth adapter status, device pairings, and connection events, playing sounds for Bluetooth events.

## Motivation

- Bluetooth awareness
- Device connection feedback
- Adapter state changes
- Pairing notifications
- Audio device switching

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Bluetooth Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | Bluetooth device paired | AirPods connected |
| Device Disconnected | Bluetooth device unpaired | AirPods disconnected |
| Adapter Powered | Adapter powered on/off | Bluetooth on |
| Adapter Discoverable | Adapter discoverable mode | Discoverable enabled |
| Device Added | New device paired | New device paired |
| Device Removed | Device unpaired | Device forgotten |

### Configuration

```go
type BluetoothMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchDevices       []string          `json:"watch_devices"` // "AirPods", "Magic Mouse", "*"
    SoundOnConnect     bool              `json:"sound_on_connect"`
    SoundOnDisconnect  bool              `json:"sound_on_disconnect"`
    SoundOnAdapter     bool              `json:"sound_on_adapter"`
    SoundOnDiscoverable bool             `json:"sound_on_discoverable"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type BluetoothEvent struct {
    Device      string
    Address     string
    Adapter     string
    DeviceType  string // "audio", "input", "phone"
    Connected   bool
    EventType   string // "connect", "disconnect", "adapter", "discoverable"
}
```

### Commands

```bash
/ccbell:bluetooth status              # Show Bluetooth status
/ccbell:bluetooth add "AirPods"       # Add device to watch
/ccbell:bluetooth remove "AirPods"
/ccbell:bluetooth sound connect <sound>
/ccbell:bluetooth sound disconnect <sound>
/ccbell:bluetooth test                # Test Bluetooth sounds
```

### Output

```
$ ccbell:bluetooth status

=== Sound Event Bluetooth Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Adapter Sounds: Yes

Watched Devices: 2

[1] AirPods Pro
    Address: AA:BB:CC:DD:EE:FF
    Type: audio
    Status: CONNECTED
    Battery: 85%
    Sound: bundled:bt-airpods

[2] Magic Keyboard
    Address: 11:22:33:44:55:66
    Type: input
    Status: CONNECTED
    Sound: bundled:bt-keyboard

[3] Sony WH-1000XM4
    Address: FF:EE:DD:CC:BB:AA
    Type: audio
    Status: DISCONNECTED
    Sound: bundled:bt-headphones

Recent Events:
  [1] AirPods Pro: Device Connected (5 min ago)
       Connected to MacBook Pro
  [2] Sony WH-1000XM4: Device Disconnected (10 min ago)
       Out of range
  [3] Magic Keyboard: Device Connected (1 hour ago)
       Paired successfully

Bluetooth Statistics:
  Total paired: 5
  Connected: 2
  Disconnections today: 3

Sound Settings:
  Connect: bundled:bt-connect
  Disconnect: bundled:bt-disconnect
  Adapter: bundled:bt-adapter

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Bluetooth monitoring doesn't play sounds directly:
- Monitoring feature using bluetoothctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Bluetooth Monitor

```go
type BluetoothMonitor struct {
    config          *BluetoothMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*BluetoothDeviceInfo
    lastEventTime   map[string]time.Time
}

type BluetoothDeviceInfo struct {
    Name      string
    Address   string
    Type      string
    Connected bool
    Battery   int
    Trusted   bool
}

func (m *BluetoothMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*BluetoothDeviceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *BluetoothMonitor) monitor() {
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

func (m *BluetoothMonitor) snapshotDeviceState() {
    cmd := exec.Command("bluetoothctl", "devices")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDevicesOutput(string(output))

    // Check connected devices
    m.checkConnectedDevices()
}

func (m *BluetoothMonitor) checkDeviceState() {
    // List devices
    cmd := exec.Command("bluetoothctl", "devices")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentDevices := m.parseDevicesOutput(string(output))

    // Check connected status
    m.checkConnectedDevices()

    // Check for changes
    for key, info := range currentDevices {
        lastInfo := m.deviceState[key]
        if lastInfo == nil {
            m.deviceState[key] = info
            m.onDeviceAdded(info)
            continue
        }

        if lastInfo.Connected != info.Connected {
            if info.Connected {
                m.onDeviceConnected(info)
            } else {
                m.onDeviceDisconnected(lastInfo)
            }
        }

        m.deviceState[key] = info
    }

    // Check for removed devices
    for key, lastInfo := range m.deviceState {
        if _, exists := currentDevices[key]; !exists {
            delete(m.deviceState, key)
            m.onDeviceRemoved(lastInfo)
        }
    }
}

func (m *BluetoothMonitor) parseDevicesOutput(output string) map[string]*BluetoothDeviceInfo {
    devices := make(map[string]*BluetoothDeviceInfo)

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse: "Device AA:BB:CC:DD:EE:FF Device Name"
        parts := strings.SplitN(line, " ", 3)
        if len(parts) < 3 {
            continue
        }

        address := parts[1]
        name := parts[2]

        if !m.shouldWatchDevice(name) {
            continue
        }

        devices[address] = &BluetoothDeviceInfo{
            Name:    name,
            Address: address,
        }
    }

    return devices
}

func (m *BluetoothMonitor) checkConnectedDevices() {
    cmd := exec.Command("bluetoothctl", "info")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    var currentDevice *BluetoothDeviceInfo
    var currentAddress string

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Device") {
            parts := strings.SplitN(line, " ", 2)
            if len(parts) > 1 {
                currentAddress = parts[1]
                if info, exists := m.deviceState[currentAddress]; exists {
                    currentDevice = info
                }
            }
        }

        if currentDevice != nil {
            if strings.HasPrefix(line, "Connected: yes") {
                currentDevice.Connected = true
            } else if strings.HasPrefix(line, "Connected: no") {
                currentDevice.Connected = false
            } else if strings.HasPrefix(line, "Battery Percentage:") {
                re := regexp.MustCompile(`\(([^)]+)\)`)
                match := re.FindStringSubmatch(line)
                if match != nil {
                    currentDevice.Battery, _ = strconv.Atoi(match[1])
                }
            }
        }
    }
}

func (m *BluetoothMonitor) shouldWatchDevice(name string) bool {
    if len(m.config.WatchDevices) == 0 {
        return true
    }

    for _, d := range m.config.WatchDevices {
        if d == "*" || strings.Contains(name, d) {
            return true
        }
    }

    return false
}

func (m *BluetoothMonitor) onDeviceConnected(info *BluetoothDeviceInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    key := fmt.Sprintf("connect:%s", info.Address)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BluetoothMonitor) onDeviceDisconnected(info *BluetoothDeviceInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s", info.Address)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *BluetoothMonitor) onDeviceAdded(info *BluetoothDeviceInfo) {
    // Optional: sound when new device is paired
}

func (m *BluetoothMonitor) onDeviceRemoved(info *BluetoothDeviceInfo) {
    // Optional: sound when device is forgotten
}

func (m *BluetoothMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| bluetoothctl | System Tool | Free | Bluetooth management |
| bluez | System Service | Free | Linux Bluetooth stack |

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
| Linux | Supported | Uses bluetoothctl, bluez |
