# Feature: Sound Event AirPlay Monitor

Play sounds for AirPlay and casting events.

## Summary

Monitor AirPlay connections, Apple TV discovery, and casting events, playing sounds for AirPlay-related events.

## Motivation

- AirPlay connection feedback
- Casting confirmation
- Apple TV discovery alerts
- Streaming state awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### AirPlay Events

| Event | Description | Example |
|-------|-------------|---------|
| AirPlay Connected | Device connected | Apple TV connected |
| AirPlay Disconnected | Device disconnected | Streaming stopped |
| Device Discovered | New device found | Apple TV appeared |
| Mirroring Started | Screen mirroring begun | Display casting |
| Mirroring Stopped | Screen mirroring ended | Stopped casting |
| Audio Stream | Audio only stream | Music streaming |

### Configuration

```go
type AirPlayMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnDiscover   bool              `json:"sound_on_discover"`
    WatchDevices      []string          `json:"watch_devices"` // Device names
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type AirPlayEvent struct {
    DeviceName string
    EventType  string // "connected", "disconnected", "discovered", "mirroring"
    DeviceType string // "apple_tv", "homepod", "mac"
    IPAddress  string
}
```

### Commands

```bash
/ccbell:airplay status            # Show AirPlay status
/ccbell:airplay connect on        # Enable connect sounds
/ccbell:airplay discover on       # Enable discovery sounds
/ccbell:airplay add "Living Room TV"
/ccbell:airplay sound connected <sound>
/ccbell:airplay test              # Test AirPlay sounds
```

### Output

```
$ ccbell:airplay status

=== Sound Event AirPlay Monitor ===

Status: Enabled
Connect Sounds: Yes
Discover Sounds: Yes

Available Devices: 3

[1] Living Room TV (Apple TV 4K)
    Status: Connected
    Type: apple_tv
    IP: 192.168.1.100
    Sound: bundled:stop

[2] HomePod (Bedroom)
    Status: Available
    Type: homepod
    IP: 192.168.1.101
    Sound: bundled:stop

[3] Office TV (Apple TV HD)
    Status: Available
    Type: apple_tv
    IP: 192.168.1.102
    Sound: bundled:stop

Recent Events:
  [1] Living Room TV: Connected (5 min ago)
  [2] Office TV: Discovered (30 min ago)
  [3] Living Room TV: Disconnected (1 hour ago)

Sound Settings:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Discovered: bundled:stop

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

AirPlay monitoring doesn't play sounds directly:
- Monitoring feature using network discovery
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### AirPlay Monitor

```go
type AirPlayMonitor struct {
    config       *AirPlayMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    devices      map[string]bool
    mirroring    bool
}

func (m *AirPlayMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.devices = make(map[string]bool)
    go m.monitor()
}

func (m *AirPlayMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkAirPlayDevices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *AirPlayMonitor) checkAirPlayDevices() {
    discovered := m.discoverDevices()

    for device, isAvailable := range discovered {
        wasAvailable := m.devices[device]
        m.devices[device] = isAvailable

        if isAvailable && !wasAvailable {
            m.onDeviceDiscovered(device)
        }
    }

    m.checkMirroring()
}

func (m *AirPlayMonitor) discoverDevices() map[string]bool {
    devices := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        devices = m.discoverMacOSDevices()
    } else if runtime.GOOS == "linux" {
        devices = m.discoverLinuxDevices()
    }

    return devices
}

func (m *AirPlayMonitor) discoverMacOSDevices() map[string]bool {
    devices := make(map[string]bool)

    // Use dns-sd to discover AirPlay devices
    cmd := exec.Command("dns-sd", "-B", "_airplay._tcp", "local")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Apple TV") || strings.Contains(line, "HomePod") {
            parts := strings.Fields(line)
            if len(parts) >= 1 {
                devices[parts[0]] = true
            }
        }
    }

    return devices
}

func (m *AirPlayMonitor) discoverLinuxDevices() map[string]bool {
    devices := make(map[string]bool)

    // Use avahi-browse to discover AirPlay devices
    cmd := exec.Command("avahi-browse", "-r", "_airplay._tcp")
    output, err := cmd.Output()
    if err != nil {
        return devices
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Apple TV") || strings.Contains(line, "HomePod") {
            devices["discovered_device"] = true
        }
    }

    return devices
}

func (m *AirPlayMonitor) checkMirroring() {
    mirroring := m.isMirroring()

    if mirroring && !m.mirroring {
        m.onMirroringStarted()
    } else if !mirroring && m.mirroring {
        m.onMirroringStopped()
    }

    m.mirroring = mirroring
}

func (m *AirPlayMonitor) isMirroring() bool {
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("osascript", "-e",
            `tell application "System Events" to name of every process`)
        output, err := cmd.Output()
        if err != nil {
            return false
        }

        return strings.Contains(string(output), "AirPlay")
    }

    if runtime.GOOS == "linux" {
        cmd := exec.Command("xrandr", "--listmonitors")
        output, err := cmd.Output()
        if err != nil {
            return false
        }

        return strings.Contains(string(output), "AirPlay")
    }

    return false
}

func (m *AirPlayMonitor) onDeviceDiscovered(device string) {
    if !m.config.SoundOnDiscover {
        return
    }

    sound := m.config.Sounds["discovered"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AirPlayMonitor) onDeviceConnected(device string) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AirPlayMonitor) onDeviceDisconnected(device string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AirPlayMonitor) onMirroringStarted() {
    sound := m.config.Sounds["mirroring_started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AirPlayMonitor) onMirroringStopped() {
    sound := m.config.Sounds["mirroring_stopped"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dns-sd | Bonjour | Free | macOS service discovery |
| avahi-browse | APT | Free | Linux service discovery |
| osascript | System Tool | Free | macOS automation |

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
| macOS | Supported | Uses dns-sd and osascript |
| Linux | Supported | Uses avahi-browse |
| Windows | Not Supported | ccbell only supports macOS/Linux |
