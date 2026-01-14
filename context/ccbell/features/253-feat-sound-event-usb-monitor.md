# Feature: Sound Event USB Monitor

Play sounds for USB device connections and disconnections.

## Summary

Monitor USB device connections, storage device insertions, and peripheral events, playing sounds for USB activity.

## Motivation

- Storage device detection
- Peripheral connection feedback
- USB device alerts
- Drive mount notifications

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
| Device Connected | USB device plugged | Flash drive |
| Device Disconnected | USB device removed | Flash drive |
| Storage Mounted | Drive mounted | /Volumes/USB |
| Storage Unmounted | Drive ejected | /Volumes/USB |
| Device Type | Device category | Keyboard, mouse |

### Configuration

```go
type USBMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchTypes        []string          `json:"watch_types"` // "storage", "hid", "audio"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnMount      bool              `json:"sound_on_mount"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 2 default
}

type USBEvent struct {
    DeviceName    string
    DeviceType    string // "storage", "hid", "audio", "other"
    VendorID      string
    ProductID     string
    SerialNumber  string
    MountPath     string
    EventType     string // "connected", "disconnected", "mounted"
}
```

### Commands

```bash
/ccbell:usb status                 # Show USB status
/ccbell:usb add storage            # Add type to watch
/ccbell:usb remove storage
/ccbell:usb sound connect <sound>
/ccbell:usb sound mount <sound>
/ccbell:usb test                   # Test USB sounds
```

### Output

```
$ ccbell:usb status

=== Sound Event USB Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Current Devices: 3

[1] USB Flash Drive
    Type: Storage
    Vendor: SanDisk
    Connected: Yes
    Mount: /Volumes/USB
    Sound: bundled:stop

[2] USB Keyboard
    Type: HID
    Vendor: Logitech
    Connected: Yes
    Sound: bundled:stop

[3] USB Mouse
    Type: HID
    Vendor: Apple
    Connected: Yes
    Sound: bundled:stop

Recent Events:
  [1] USB Flash Drive: Connected (5 min ago)
  [2] USB Flash Drive: Mounted (5 min ago)
       /Volumes/USB
  [3] USB Mouse: Connected (1 hour ago)

Sound Settings:
  Connect: bundled:stop
  Disconnect: bundled:stop
  Mount: bundled:stop

[Configure] [Add Type] [Test All]
```

---

## Audio Player Compatibility

USB monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### USB Monitor

```go
type USBMonitor struct {
    config          *USBMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*USBDeviceState
}

type USBDeviceState struct {
    Name       string
    DeviceType string
    VendorID   string
    ProductID  string
    Connected  bool
    MountPath  string
    LastSeen   time.Time
}

func (m *USBMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*USBDeviceState)
    go m.monitor()
}

func (m *USBMonitor) monitor() {
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

func (m *USBMonitor) checkDevices() {
    devices := m.getUSBDevices()

    // Mark all devices as potentially disconnected first
    for _, state := range m.deviceState {
        state.Connected = false
    }

    // Update state for connected devices
    for _, device := range devices {
        m.evaluateDevice(device)
    }

    // Report any devices still marked as disconnected
    for key, state := range m.deviceState {
        if !state.Connected && state.LastSeen.Add(10*time.Second).After(time.Now()) {
            // Recently disconnected
            m.onDeviceDisconnected(state)
            delete(m.deviceState, key)
        }
    }
}

func (m *USBMonitor) getUSBDevices() []*USBInfo {
    var devices []*USBInfo

    if runtime.GOOS == "darwin" {
        return m.getDarwinUSBDevices()
    }
    return m.getLinuxUSBDevices()
}

func (m *USBMonitor) getDarwinUSBDevices() []*USBInfo {
    var devices []*USBInfo

    cmd := exec.Command("system_profiler", "SPUSBDataType", "-json")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    // Parse JSON (simplified - real implementation would traverse properly)
    var result map[string]interface{}
    if err := json.Unmarshal(output, &result); err != nil {
        return devices
    }

    // Extract USB devices from result
    // This is a placeholder - real implementation would parse the full structure

    return devices
}

func (m *USBMonitor) getLinuxUSBDevices() []*USBInfo {
    var devices []*USBInfo

    // Read USB devices from sysfs
    usbPath := "/sys/bus/usb/devices"

    entries, err := os.ReadDir(usbPath)
    if err != nil {
        return devices
    }

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        devicePath := filepath.Join(usbPath, entry.Name())

        // Check if it's a device (not a hub)
        idVendor, _ := os.ReadFile(filepath.Join(devicePath, "idVendor"))
        idProduct, _ := os.ReadFile(filepath.Join(devicePath, "idProduct"))

        if len(idVendor) > 0 && len(idProduct) > 0 {
            device := &USBInfo{
                VendorID:  strings.TrimSpace(string(idVendor)),
                ProductID: strings.TrimSpace(string(idProduct)),
            }

            // Get manufacturer and product name
            manufacturer, _ := os.ReadFile(filepath.Join(devicePath, "manufacturer"))
            product, _ := os.ReadFile(filepath.Join(devicePath, "product"))

            if len(manufacturer) > 0 {
                device.Name = strings.TrimSpace(string(manufacturer))
            }
            if len(product) > 0 {
                if device.Name != "" {
                    device.Name += " "
                }
                device.Name += strings.TrimSpace(string(product))
            }

            // Determine device type
            if _, err := os.Stat(filepath.Join(devicePath, "block")); err == nil {
                device.DeviceType = "storage"
            } else if strings.Contains(device.Name, "Keyboard") ||
                       strings.Contains(device.Name, "Mouse") {
                device.DeviceType = "hid"
            } else {
                device.DeviceType = "other"
            }

            devices = append(devices, device)
        }
    }

    return devices
}

func (m *USBMonitor) evaluateDevice(device *USBInfo) {
    key := device.VendorID + ":" + device.ProductID

    // Check for serial number if available
    if device.SerialNumber != "" {
        key += ":" + device.SerialNumber
    }

    lastState := m.deviceState[key]

    if lastState == nil {
        // New device
        m.deviceState[key] = &USBDeviceState{
            Name:       device.Name,
            DeviceType: device.DeviceType,
            VendorID:   device.VendorID,
            ProductID:  device.ProductID,
            Connected:  true,
            LastSeen:   time.Now(),
        }

        m.onDeviceConnected(device)
        return
    }

    // Update state
    lastState.Connected = true
    lastState.LastSeen = time.Now()

    // Check if we should watch this type
    if len(m.config.WatchTypes) > 0 {
        found := false
        for _, watchType := range m.config.WatchTypes {
            if device.DeviceType == watchType {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }
}

func (m *USBMonitor) onDeviceConnected(device *USBInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *USBMonitor) onDeviceDisconnected(state *USBDeviceState) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *USBMonitor) onStorageMounted(path string) {
    if !m.config.SoundOnMount {
        return
    }

    sound := m.config.Sounds["mounted"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| system_profiler | System Tool | Free | macOS hardware info |
| /sys/bus/usb | File | Free | Linux USB info |

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
| Linux | Supported | Uses /sys/bus/usb |
| Windows | Not Supported | ccbell only supports macOS/Linux |
