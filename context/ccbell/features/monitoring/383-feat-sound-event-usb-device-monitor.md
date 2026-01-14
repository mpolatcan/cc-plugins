# Feature: Sound Event USB Device Monitor

Play sounds for USB device connections, disconnections, and device changes.

## Summary

Monitor USB bus for device insertions, removals, and device property changes, playing sounds for USB events.

## Motivation

- Hardware awareness
- Security monitoring
- Device hot-plug detection
- Storage device tracking
- Peripheral management

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
| Device Connected | USB device inserted | flash drive |
| Device Disconnected | USB device removed | unplugged |
| Storage Mounted | Mounted as storage | /dev/sda1 |
| Storage Unmounted | Ejected safely | unmount |
| High Power | Power negotiation | 900mA |
| Device Changed | Property changed | mode change |

### Configuration

```go
type USBDeviceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchVendors      []string          `json:"watch_vendors"` // "Apple", "Samsung"
    WatchTypes        []string          `json:"watch_types"` // "storage", "hid", "audio"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnMount      bool              `json:"sound_on_mount"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:usb status                     # Show USB status
/ccbell:usb add vendor Apple           # Add vendor to watch
/ccbell:usb remove vendor Apple
/ccbell:usb sound connect <sound>
/ccbell:usb sound disconnect <sound>
/ccbell:usb test                       # Test USB sounds
```

### Output

```
$ ccbell:usb status

=== Sound Event USB Device Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Mount Sounds: Yes

Watched Vendors: 2
Watched Types: 2

USB Devices:

[1] USB3.0 Flash Drive (Sandisk)
    VID: 0x0781
    PID: 0x558a
    Serial: XXX123
    Speed: 5 Gbps
    Connected: 5 min ago
    Sound: bundled:usb-flash

[2] Apple Magic Mouse
    VID: 0x05AC
    PID: 0x0269
    Serial: ABC123
    Speed: 12 Mbps
    Connected: 2 hours ago
    Sound: bundled:usb-mouse

[3] USB Hub
    VID: 0x1A40
    PID: 0x0201
    Ports: 4
    Connected: 1 day ago
    Sound: bundled:usb-hub

Recent Events:
  [1] USB3.0 Flash Drive: Connected (5 min ago)
       Vendor: Sandisk
  [2] Apple Magic Mouse: Disconnected (1 hour ago)
       Battery replaced
  [3] USB3.0 Flash Drive: Mounted (4 min ago)
       /media/user/USB3.0

USB Statistics:
  Devices Today: 8
  Connections: 6
  Disconnections: 4

Sound Settings:
  Connect: bundled:usb-connect
  Disconnect: bundled:usb-disconnect
  Mount: bundled:usb-mount

[Configure] [Add Vendor] [Test All]
```

---

## Audio Player Compatibility

USB monitoring doesn't play sounds directly:
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
    VendorID   string
    ProductID  string
    Vendor     string
    Product    string
    Serial     string
    Speed      string
    Connected  bool
    Mounted    bool
    MountPoint string
    LastSeen   time.Time
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
    m.listDevices()
}

func (m *USBDeviceMonitor) checkDeviceState() {
    currentDevices := m.listDevices()

    for id, device := range currentDevices {
        lastDevice := m.deviceState[id]

        if lastDevice == nil {
            m.deviceState[id] = device
            m.onDeviceConnected(device)
            continue
        }

        // Device was already known
        m.deviceState[id] = device
    }

    // Check for removed devices
    for id, lastDevice := range m.deviceState {
        if _, exists := currentDevices[id]; !exists {
            delete(m.deviceState, id)
            m.onDeviceDisconnected(lastDevice)
        }
    }
}

func (m *USBDeviceMonitor) listDevices() map[string]*USBDeviceInfo {
    devices := make(map[string]*USBDeviceInfo)

    cmd := exec.Command("lsusb")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        // Parse: "Bus 001 Device 001: ID 1234:5678 Device Name"
        re := regexp.MustCompile(`Bus (\d+) Device (\d+): ID ([0-9A-Fa-f]+):([0-9A-Fa-f]+) (.*)`)
        match := re.FindStringSubmatch(line)
        if match == nil {
            continue
        }

        bus := match[1]
        devNum := match[2]
        vid := match[3]
        pid := match[4]
        name := strings.TrimSpace(match[5])

        id := fmt.Sprintf("%s-%s-%s", bus, devNum, vid+":"+pid)

        device := &USBDeviceInfo{
            VendorID:  vid,
            ProductID: pid,
            Product:   name,
            Connected: true,
            LastSeen:  time.Now(),
        }

        // Get more details
        details := m.getDeviceDetails(vid, pid)
        if details != nil {
            device.Vendor = details.Vendor
            device.Serial = details.Serial
            device.Speed = details.Speed
        }

        devices[id] = device
    }

    return devices
}

func (m *USBDeviceMonitor) getDeviceDetails(vid, pid string) *USBDeviceInfo {
    // Use udevadm for detailed info
    cmd := exec.Command("udevadm", "info", "--query=all",
        fmt.Sprintf("/sys/bus/usb/devices/%s:%s", vid, pid))
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &USBDeviceInfo{VendorID: vid, ProductID: pid}

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "ID_VENDOR=") {
            info.Vendor = strings.TrimPrefix(line, "ID_VENDOR=")
        } else if strings.Contains(line, "ID_SERIAL=") {
            info.Serial = strings.TrimPrefix(line, "ID_SERIAL=")
        } else if strings.Contains(line, "ID_SPEED=") {
            info.Speed = strings.TrimPrefix(line, "ID_SPEED=")
        }
    }

    return info
}

func (m *USBDeviceMonitor) onDeviceConnected(device *USBDeviceInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    if !m.shouldWatchVendor(device.Vendor) {
        return
    }

    key := fmt.Sprintf("connect:%s:%s", device.VendorID, device.ProductID)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *USBDeviceMonitor) onDeviceDisconnected(device *USBDeviceInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s:%s", device.VendorID, device.ProductID)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *USBDeviceMonitor) shouldWatchVendor(vendor string) bool {
    if len(m.config.WatchVendors) == 0 {
        return true
    }

    for _, v := range m.config.WatchVendors {
        if strings.Contains(strings.ToLower(vendor), strings.ToLower(v)) {
            return true
        }
    }

    return false
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
| udevadm | System Tool | Free | Device management |
| system_profiler | System Tool | Free | macOS hardware info |

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
| Linux | Supported | Uses lsusb, udevadm |
