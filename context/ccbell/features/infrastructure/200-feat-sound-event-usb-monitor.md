# Feature: Sound Event USB Monitor

Play sounds for USB device events.

## Summary

Play sounds when USB devices are connected or disconnected.

## Motivation

- Device awareness
- Security alerts
- Peripheral notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### USB Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | USB plugged in | Flash drive |
| Device Disconnected | USB removed | Flash drive |
| Device Type | Device category | Storage, audio |
| Unknown Device | Unrecognized device | Security alert |

### Configuration

```go
type USBMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchTypes    []string          `json:"watch_types"` // "storage", "audio", "hid"
    IgnoreDevices []string          `json:"ignore_devices"` // Device names to ignore
    Sounds        map[string]string `json:"sounds"`
    AlertUnknown  bool              `json:"alert_unknown"` // Alert on unrecognized devices
}

type USBDevice struct {
    ID           string
    Name         string
    Vendor       string
    Product      string
    Type         string // "storage", "audio", "hid", "other"
    Serial       string
    ConnectedAt  time.Time
}
```

### Commands

```bash
/ccbell:usb status                  # Show USB status
/ccbell:usb list                    # List connected devices
/ccbell:usb sound connected <sound>
/ccbell:usb sound disconnected <sound>
/ccbell:usb sound storage <sound>
/ccbell:usb sound unknown <sound>
/ccbell:usb watch storage           # Watch storage devices
/ccbell:usb ignore "Apple Keyboard"
/ccbell:usb enable alert_unknown    # Enable unknown device alerts
/ccbell:usb test                    # Test USB sounds
```

### Output

```
$ ccbell:usb status

=== Sound Event USB Monitor ===

Status: Enabled

Connected Devices: 5

[1] SanDisk Ultra
    Type: storage
    Serial: 123456789ABC
    Connected: 2 hours ago
    Sound: bundled:stop
    [Ignore]

[2] Apple Keyboard
    Type: hid
    Serial: DEF456GHI789
    Connected: 1 week ago
    Ignored
    [Unignore]

[3] USB Audio Device
    Type: audio
    Serial: JKL012MNO345
    Connected: 3 days ago
    Sound: bundled:stop
    [Ignore]

Watch Types: [storage, audio, hid]
Alert Unknown: Disabled

Recent Events:
  [1] SanDisk Ultra: Connected (2 hours ago)
  [2] USB Audio Device: Connected (3 days ago)

[Configure] [List] [Test All]
```

---

## Audio Player Compatibility

USB monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### USB Monitor

```go
type USBMonitor struct {
    config   *USBMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastDevices map[string]*USBDevice
}

func (m *USBMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastDevices = make(map[string]*USBDevice)
    go m.monitor()
}

func (m *USBMonitor) monitor() {
    ticker := time.NewTicker(5 * time.Second)
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

func (m *USBMonitor) checkDevices() {
    devices := m.listUSBDevices()
    deviceMap := make(map[string]*USBDevice)

    for _, dev := range devices {
        deviceMap[dev.ID] = dev
    }

    // Check for new devices
    for id, dev := range deviceMap {
        if _, exists := m.lastDevices[id]; !exists {
            m.onDeviceConnected(dev)
        }
    }

    // Check for disconnected devices
    for id, lastDev := range m.lastDevices {
        if _, exists := deviceMap[id]; !exists {
            m.onDeviceDisconnected(lastDev)
        }
    }

    m.lastDevices = deviceMap
}

func (m *USBMonitor) listUSBDevices() []*USBDevice {
    var devices []*USBDevice

    // Linux: Read from sysfs
    usbPath := "/sys/bus/usb/devices"
    filepath.Walk(usbPath, func(path string, info os.FileInfo, err error) error {
        if err != nil || !info.IsDir() {
            return nil
        }

        // Check if this is a device (has idVendor and idProduct)
        vendorPath := filepath.Join(path, "idVendor")
        productPath := filepath.Join(path, "idProduct")

        if _, err := os.Stat(vendorPath); err == nil {
            vendor, _ := os.ReadFile(vendorPath)
            product, _ := os.ReadFile(productPath)

            if len(vendor) > 0 && len(product) > 0 {
                dev := &USBDevice{
                    ID:      path,
                    Vendor:  strings.TrimSpace(string(vendor)),
                    Product: strings.TrimSpace(string(product)),
                }

                // Get device name
                if name, err := os.ReadFile(filepath.Join(path, "manufacturer")); err == nil {
                    dev.Name = strings.TrimSpace(string(name))
                }

                // Determine type
                dev.Type = m.detectDeviceType(path)

                devices = append(devices, dev)
            }
        }

        return nil
    })

    return devices
}

func (m *USBMonitor) detectDeviceType(path string) string {
    // Check for storage (has block devices)
    if _, err := os.Stat(filepath.Join(path, "block")); err == nil {
        return "storage"
    }

    // Check for audio
    if strings.Contains(path, "audio") {
        return "audio"
    }

    // Check for HID (human interface device)
    if _, err := os.Stat(filepath.Join(path, "hid")); err == nil {
        return "hid"
    }

    return "other"
}

func (m *USBMonitor) onDeviceConnected(device *USBDevice) {
    // Check if should alert
    if m.isIgnored(device) {
        return
    }

    // Check device type
    if len(m.config.WatchTypes) > 0 {
        if !contains(m.config.WatchTypes, device.Type) {
            return
        }
    }

    // Unknown device alert
    if m.config.AlertUnknown && device.Type == "other" {
        m.playUSBEvent("unknown", m.config.Sounds["unknown"])
    } else {
        m.playUSBEvent("connected", m.config.Sounds["connected"])
    }
}

func (m *USBMonitor) onDeviceDisconnected(device *USBDevice) {
    if m.isIgnored(device) {
        return
    }

    m.playUSBEvent("disconnected", m.config.Sounds["disconnected"])
}

func (m *USBMonitor) isIgnored(device *USBDevice) bool {
    for _, name := range m.config.IgnoreDevices {
        if strings.Contains(device.Name, name) {
            return true
        }
    }
    return false
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /sys/bus/usb | Filesystem | Free | Linux USB info |

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
| Linux | ✅ Supported | Uses /sys/bus/usb |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
