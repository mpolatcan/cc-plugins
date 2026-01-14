# Feature: Sound Event Bluetooth Device Monitor

Play sounds for Bluetooth device connections, disconnections, and discovery events.

## Summary

Monitor Bluetooth devices for connect/disconnect events, pairing, and discovery, playing sounds for Bluetooth events.

## Motivation

- Device connection awareness
- Wireless peripheral tracking
- Security awareness
- Audio device switching
- Proximity detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Bluetooth Device Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | Device paired | headphones |
| Device Disconnected | Device lost | out of range |
| Discovery Started | Scanning | bt scan on |
| Discovery Stopped | Scan ended | bt scan off |
| Battery Low | Low battery | < 20% |
| Device Paired | New pairing | trust established |

### Configuration

```go
type BluetoothDeviceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDevices      []string          `json:"watch_devices"` // "AirPods", "*"
    WatchTypes        []string          `json:"watch_types"` // "headset", "keyboard", "mouse"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnBattery    bool              `json:"sound_on_battery"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:bluetooth status               # Show Bluetooth status
/ccbell:bluetooth add "AirPods"        # Add device to watch
/ccbell:bluetooth remove "AirPods"
/ccbell:bluetooth sound connect <sound>
/ccbell:bluetooth sound disconnect <sound>
/ccbell:bluetooth test                 # Test Bluetooth sounds
```

### Output

```
$ ccbell:bluetooth status

=== Sound Event Bluetooth Device Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Battery Sounds: Yes

Watched Devices: 3
Watched Types: 2

Connected Devices:

[1] AirPods Pro (XX:XX:XX:XX:XX:XX)
    Status: Connected
    Battery: 85%
    Type: headset
    Last Connected: 2 hours ago
    Sound: bundled:bt-airpods

[2] Magic Keyboard (YY:YY:YY:YY:YY:YY)
    Status: Connected
    Battery: 45%
    Type: keyboard
    Last Connected: 1 day ago
    Sound: bundled:bt-keyboard

[3] MX Master 3 (ZZ:ZZ:ZZ:ZZ:ZZ:ZZ)
    Status: Disconnected
    Battery: 30%
    Type: mouse
    Last Connected: 3 days ago
    Sound: bundled:bt-mouse

Recent Events:
  [1] AirPods Pro: Connected (2 hours ago)
       Battery: 85%
  [2] MX Master 3: Disconnected (1 day ago)
       Out of range
  [3] Magic Keyboard: Battery Low (2 days ago)
       45% remaining

Bluetooth Statistics:
  Total Connections: 25
  Disconnections: 10
  Low Battery Alerts: 3

Sound Settings:
  Connect: bundled:bt-connect
  Disconnect: bundled:bt-disconnect
  Battery: bundled:bt-battery

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

### Bluetooth Device Monitor

```go
type BluetoothDeviceMonitor struct {
    config          *BluetoothDeviceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*DeviceInfo
    lastEventTime   map[string]time.Time
}

type DeviceInfo struct {
    Name       string
    Address    string
    Connected  bool
    Paired     bool
    Battery    int // percentage, -1 if unknown
    DeviceType string
    LastSeen   time.Time
}

func (m *BluetoothDeviceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*DeviceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *BluetoothDeviceMonitor) monitor() {
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

func (m *BluetoothDeviceMonitor) snapshotDeviceState() {
    m.listDevices()
}

func (m *BluetoothDeviceMonitor) checkDeviceState() {
    currentDevices := m.listDevices()

    for addr, device := range currentDevices {
        lastDevice := m.deviceState[addr]

        if lastDevice == nil {
            m.deviceState[addr] = device
            if device.Connected {
                m.onDeviceConnected(device)
            }
            continue
        }

        // Check connection state change
        if device.Connected && !lastDevice.Connected {
            m.onDeviceConnected(device)
        } else if !device.Connected && lastDevice.Connected {
            m.onDeviceDisconnected(device, lastDevice)
        }

        // Check battery level
        if device.Battery >= 0 && device.Battery < lastDevice.Battery && device.Battery <= 20 {
            if m.config.SoundOnBattery {
                m.onLowBattery(device)
            }
        }

        m.deviceState[addr] = device
    }

    // Check for removed devices
    for addr, lastDevice := range m.deviceState {
        if _, exists := currentDevices[addr]; !exists {
            delete(m.deviceState, addr)
            if lastDevice.Connected {
                m.onDeviceDisconnected(lastDevice, lastDevice)
            }
        }
    }
}

func (m *BluetoothDeviceMonitor) listDevices() map[string]*DeviceInfo {
    devices := make(map[string]*DeviceInfo)

    cmd := exec.Command("bluetoothctl", "devices")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        // Parse: "Device XX:XX:XX:XX:XX:XX Device Name"
        re := regexp.MustCompile(`Device ([0-9A-F:]+) (.+)`)
        match := re.FindStringSubmatch(line)
        if match == nil {
            continue
        }

        addr := match[1]
        name := match[2]

        info := &DeviceInfo{
            Name:    name,
            Address: addr,
            LastSeen: time.Now(),
        }

        // Get device info
        deviceInfo := m.getDeviceInfo(addr)
        if deviceInfo != nil {
            info.Connected = deviceInfo.Connected
            info.Paired = deviceInfo.Paired
            info.Battery = deviceInfo.Battery
            info.DeviceType = deviceInfo.DeviceType
        }

        devices[addr] = info
    }

    return devices
}

func (m *BluetoothDeviceMonitor) getDeviceInfo(addr string) *DeviceInfo {
    cmd := exec.Command("bluetoothctl", "info", addr)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &DeviceInfo{Address: addr}

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.HasPrefix(line, "Name: ") {
            info.Name = strings.TrimPrefix(line, "Name: ")
        } else if strings.HasPrefix(line, "Connected: ") {
            connected := strings.TrimPrefix(line, "Connected: ")
            info.Connected = connected == "yes"
        } else if strings.HasPrefix(line, "Paired: ") {
            paired := strings.TrimPrefix(line, "Paired: ")
            info.Paired = paired == "yes"
        } else if strings.HasPrefix(line, "Type: ") {
            info.DeviceType = strings.TrimPrefix(line, "Type: ")
        } else if strings.Contains(strings.ToLower(line), "battery") {
            // Try to parse battery level
            re := regexp.MustCompile(`(\d+)%`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                battery, _ := strconv.Atoi(match[1])
                info.Battery = battery
            }
        }
    }

    return info
}

func (m *BluetoothDeviceMonitor) onDeviceConnected(device *DeviceInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    if !m.shouldWatchDevice(device.Name) {
        return
    }

    key := fmt.Sprintf("connect:%s", device.Address)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BluetoothDeviceMonitor) onDeviceDisconnected(device *DeviceInfo, lastState *DeviceInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    if !m.shouldWatchDevice(device.Name) {
        return
    }

    key := fmt.Sprintf("disconnect:%s", device.Address)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BluetoothDeviceMonitor) onLowBattery(device *DeviceInfo) {
    key := fmt.Sprintf("battery:%s", device.Address)
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["battery"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BluetoothDeviceMonitor) shouldWatchDevice(name string) bool {
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

func (m *BluetoothDeviceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| bluez | System Package | Free | Bluetooth stack |

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
