# Feature: Sound Event Hardware Insertion Monitor

Play sounds for new hardware device detection events.

## Summary

Monitor hardware device insertion, detection, and initialization, playing sounds for device events.

## Motivation

- Hardware awareness
- Device detection feedback
- USB device alerts
- Driver loading feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Hardware Insertion Events

| Event | Description | Example |
|-------|-------------|---------|
| USB Device | USB device plugged | flash drive |
| Device Attached | New device detected | /dev/sda |
| Driver Loaded | New driver loaded | nvme driver |
| Network Interface | New network interface | USB ethernet |

### Configuration

```go
type HardwareInsertionMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchTypes       []string          `json:"watch_types"` // "usb", "block", "net"
    SoundOnInsert    bool              `json:"sound_on_insert"]
    SoundOnRemove    bool              `json:"sound_on_remove"]
    SoundOnDriver    bool              `json:"sound_on_driver"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type HardwareEvent struct {
    DeviceType string // "usb", "block", "net", "audio"
    DeviceName string
    Path       string
    Driver     string
    EventType  string // "insert", "remove", "driver_loaded"
}
```

### Commands

```bash
/ccbell:hw status                     # Show hardware status
/ccbell:hw add usb                    # Add device type to watch
/ccbell:hw remove usb
/ccbell:hw sound insert <sound>
/ccbell:hw sound driver <sound>
/ccbell:hw test                       # Test hardware sounds
```

### Output

```
$ ccbell:hw status

=== Sound Event Hardware Insertion Monitor ===

Status: Enabled
Insert Sounds: Yes
Driver Sounds: Yes

Watched Types: 3

[1] USB Devices
    Attached: 5
    Last Insert: 5 min ago
    Sound: bundled:hw-insert

[2] Block Devices
    Attached: 3
    Last Insert: 1 hour ago
    Sound: bundled:stop

[3] Network Interfaces
    Attached: 2
    Last Insert: 2 hours ago
    Sound: bundled:stop

Recent Events:
  [1] USB Device Inserted (5 min ago)
       Kingston DataTraveler 2.0
  [2] Driver Loaded (10 min ago)
       usbhid
  [3] Network Interface Added (2 hours ago)
       en3: USB Ethernet

Hardware Statistics:
  Total insertions: 15
  Total removals: 8

Sound Settings:
  Insert: bundled:hw-insert
  Remove: bundled:hw-remove
  Driver: bundled:hw-driver

[Configure] [Add Type] [Test All]
```

---

## Audio Player Compatibility

Hardware monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Hardware Insertion Monitor

```go
type HardwareInsertionMonitor struct {
    config           *HardwareInsertionMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    deviceState      map[string]*DeviceInfo
    lastEventTime    map[string]time.Time
}

type DeviceInfo struct {
    Path     string
    Name     string
    Type     string
    Driver   string
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
    m.snapshotHardwareState()

    for {
        select {
        case <-ticker.C:
            m.checkHardwareChanges()
        case <-m.stopCh:
            return
        }
    }
}

func (m *HardwareInsertionMonitor) snapshotHardwareState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinHardware()
    } else {
        m.snapshotLinuxHardware()
    }
}

func (m *HardwareInsertionMonitor) snapshotDarwinHardware() {
    // Use system_profiler for hardware info
    cmd := exec.Command("system_profiler", "SPUSBDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Also check for new block devices
    cmd = exec.Command("diskutil", "list")
    output, err = cmd.Output()
    if err == nil {
        m.parseDiskutilOutput(string(output))
    }
}

func (m *HardwareInsertionMonitor) snapshotLinuxHardware() {
    // Check /sys/bus for new devices
    m.checkUSBDevices()
    m.checkBlockDevices()
    m.checkNetworkDevices()
    m.checkDrivers()
}

func (m *HardwareInsertionMonitor) checkHardwareChanges() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinHardware()
    } else {
        m.checkLinuxHardware()
    }
}

func (m *HardwareInsertionMonitor) checkDarwinHardware() {
    cmd := exec.Command("system_profiler", "SPUSBDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSystemProfilerOutput(string(output))
}

func (m *HardwareInsertionMonitor) checkLinuxHardware() {
    m.checkUSBDevices()
    m.checkBlockDevices()
    m.checkNetworkDevices()
    m.checkDrivers()
}

func (m *HardwareInsertionMonitor) checkUSBDevices() {
    usbPath := "/sys/bus/usb/devices"
    entries, err := os.ReadDir(usbPath)
    if err != nil {
        return
    }

    currentDevices := make(map[string]bool)

    for _, entry := range entries {
        devicePath := filepath.Join(usbPath, entry.Name())
        deviceInfo := m.parseUSBDevice(devicePath)
        if deviceInfo != nil {
            key := fmt.Sprintf("usb:%s", entry.Name())
            currentDevices[key] = true

            if _, exists := m.deviceState[key]; !exists {
                m.onDeviceInserted(deviceInfo)
            }
            m.deviceState[key] = deviceInfo
        }
    }

    // Check for removed devices
    m.checkRemovedDevices(currentDevices, "usb")
}

func (m *HardwareInsertionMonitor) checkBlockDevices() {
    // Check /sys/block for new block devices
    entries, err := os.ReadDir("/sys/block")
    if err != nil {
        return
    }

    currentDevices := make(map[string]bool)

    for _, entry := range entries {
        if strings.HasPrefix(entry.Name(), "loop") || strings.HasPrefix(entry.Name(), "sr") {
            continue
        }

        key := fmt.Sprintf("block:%s", entry.Name())
        currentDevices[key] = true

        if _, exists := m.deviceState[key]; !exists {
            m.onDeviceInserted(&DeviceInfo{
                Path: filepath.Join("/dev", entry.Name()),
                Name: entry.Name(),
                Type: "block",
            })
        }

        m.deviceState[key] = &DeviceInfo{
            Path: filepath.Join("/dev", entry.Name()),
            Name: entry.Name(),
            Type: "block",
        }
    }

    m.checkRemovedDevices(currentDevices, "block")
}

func (m *HardwareInsertionMonitor) checkNetworkDevices() {
    // Check /sys/class/net for new network interfaces
    entries, err := os.ReadDir("/sys/class/net")
    if err != nil {
        return
    }

    currentDevices := make(map[string]bool)

    for _, entry := range entries {
        key := fmt.Sprintf("net:%s", entry.Name())
        currentDevices[key] = true

        if _, exists := m.deviceState[key]; !exists {
            m.onDeviceInserted(&DeviceInfo{
                Path: filepath.Join("/sys/class/net", entry.Name()),
                Name: entry.Name(),
                Type: "net",
            })
        }

        m.deviceState[key] = &DeviceInfo{
            Path: filepath.Join("/sys/class/net", entry.Name()),
            Name: entry.Name(),
            Type: "net",
        }
    }

    m.checkRemovedDevices(currentDevices, "net")
}

func (m *HardwareInsertionMonitor) checkDrivers() {
    // Check /proc/modules for new drivers
    data, err := os.ReadFile("/proc/modules")
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    currentDrivers := make(map[string]bool)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) >= 4 {
            driverName := parts[0]
            currentDrivers[driverName] = true

            if !m.shouldWatchType("driver") {
                continue
            }

            key := fmt.Sprintf("driver:%s", driverName)
            if _, exists := m.deviceState[key]; !exists {
                m.onDriverLoaded(driverName)
            }
            m.deviceState[key] = &DeviceInfo{
                Name:   driverName,
                Driver: driverName,
                Type:   "driver",
            }
        }
    }
}

func (m *HardwareInsertionMonitor) parseUSBDevice(path string) *DeviceInfo {
    // Read device info
    idVendor, _ := os.ReadFile(filepath.Join(path, "idVendor"))
    idProduct, _ := os.ReadFile(filepath.Join(path, "idProduct"))
    manufacturer, _ := os.ReadFile(filepath.Join(path, "manufacturer"))
    product, _ := os.ReadFile(filepath.Join(path, "product"))

    if len(idVendor) == 0 {
        return nil
    }

    name := strings.TrimSpace(string(product))
    if name == "" {
        name = fmt.Sprintf("USB %s:%s", strings.TrimSpace(string(idVendor)), strings.TrimSpace(string(idProduct)))
    }

    return &DeviceInfo{
        Path: path,
        Name: name,
        Type: "usb",
    }
}

func (m *HardwareInsertionMonitor) parseDiskutilOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "/dev/") {
            parts := strings.Fields(line)
            if len(parts) >= 1 {
                devicePath := parts[0]
                name := filepath.Base(devicePath)
                key := fmt.Sprintf("block:%s", name)

                if _, exists := m.deviceState[key]; !exists {
                    m.onDeviceInserted(&DeviceInfo{
                        Path: devicePath,
                        Name: name,
                        Type: "block",
                    })
                }
            }
        }
    }
}

func (m *HardwareInsertionMonitor) parseSystemProfilerOutput(output string) {
    // Parse JSON output for USB devices
    // Simplified - extract device names
    re := regexp.MustCompile(`"name":\s*"([^"]+)"`)
    matches := re.FindAllStringSubmatch(output, -1)

    for _, match := range matches {
        if len(match) >= 2 {
            name := match[1]
            key := fmt.Sprintf("usb:%s", name)

            if _, exists := m.deviceState[key]; !exists {
                m.onDeviceInserted(&DeviceInfo{
                    Name: name,
                    Type: "usb",
                })
            }
        }
    }
}

func (m *HardwareInsertionMonitor) checkRemovedDevices(currentDevices map[string]bool, deviceType string) {
    for key := range m.deviceState {
        if !strings.HasPrefix(key, deviceType+":") {
            continue
        }

        if !currentDevices[key] {
            info := m.deviceState[key]
            m.onDeviceRemoved(info)
            delete(m.deviceState, key)
        }
    }
}

func (m *HardwareInsertionMonitor) shouldWatchType(deviceType string) bool {
    if len(m.config.WatchTypes) == 0 {
        return true
    }

    for _, t := range m.config.WatchTypes {
        if t == deviceType {
            return true
        }
    }

    return false
}

func (m *HardwareInsertionMonitor) onDeviceInserted(info *DeviceInfo) {
    if !m.config.SoundOnInsert {
        return
    }

    if !m.shouldWatchType(info.Type) {
        return
    }

    key := fmt.Sprintf("insert:%s:%s", info.Type, info.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["insert"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *HardwareInsertionMonitor) onDeviceRemoved(info *DeviceInfo) {
    if !m.config.SoundOnRemove {
        return
    }

    if !m.shouldWatchType(info.Type) {
        return
    }

    key := fmt.Sprintf("remove:%s:%s", info.Type, info.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["remove"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *HardwareInsertionMonitor) onDriverLoaded(driverName string) {
    if !m.config.SoundOnDriver {
        return
    }

    key := fmt.Sprintf("driver:%s", driverName)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["driver"]
        if sound != "" {
            m.player.Play(sound, 0.3)
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
| system_profiler | System Tool | Free | macOS hardware info |
| diskutil | System Tool | Free | macOS disk info |
| /sys/bus/usb/devices | File | Free | USB device info |
| /proc/modules | File | Free | Loaded modules |

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
| macOS | Supported | Uses system_profiler, diskutil |
| Linux | Supported | Uses /sys, /proc/modules |
| Windows | Not Supported | ccbell only supports macOS/Linux |
