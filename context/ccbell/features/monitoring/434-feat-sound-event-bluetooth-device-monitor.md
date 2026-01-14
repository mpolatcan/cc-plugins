# Feature: Sound Event Bluetooth Device Monitor

Play sounds for Bluetooth device connections, disconnections, and battery level changes.

## Summary

Monitor Bluetooth devices for connection status, pairing events, and battery updates, playing sounds for Bluetooth events.

## Motivation

- Bluetooth awareness
- Device connection feedback
- Battery level alerts
- Pairing detection
- Device tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Bluetooth Device Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | Paired device connected | AirPods |
| Device Disconnected | Device disconnected | AirPods |
| Device Paired | New pairing | New device |
| Battery Low | Battery < threshold | < 20% |
| Device Found | Discovery mode | scanning |
| Connected Nearby | Device in range | near |

### Configuration

```go
type BluetoothDeviceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDevices      []string          `json:"watch_devices"` // "AirPods", "*"
    BatteryWarning    int               `json:"battery_warning"` // 20 default
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnBattery    bool              `json:"sound_on_battery"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:bluetooth status             # Show bluetooth status
/ccbell:bluetooth add "AirPods"      # Add device to watch
/ccbell:bluetooth battery 20         # Set battery warning
/ccbell:bluetooth sound connect <sound>
/ccbell:bluetooth sound disconnect <sound>
/ccbell:bluetooth test               # Test bluetooth sounds
```

### Output

```
$ ccbell:bluetooth status

=== Sound Event Bluetooth Device Monitor ===

Status: Enabled
Battery Warning: 20%

Bluetooth Status:
  Power: ON
  Adapters: 1
  Discoverable: No
  Devices Paired: 5

Watched Devices:

[1] AirPods Pro
    Status: CONNECTED
    Connected: Yes
    Battery: 45%
    Last Connected: 2 hours ago
    Sound: bundled:bt-airpods

[2] Magic Keyboard
    Status: CONNECTED
    Connected: Yes
    Battery: 78%
    Last Connected: 1 day ago
    Sound: bundled:bt-keyboard

[3] Magic Mouse
    Status: DISCONNECTED *** DISCONNECTED ***
    Battery: 15% *** LOW BATTERY ***
    Last Connected: 3 days ago
    Sound: bundled:bt-mouse *** WARNING ***

[4] Sony WH-1000XM4
    Status: DISCONNECTED
    Connected: No
    Battery: 85%
    Last Connected: 1 week ago
    Sound: bundled:bt-headphones

[5] Apple Watch
    Status: CONNECTED
    Connected: Yes
    Battery: 92%
    Last Connected: Just now
    Sound: bundled:bt-watch

Recent Bluetooth Events:
  [1] Magic Mouse: Battery Low (1 hour ago)
       15% remaining
       Sound: bundled:bt-battery
  [2] AirPods Pro: Connected (2 hours ago)
       Range: Connected
       Sound: bundled:bt-connect
  [3] Sony WH-1000XM4: Disconnected (3 days ago)
       Out of range
       Sound: bundled:bt-disconnect

Bluetooth Statistics:
  Total Devices: 5
  Connected: 3
  Low Battery: 1

Sound Settings:
  Connect: bundled:bt-connect
  Disconnect: bundled:bt-disconnect
  Battery: bundled:bt-battery
  Paired: bundled:bt-paired

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Bluetooth monitoring doesn't play sounds directly:
- Monitoring feature using blueutil/system_profiler
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
    deviceState     map[string]*BluetoothDeviceInfo
    lastEventTime   map[string]time.Time
}

type BluetoothDeviceInfo struct {
    Name        string
    Address     string
    Connected   bool
    Paired      bool
    Battery     int
    LastSeen    time.Time
    LastConnected time.Time
}

func (m *BluetoothDeviceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*BluetoothDeviceInfo)
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
    m.checkDeviceState()
}

func (m *BluetoothDeviceMonitor) checkDeviceState() {
    devices := m.listBluetoothDevices()

    for _, device := range devices {
        if !m.shouldWatchDevice(device.Name) {
            continue
        }
        m.processDeviceStatus(device)
    }
}

func (m *BluetoothDeviceMonitor) listBluetoothDevices() []*BluetoothDeviceInfo {
    if runtime.GOOS == "darwin" {
        return m.listDarwinBluetoothDevices()
    }
    return m.listLinuxBluetoothDevices()
}

func (m *BluetoothDeviceMonitor) listDarwinBluetoothDevices() []*BluetoothDeviceInfo {
    var devices []*BluetoothDeviceInfo

    // Use system_profiler for Bluetooth info
    cmd := exec.Command("system_profiler", "SPBluetoothDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    outputStr := string(output)

    // Extract paired devices
    re := regexp.MustEach(`"name":\s*"([^"]+)"`)
    matches := re.FindAllStringSubmatch(outputStr, -1)

    pairedNames := make(map[string]bool)
    for _, match := range matches {
        if len(match) >= 2 {
            pairedNames[match[1]] = true
        }
    }

    // Check blueutil for connected devices
    if m.commandExists("blueutil") {
        cmd = exec.Command("blueutil", "--paired")
        output, _ = cmd.Output()
        outputStr = string(output)

        for _, line := range strings.Split(outputStr, "\n") {
            if strings.TrimSpace(line) == "" {
                continue
            }

            device := &BluetoothDeviceInfo{
                Name:   strings.TrimSpace(line),
                Paired: true,
                Connected: false,
            }

            // Check if connected
            cmd = exec.Command("blueutil", "--connected")
            connOutput, _ := cmd.Output()
            if strings.Contains(string(connOutput), device.Name) {
                device.Connected = true
            }

            // Get battery if available (limited on macOS)
            cmd = exec.Command("blueutil", "--info", device.Name)
            infoOutput, _ := cmd.Output()
            infoStr := string(infoOutput)

            batteryRe := regexp.MustEach(`battery:\s*(\d+)`)
            batteryMatch := batteryRe.FindStringSubmatch(infoStr)
            if len(batteryMatch) >= 2 {
                device.Battery, _ = strconv.Atoi(batteryMatch[1])
            }

            devices = append(devices, device)
        }
    }

    // Also check via system_profiler for devices not found by blueutil
    for name := range pairedNames {
        found := false
        for _, device := range devices {
            if device.Name == name {
                found = true
                break
            }
        }
        if !found {
            device := &BluetoothDeviceInfo{
                Name:    name,
                Paired:  true,
                Battery: -1, // Unknown
            }
            devices = append(devices, device)
        }
    }

    return devices
}

func (m *BluetoothDeviceMonitor) listLinuxBluetoothDevices() []*BluetoothDeviceInfo {
    var devices []*BluetoothDeviceInfo

    // Use bluetoothctl for Bluetooth info
    if !m.commandExists("bluetoothctl") {
        return devices
    }

    // List paired devices
    cmd := exec.Command("bluetoothctl", "--paired")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Device") {
            // Parse: Device XX:XX:XX:XX:XX:XX Device Name
            parts := strings.SplitN(line, " ", 3)
            if len(parts) >= 3 {
                address := parts[1]
                name := strings.TrimSpace(parts[2])

                device := &BluetoothDeviceInfo{
                    Name:    name,
                    Address: address,
                    Paired:  true,
                }

                // Check if connected
                cmd = exec.Command("bluetoothctl", "--info", address)
                infoOutput, _ := cmd.Output()
                infoStr := string(infoOutput)

                if strings.Contains(infoStr, "Connected: yes") {
                    device.Connected = true
                }

                // Get battery if available
                batteryRe := regexp.MustEach(`BatteryPercentage:\s*(\d+)`)
                batteryMatch := batteryRe.FindStringSubmatch(infoStr)
                if len(batteryMatch) >= 2 {
                    device.Battery, _ = strconv.Atoi(batteryMatch[1])
                }

                devices = append(devices, device)
            }
        }
    }

    return devices
}

func (m *BluetoothDeviceMonitor) commandExists(cmd string) bool {
    _, err := exec.LookPath(cmd)
    return err == nil
}

func (m *BluetoothDeviceMonitor) shouldWatchDevice(name string) bool {
    if len(m.config.WatchDevices) == 0 {
        return true
    }

    for _, d := range m.config.WatchDevices {
        if d == "*" || name == d || strings.Contains(strings.ToLower(name), strings.ToLower(d)) {
            return true
        }
    }

    return false
}

func (m *BluetoothDeviceMonitor) processDeviceStatus(device *BluetoothDeviceInfo) {
    lastInfo := m.deviceState[device.Name]

    if lastInfo == nil {
        m.deviceState[device.Name] = device
        if device.Connected && m.config.SoundOnConnect {
            m.onDeviceConnected(device)
        }
        return
    }

    // Check for connection changes
    if device.Connected != lastInfo.Connected {
        if device.Connected {
            if m.config.SoundOnConnect {
                m.onDeviceConnected(device)
            }
            device.LastConnected = time.Now()
        } else {
            if m.config.SoundOnDisconnect {
                m.onDeviceDisconnected(device)
            }
        }
    }

    // Check for battery warnings
    if device.Battery > 0 && device.Battery < m.config.BatteryWarning {
        if lastInfo.Battery == 0 || lastInfo.Battery >= m.config.BatteryWarning {
            if m.config.SoundOnBattery {
                m.onBatteryLow(device)
            }
        }
    }

    device.LastSeen = time.Now()
    m.deviceState[device.Name] = device
}

func (m *BluetoothDeviceMonitor) onDeviceConnected(device *BluetoothDeviceInfo) {
    key := fmt.Sprintf("connect:%s", device.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BluetoothDeviceMonitor) onDeviceDisconnected(device *BluetoothDeviceInfo) {
    key := fmt.Sprintf("disconnect:%s", device.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BluetoothDeviceMonitor) onBatteryLow(device *BluetoothDeviceInfo) {
    key := fmt.Sprintf("battery:%s", device.Name)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["battery"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
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
| blueutil | System Tool | Free | Bluetooth control (macOS) |
| bluetoothctl | System Tool | Free | Bluetooth control (Linux) |
| system_profiler | System Tool | Free | macOS system profiler |

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
| macOS | Supported | Uses blueutil, system_profiler |
| Linux | Supported | Uses bluetoothctl |
