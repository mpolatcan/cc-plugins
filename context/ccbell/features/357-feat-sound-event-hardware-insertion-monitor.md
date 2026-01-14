# Feature: Sound Event Hardware Insertion Monitor

Play sounds for hardware device insertions and driver loading events.

## Summary

Monitor hardware device insertions, hot-plug events, and driver loading, playing sounds for hardware events.

## Motivation

- Hardware awareness
- Device detection feedback
- Driver loading confirmation
- Security device alerts
- Peripheral tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Hardware Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Inserted | Hardware added | USB device inserted |
| Device Removed | Hardware removed | USB device removed |
| Driver Loaded | Kernel driver loaded | Driver installed |
| Driver Unloaded | Kernel driver removed | Driver unloaded |
| Device Ready | Device ready to use | Mounted/available |
| Hotplug Event | Udev hotplug event | Device added |

### Configuration

```go
type HardwareInsertionMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchDevices       []string          `json:"watch_devices"` // "usb", "pci", "scsi", "*"
    WatchVendors       []string          `json:"watch_vendors"` // "0x8086", "0x10de"
    SoundOnInsert      bool              `json:"sound_on_insert"`
    SoundOnRemove      bool              `json:"sound_on_remove"`
    SoundOnDriver      bool              `json:"sound_on_driver"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type HardwareEvent struct {
    Device      string
    Subsystem   string // "usb", "pci", "block"
    Vendor      string
    Model       string
    Driver      string
    Action      string // "add", "remove", "bind", "unbind"
    EventType   string // "insert", "remove", "driver", "ready"
}
```

### Commands

```bash
/ccbell:hardware status               # Show hardware status
/ccbell:hardware add usb              # Add device type to watch
/ccbell:hardware remove usb
/ccbell:hardware sound insert <sound>
/ccbell:hardware sound driver <sound>
/ccbell:hardware test                 # Test hardware sounds
```

### Output

```
$ ccbell:hardware status

=== Sound Event Hardware Insertion Monitor ===

Status: Enabled
Insert Sounds: Yes
Remove Sounds: Yes
Driver Sounds: Yes

Watched Devices: 2
Watched Vendors: 1

Recent Hardware Events:
  [1] USB Storage (5 min ago)
       Device: /dev/sdb1
       Vendor: SanDisk
       Action: ADDED
       Sound: bundled:hw-usb

  [2] NVIDIA GPU (10 min ago)
       Device: 0000:01:00.0
       Vendor: 0x10de
       Driver: nvidia
       Action: DRIVER_LOADED
       Sound: bundled:hw-gpu

  [3] USB Mouse (1 hour ago)
       Device: /dev/input/mouse0
       Vendor: Logitech
       Action: ADDED
       Sound: bundled:hw-mouse

Hardware Statistics:
  Devices Today: 12
  Insertions: 10
  Removals: 2

Sound Settings:
  Insert: bundled:hw-insert
  Remove: bundled:hw-remove
  Driver: bundled:hw-driver

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Hardware monitoring doesn't play sounds directly:
- Monitoring feature using udevadm/sysfs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Hardware Insertion Monitor

```go
type HardwareInsertionMonitor struct {
    config          *HardwareInsertionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*DeviceInfo
    lastEventTime   map[string]time.Time
}

type DeviceInfo struct {
    DevicePath  string
    Subsystem   string
    Vendor      string
    Model       string
    Driver      string
    Action      string
    DetectedAt  time.Time
}

func (m *HardwareInsertionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*DeviceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *HardwareInsertionMonitor) monitor() {
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

func (m *HardwareInsertionMonitor) snapshotDeviceState() {
    // Scan /sys/devices for current devices
    m.scanDevices()
}

func (m *HardwareInsertionMonitor) checkDeviceState() {
    // Check for udev events or scan devices
    m.scanDevices()
}

func (m *HardwareInsertionMonitor) scanDevices() {
    // Scan USB devices
    m.scanUSBDevices()

    // Scan PCI devices
    m.scanPCIDevices()

    // Scan block devices
    m.scanBlockDevices()
}

func (m *HardwareInsertionMonitor) scanUSBDevices() {
    usbPath := "/sys/bus/usb/devices"
    entries, err := os.ReadDir(usbPath)
    if err != nil {
        return
    }

    currentDevices := make(map[string]bool)

    for _, entry := range entries {
        devPath := filepath.Join(usbPath, entry.Name())
        idVendor := filepath.Join(devPath, "idVendor")
        idProduct := filepath.Join(devPath, "idProduct")

        vendorData, _ := os.ReadFile(idVendor)
        productData, _ := os.ReadFile(idProduct)

        vendor := strings.TrimSpace(string(vendorData))
        product := strings.TrimSpace(string(productData))

        if vendor == "" || product == "" {
            continue
        }

        key := fmt.Sprintf("usb:%s:%s", vendor, product)
        currentDevices[key] = true

        if _, exists := m.deviceState[key]; !exists {
            // New device
            device := &DeviceInfo{
                DevicePath: devPath,
                Subsystem:  "usb",
                Vendor:     vendor,
                Model:      product,
                Action:     "add",
                DetectedAt: time.Now(),
            }

            m.deviceState[key] = device
            m.onDeviceInserted(device)
        }
    }

    // Check for removed devices
    for key, device := range m.deviceState {
        if device.Subsystem == "usb" && !currentDevices[key] {
            delete(m.deviceState, key)
            m.onDeviceRemoved(device)
        }
    }
}

func (m *HardwareInsertionMonitor) scanPCIDevices() {
    pciPath := "/sys/bus/pci/devices"
    entries, err := os.ReadDir(pciPath)
    if err != nil {
        return
    }

    currentDevices := make(map[string]bool)

    for _, entry := range entries {
        devPath := filepath.Join(pciPath, entry.Name())
        vendor := filepath.Join(devPath, "vendor")
        device := filepath.Join(devPath, "device")
        driver := filepath.Join(devPath, "driver")

        vendorData, _ := os.ReadFile(vendor)
        deviceData, _ := os.ReadFile(device)

        vendorID := strings.TrimSpace(string(vendorData))
        deviceID := strings.TrimSpace(string(deviceData))

        if vendorID == "" {
            continue
        }

        key := fmt.Sprintf("pci:%s:%s", vendorID, deviceID)
        currentDevices[key] = true

        if _, exists := m.deviceState[key]; !exists {
            // New device
            devInfo := &DeviceInfo{
                DevicePath: devPath,
                Subsystem:  "pci",
                Vendor:     vendorID,
                Model:      deviceID,
                DetectedAt: time.Now(),
            }

            // Check for driver
            if _, err := os.Stat(driver); err == nil {
                driverLink := filepath.Join(driver, "module")
                if _, err := os.Readlink(driverLink); err == nil {
                    devInfo.Driver = "loaded"
                }
            }

            m.deviceState[key] = devInfo
            m.onDeviceInserted(devInfo)
        }
    }

    // Check for removed devices
    for key, device := range m.deviceState {
        if device.Subsystem == "pci" && !currentDevices[key] {
            delete(m.deviceState, key)
            m.onDeviceRemoved(device)
        }
    }
}

func (m *HardwareInsertionMonitor) scanBlockDevices() {
    // Scan /sys/block for block devices
    entries, err := os.ReadDir("/sys/block")
    if err != nil {
        return
    }

    for _, entry := range entries {
        devPath := filepath.Join("/sys/block", entry.Name())
        // Check if it's a removable device
        removable := filepath.Join(devPath, "removable")
        if data, err := os.ReadFile(removable); err == nil {
            if strings.TrimSpace(string(data)) == "1" {
                key := fmt.Sprintf("block:%s", entry.Name())
                if _, exists := m.deviceState[key]; !exists {
                    device := &DeviceInfo{
                        DevicePath: devPath,
                        Subsystem:  "block",
                        Model:      entry.Name(),
                        Action:     "add",
                        DetectedAt: time.Now(),
                    }
                    m.deviceState[key] = device
                    m.onDeviceInserted(device)
                }
            }
        }
    }
}

func (m *HardwareInsertionMonitor) shouldWatchDevice(subsystem, vendor string) bool {
    if len(m.config.WatchDevices) == 0 && len(m.config.WatchVendors) == 0 {
        return true
    }

    for _, dev := range m.config.WatchDevices {
        if dev == "*" || dev == subsystem {
            return true
        }
    }

    for _, v := range m.config.WatchVendors {
        if v == vendor {
            return true
        }
    }

    return false
}

func (m *HardwareInsertionMonitor) onDeviceInserted(device *DeviceInfo) {
    if !m.config.SoundOnInsert {
        return
    }

    key := fmt.Sprintf("insert:%s:%s", device.Subsystem, device.Vendor)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["insert"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *HardwareInsertionMonitor) onDeviceRemoved(device *DeviceInfo) {
    if !m.config.SoundOnRemove {
        return
    }

    key := fmt.Sprintf("remove:%s:%s", device.Subsystem, device.Vendor)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["remove"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *HardwareInsertionMonitor) onDriverLoaded(device *DeviceInfo) {
    if !m.config.SoundOnDriver {
        return
    }

    key := fmt.Sprintf("driver:%s", device.Model)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["driver"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *HardwareInsertionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /sys/bus/*/devices/* | Filesystem | Free | Device info |
| udevadm | System Tool | Free | Device events |

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
| macOS | Limited | Uses system_profiler |
| Linux | Supported | Uses sysfs, udev |
