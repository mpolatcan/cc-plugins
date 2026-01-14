# Feature: Sound Event USB Device Monitor

Play sounds for USB device connections, disconnections, and device changes.

## Summary

Monitor USB device additions, removals, and configuration changes, playing sounds for USB events.

## Motivation

- USB awareness
- Security monitoring
- Device detection
- Hardware changes
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

### USB Device Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Connected | USB device added | mouse added |
| Device Disconnected | USB device removed | usb drive removed |
| Device Changed | Configuration changed | bandwidth changed |
| Unknown Device | Unrecognized device | unknown vendor |
| High Power | Device needs high power | 900mA |
| USB Error | Device error detected | error |

### Configuration

```go
type USBDeviceMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchTypes         []string          `json:"watch_types"` // "storage", "input", "*"
    SoundOnConnect     bool              `json:"sound_on_connect"`
    SoundOnDisconnect  bool              `json:"sound_on_disconnect"`
    SoundOnUnknown     bool              `json:"sound_on_unknown"`
    SoundOnError       bool              `json:"sound_on_error"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:usb status                  # Show USB status
/ccbell:usb add storage             # Add device type to watch
/ccbell:usb sound connect <sound>
/ccbell:usb test                    # Test USB sounds
```

### Output

```
$ ccbell:usb status

=== Sound Event USB Device Monitor ===

Status: Enabled
Watch Types: all

USB Device Status:

[1] Apple Keyboard (connected)
    Vendor: Apple (05AC)
    Product: Keyboard (0220)
    Type: input
    Speed: USB 2.0
    Sound: bundled:usb-keyboard

[2] USB Flash Drive (connected)
    Vendor: SanDisk (0781)
    Product: Cruzer Glide (5578)
    Type: storage
    Size: 32 GB
    Sound: bundled:usb-storage

[3] Logitech Mouse (connected)
    Vendor: Logitech (046D)
    Product: MX Master (404D)
    Type: input
    Speed: USB 2.0
    Sound: bundled:usb-mouse

Recent Events:

[1] USB Flash Drive: Connected (5 min ago)
       SanDisk Cruzer Glide mounted
       Sound: bundled:usb-connect
  [2] Logitech Mouse: Device Changed (10 min ago)
       Rate changed to 1000Hz
       Sound: bundled:usb-change
  [3] Unknown Device: Unknown Device Detected (1 hour ago)
       Device 1234:5678 not recognized
       Sound: bundled:usb-unknown

USB Statistics:
  Total Devices: 3
  Connected: 3
  Disconnected Today: 1

Sound Settings:
  Connect: bundled:usb-connect
  Disconnect: bundled:usb-disconnect
  Unknown: bundled:usb-unknown
  Error: bundled:usb-error

[Configure] [Add Type] [Test All]
```

---

## Audio Player Compatibility

USB monitoring doesn't play sounds directly:
- Monitoring feature using system_profiler, lsusb, ioreg
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### USB Device Monitor

```go
type USBDeviceMonitor struct {
    config        *USBDeviceMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    deviceState   map[string]*USBDeviceInfo
    lastEventTime map[string]time.Time
}

type USBDeviceInfo struct {
    DeviceName string
    VendorID   string
    ProductID  string
    VendorName string
    ProductName string
    Type       string // "storage", "input", "hub", "unknown"
    Speed      string
    Status     string // "connected", "disconnected"
    ConnectedAt time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| system_profiler | System Tool | Free | macOS hardware info |
| lsusb | System Tool | Free | Linux USB devices |
| ioreg | System Tool | Free | macOS I/O registry |

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
| macOS | Supported | Uses system_profiler, ioreg |
| Linux | Supported | Uses lsusb, /sys/bus/usb |
