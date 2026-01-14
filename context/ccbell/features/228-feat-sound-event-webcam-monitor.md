# Feature: Sound Event Webcam Monitor

Play sounds for webcam access and status events.

## Summary

Monitor webcam access, camera on/off states, and recording indicators, playing sounds for webcam events.

## Motivation

- Privacy awareness
- Recording state feedback
- Video call alerts
- Camera access detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Webcam Events

| Event | Description | Example |
|-------|-------------|---------|
| Camera On | Camera activated | Video call started |
| Camera Off | Camera deactivated | Call ended |
| Recording | Recording active | OBS recording |
| Access Denied | Camera access blocked | Permission denied |
| Device Connected | Camera plugged in | USB camera attached |

### Configuration

```go
type WebcamMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    SoundOnAccess    bool              `json:"sound_on_access"`
    SoundOnDisconnect bool             `json:"sound_on_disconnect"`
    WatchApps        []string          `json:"watch_apps"` // Apps using camera
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type WebcamEvent struct {
    AppName    string
    EventType  string // "on", "off", "recording", "connected", "disconnected"
    DeviceName string
}
```

### Commands

```bash
/ccbell:webcam status             # Show webcam status
/ccbell:webcam access on          # Enable access sounds
/ccbell:webcam add Zoom           # Add app to watch
/ccbell:webcam sound on <sound>
/ccbell:webcam sound off <sound>
/ccbell:webcam test               # Test webcam sounds
```

### Output

```
$ ccbell:webcam status

=== Sound Event Webcam Monitor ===

Status: Enabled
Access Sounds: Yes
Disconnect Sounds: Yes

Current State:
  Camera: OFF
  Active Apps: 0
  Status: Idle

Devices: 2

[1] FaceTime HD Camera
    Status: Connected
    Last Used: 2 hours ago
    Sound: bundled:stop

[2] USB Webcam C920
    Status: Disconnected
    Last Used: 1 week ago
    Sound: bundled:stop

Recent Events:
  [1] Zoom: Camera OFF (1 hour ago)
  [2] FaceTime HD Camera: Device Connected (5 hours ago)
  [3] Safari: Camera ON (1 day ago)

Sound Settings:
  Camera On: bundled:stop
  Camera Off: bundled:stop
  Recording: bundled:stop

[Configure] [Add App] [Test All]
```

---

## Audio Player Compatibility

Webcam monitoring doesn't play sounds directly:
- Monitoring feature using camera APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Webcam Monitor

```go
type WebcamMonitor struct {
    config       *WebcamMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    activeApps   map[string]bool
    devices      map[string]bool
}

func (m *WebcamMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeApps = make(map[string]bool)
    m.devices = make(map[string]bool)
    go m.monitor()
}

func (m *WebcamMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkWebcam()
        case <-m.stopCh:
            return
        }
    }
}

func (m *WebcamMonitor) checkWebcam() {
    // Check active camera users
    activeUsers := m.getActiveWebcamUsers()

    for app, isActive := range activeUsers {
        wasActive := m.activeApps[app]
        m.activeApps[app] = isActive

        if isActive && !wasActive {
            m.onCameraOn(app)
        } else if !isActive && wasActive {
            m.onCameraOff(app)
        }
    }

    // Check devices
    currentDevices := m.getWebcamDevices()

    for device, connected := range currentDevices {
        wasConnected := m.devices[device]
        m.devices[device] = connected

        if connected && !wasConnected {
            m.onDeviceConnected(device)
        } else if !connected && wasConnected {
            m.onDeviceDisconnected(device)
        }
    }
}

func (m *WebcamMonitor) getActiveWebcamUsers() map[string]bool {
    users := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        users = m.getMacOSWebcamUsers()
    } else if runtime.GOOS == "linux" {
        users = m.getLinuxWebcamUsers()
    }

    // Filter to watched apps if configured
    if len(m.config.WatchApps) > 0 {
        filtered := make(map[string]bool)
        for app, active := range users {
            for _, watched := range m.config.WatchApps {
                if strings.Contains(strings.ToLower(app), strings.ToLower(watched)) {
                    filtered[app] = active
                    break
                }
            }
        }
        return filtered
    }

    return users
}

func (m *WebcamMonitor) getMacOSWebcamUsers() map[string]bool {
    users := make(map[string]bool)

    // Use lsof to check camera access
    cmd := exec.Command("lsof", "-i", "-P", "-n")
    output, err := cmd.Output()
    if err != nil {
        return users
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "VDC") || strings.Contains(line, "FaceTime") {
            // Extract process name
            parts := strings.Fields(line)
            if len(parts) > 0 {
                users[parts[0]] = true
            }
        }
    }

    return users
}

func (m *WebcamMonitor) getLinuxWebcamUsers() map[string]bool {
    users := make(map[string]bool)

    // Check /dev/video*
    cmd := exec.Command("lsof", "/dev/video*")
    output, err := cmd.Output()
    if err != nil {
        return users
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) > 0 {
            users[parts[0]] = true
        }
    }

    return users
}

func (m *WebcamMonitor) getWebcamDevices() map[string]bool {
    devices := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        cmd := exec.Command("system_profiler", "SPCameraDataType")
        output, err := cmd.Output()
        if err != nil {
            return devices
        }

        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, ":") {
                device := strings.TrimSpace(strings.Split(line, ":")[0])
                if device != "" {
                    devices[device] = true
                }
            }
        }
    } else if runtime.GOOS == "linux" {
        // Check /dev/video*
        entries, _ := os.ReadDir("/dev")
        for _, entry := range entries {
            if strings.HasPrefix(entry.Name(), "video") {
                devices[entry.Name()] = true
            }
        }
    }

    return devices
}

func (m *WebcamMonitor) onCameraOn(appName string) {
    if !m.config.SoundOnAccess {
        return
    }

    sound := m.config.Sounds["on"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *WebcamMonitor) onCameraOff(appName string) {
    sound := m.config.Sounds["off"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *WebcamMonitor) onDeviceConnected(device string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *WebcamMonitor) onDeviceDisconnected(device string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lsof | System Tool | Free | File descriptor checking |
| system_profiler | System Tool | Free | macOS hardware info |
| /dev/video* | Device | Free | Linux video devices |

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
| macOS | Supported | Uses lsof/system_profiler |
| Linux | Supported | Uses lsof and /dev/video* |
| Windows | Not Supported | ccbell only supports macOS/Linux |
