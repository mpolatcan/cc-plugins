# Feature: Sound Event USB Device Monitor

Play sounds for USB device connections and disconnections.

## Summary

Monitor USB device additions, removals, and device property changes, playing sounds for USB device events.

## Motivation

- Hardware awareness
- Device detection
- Security monitoring
- Peripheral tracking
- Device driver loading

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### USB Device Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | USB device attached | USB flash drive |
| Device Disconnected | USB device removed | USB drive unplugged |
| Device Changed | Device properties changed | Speed changed |
| Driver Loaded | Driver module loaded | usb-storage loaded |
| Too Much Power | Power draw warning | 900mA draw |

### Configuration

```go
type USBDeviceMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchDevices       []string          `json:"watch_devices"` // "usb", "scsi", "*"
    WatchVendors       []string          `json:"watch_vendors"` // "0x0781" (SanDisk)
    SoundOnConnect     bool              `json:"sound_on_connect"`
    SoundOnDisconnect  bool              `json:"sound_on_disconnect"`
    SoundOnDriver      bool              `json:"sound_on_driver"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type USBDeviceEvent struct {
    Device      string
    Vendor      string
    Product     string
    Serial      string
    Speed       string // "480M", "5000M"
    Power       int // mA
    Driver      string
    EventType   string // "connect", "disconnect", "change", "driver"
}
```

### Commands

```bash
/ccbell:usb status                    # Show USB status
/ccbell:usb add 0x0781                # Add vendor to watch
/ccbell:usb remove 0x0781
/ccbell:usb sound connect <sound>
/ccbell:usb sound disconnect <sound>
/ccbell:usb test                      # Test USB sounds
```

### Output

```
$ ccbell:usb status

=== Sound Event USB Device Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Watched Devices: 2
Watched Vendors: 1

USB Devices:

[1] SanDisk Ultra
    Device: /dev/sdb1
    Vendor: 0x0781
    Product: 0x558a
    Serial: 4C530001241205118142
    Speed: 5G
    Sound: bundled:usb-storage

[2] Logitech MX Master
    Device: /dev/input/mouse1
    Vendor: 0x046d
    Product: 0xb02a
    Speed: 12M
    Sound: bundled:usb-mouse

[3] USB Audio
    Device: /dev/snd/pcmC1D0p
    Vendor: 0x0d8c
    Product: 0x0014
    Speed: 480M
    Sound: bundled:usb-audio

Recent Events:
  [1] SanDisk Ultra: Device Connected (5 min ago)
       USB 3.0 flash drive attached
  [2] Logitech MX Master: Device Connected (1 hour ago)
       Wireless mouse connected
  [3] USB Audio: Device Disconnected (2 hours ago)
       Audio device removed

USB Statistics:
  Total devices: 15
  Connected: 12
  Disconnected today: 3

Sound Settings:
  Connect: bundled:usb-connect
  Disconnect: bundled:usb-disconnect
  Driver: bundled:usb-driver

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

USB device monitoring doesn't play sounds directly:
- Monitoring feature using lsusb/system_profiler
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### USB Device Monitor

```go
type USBDeviceMonitor struct {
    config          *USBDeviceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*USBDeviceInfo
    lastEventTime   map[string]time.Time
}

type USBDeviceInfo struct {
    DevicePath  string
    VendorID    string
    ProductID   string
    VendorName  string
    ProductName string
    Serial      string
    Speed       string
    Power       int // mA
    Driver      string
    ConnectedAt time.Time
}

func (m *USBDeviceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*USBDeviceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *USBDeviceMonitor) monitor() {
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

func (m *USBDeviceMonitor) snapshotDeviceState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinDevices()
    } else {
        m.snapshotLinuxDevices()
    }
}

func (m *USBDeviceMonitor) snapshotLinuxDevices() {
    cmd := exec.Command("lsusb")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLSUSBOutput(string(output))
}

func (m *USBDeviceMonitor) parseLSUSBOutput(output string) {
    lines := strings.Split(output, "\n")
    currentDevices := make(map[string]*USBDeviceInfo)

    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse: "Bus 001 Device 003: ID 0781:558a SanDisk Ultra"
        re := regexp.MustCompile(`Bus (\d+) Device (\d+): ID ([0-9a-f:]+) (.+)`)
        match := re.FindStringSubmatch(line)
        if match == nil {
            continue
        }

        bus := match[1]
        deviceNum := match[2]
        deviceID := match[3]
        deviceName := match[4]

        parts := strings.Split(deviceID, ":")
        vendorID := parts[0]
        productID := parts[1]

        if !m.shouldWatchDevice(vendorID, productID) {
            continue
        }

        key := fmt.Sprintf("%s-%s", bus, deviceNum)

        // Get more details
        info := m.getUSBDeviceDetails(bus, deviceNum)
        if info == nil {
            info = &USBDeviceInfo{
                DevicePath: fmt.Sprintf("/dev/bus/usb/%s/%s", bus, deviceNum),
                VendorID:   vendorID,
                ProductID:  productID,
            }
        }

        info.VendorName = deviceName
        currentDevices[key] = info

        lastInfo := m.deviceState[key]
        if lastInfo == nil {
            m.deviceState[key] = info
            m.onDeviceConnected(info)
        }
    }

    // Check for disconnected devices
    for key, lastInfo := range m.deviceState {
        if _, exists := currentDevices[key]; !exists {
            delete(m.deviceState, key)
            m.onDeviceDisconnected(lastInfo)
        }
    }
}

func (m *USBDeviceMonitor) getUSBDeviceDetails(bus, deviceNum string) *USBDeviceInfo {
    path := fmt.Sprintf("/sys/bus/usb/devices/%s-%s", bus, deviceNum)
    info := &USBDeviceInfo{
        DevicePath: fmt.Sprintf("/dev/bus/usb/%s/%s", bus, deviceNum),
    }

    // Read vendor and product names
    vendorPath := filepath.Join(path, "manufacturer")
    if data, err := os.ReadFile(vendorPath); err == nil {
        info.VendorName = strings.TrimSpace(string(data))
    }

    productPath := filepath.Join(path, "product")
    if data, err := os.ReadFile(productPath); err == nil {
        info.ProductName = strings.TrimSpace(string(data))
    }

    serialPath := filepath.Join(path, "serial")
    if data, err := os.ReadFile(serialPath); err == nil {
        info.Serial = strings.TrimSpace(string(data))
    }

    speedPath := filepath.Join(path, "speed")
    if data, err := os.ReadFile(speedPath); err == nil {
        info.Speed = strings.TrimSpace(string(data))
    }

    // Get power
    powerPath := filepath.Join(path, "power/active_duration")
    if data, err := os.ReadFile(powerPath); err == nil {
        info.Power, _ = strconv.Atoi(strings.TrimSpace(string(data)))
    }

    return info
}

func (m *USBDeviceMonitor) snapshotDarwinDevices() {
    cmd := exec.Command("system_profiler", "SPUSBDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse JSON output
    // This is a simplified approach
}

func (m *USBDeviceMonitor) shouldWatchDevice(vendorID, productID string) bool {
    if len(m.config.WatchDevices) == 0 && len(m.config.WatchVendors) == 0 {
        return true
    }

    for _, v := range m.config.WatchVendors {
        if v == vendorID || v == "0x"+vendorID {
            return true
        }
    }

    return false
}

func (m *USBDeviceMonitor) onDeviceConnected(info *USBDeviceInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    key := fmt.Sprintf("connect:%s:%s", info.VendorID, info.ProductID)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *USBDeviceMonitor) onDeviceDisconnected(info *USBDeviceInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s:%s", info.VendorID, info.ProductID)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *USBDeviceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| lsusb | System Tool | Free | USB device listing |
| system_profiler | System Tool | Free | macOS hardware info |
| /sys/bus/usb/devices/* | Filesystem | Free | USB sysfs |

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
| Linux | Supported | Uses lsusb, sysfs |
