# Feature: Sound Event Display Monitor

Play sounds for external display connections and configuration changes.

## Summary

Monitor display connections, resolution changes, and multi-monitor configurations, playing sounds for display events.

## Motivation

- Display connection feedback
- Resolution change alerts
- Multi-monitor awareness
- Display power management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Display Events

| Event | Description | Example |
|-------|-------------|---------|
| Display Connected | External display attached | Monitor plugged |
| Display Disconnected | External display removed | Cable unplugged |
| Resolution Changed | Resolution updated | 1080p -> 4K |
| Brightness Changed | Brightness adjusted | Fn+F1 pressed |
| Rotation Changed | Display rotated | Portrait mode |
| Mirroring Changed | Mirroring toggled | Mirroring on/off |

### Configuration

```go
type DisplayMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnResolution bool              `json:"sound_on_resolution"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type DisplayEvent struct {
    DisplayID   string
    EventType   string // "connected", "disconnected", "resolution_changed", "brightness_changed"
    Resolution  string
    Brightness  float64
}
```

### Commands

```bash
/ccbell:display status            # Show display status
/ccbell:display connect on        # Enable connect sounds
/ccbell:display disconnect on     # Enable disconnect sounds
/ccbell:display sound connected <sound>
/ccbell:display sound disconnected <sound>
/ccbell:display test              # Test display sounds
```

### Output

```
$ ccbell:display status

=== Sound Event Display Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Connected Displays: 2

[1] Built-in Retina Display
    ID: 1234567890
    Resolution: 2560 x 1600
    Rotation: 0
    Status: Primary
    Sound: bundled:stop

[2] LG UltraFine 4K
    ID: 0987654321
    Resolution: 3840 x 2160
    Rotation: 0
    Status: Secondary
    Connected: Yes
    Sound: bundled:stop

Recent Events:
  [1] LG UltraFine: Connected (30 min ago)
  [2] Built-in: Resolution Changed (2 hours ago)
  [3] LG UltraFine: Disconnected (1 day ago)

Sound Settings:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Resolution Changed: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Display monitoring doesn't play sounds directly:
- Monitoring feature using display APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Display Monitor

```go
type DisplayMonitor struct {
    config       *DisplayMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    displays     map[string]bool
    resolutions  map[string]string
}

func (m *DisplayMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.displays = make(map[string]bool)
    m.resolutions = make(map[string]string)
    go m.monitor()
}

func (m *DisplayMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDisplays()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DisplayMonitor) checkDisplays() {
    currentDisplays := m.getDisplays()

    for displayID, connected := range currentDisplays {
        wasConnected := m.displays[displayID]
        m.displays[displayID] = connected

        if connected && !wasConnected {
            m.onDisplayConnected(displayID)
        } else if !connected && wasConnected {
            m.onDisplayDisconnected(displayID)
        }

        // Check resolution changes
        if connected {
            res := m.getResolution(displayID)
            if m.resolutions[displayID] != res {
                m.onResolutionChanged(displayID, res)
                m.resolutions[displayID] = res
            }
        }
    }
}

func (m *DisplayMonitor) getDisplays() map[string]bool {
    displays := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        displays = m.getMacOSDisplays()
    } else if runtime.GOOS == "linux" {
        displays = m.getLinuxDisplays()
    }

    return displays
}

func (m *DisplayMonitor) getMacOSDisplays() map[string]bool {
    displays := make(map[string]bool)

    cmd := exec.Command("system_profiler", "SPDisplaysDataType")
    output, err := cmd.Output()
    if err != nil {
        return displays
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Resolution:") || strings.Contains(line, "Display") {
            id := strings.TrimSpace(line)
            if id != "" {
                displays[id] = true
            }
        }
    }

    return displays
}

func (m *DisplayMonitor) getLinuxDisplays() map[string]bool {
    displays := make(map[string]bool)

    cmd := exec.Command("xrandr", "--query")
    output, err := cmd.Output()
    if err != nil {
        return displays
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
            continue
        }
        if strings.Contains(line, " connected") {
            parts := strings.Fields(line)
            if len(parts) >= 1 {
                displays[parts[0]] = true
            }
        }
    }

    return displays
}

func (m *DisplayMonitor) getResolution(displayID string) string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSResolution(displayID)
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxResolution(displayID)
    }
    return ""
}

func (m *DisplayMonitor) getMacOSResolution(displayID string) string {
    cmd := exec.Command("system_profiler", "SPDisplaysDataType")
    output, err := cmd.Output()
    if err != nil {
        return ""
    }

    // Parse resolution from output
    match := regexp.MustCompile(`(\d+)\s*x\s*(\d+)`).FindStringSubmatch(string(output))
    if match != nil {
        return fmt.Sprintf("%s x %s", match[1], match[2])
    }

    return ""
}

func (m *DisplayMonitor) getLinuxResolution(displayID string) string {
    cmd := exec.Command("xrandr", "--query", "--current")
    output, err := cmd.Output()
    if err != nil {
        return ""
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, displayID) {
            if strings.Contains(line, "connected") {
                // Parse resolution from line
                parts := strings.Fields(line)
                for _, part := range parts {
                    if strings.Contains(part, "x") {
                        return part
                    }
                }
            }
        }
    }

    return ""
}

func (m *DisplayMonitor) onDisplayConnected(displayID string) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DisplayMonitor) onDisplayDisconnected(displayID string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DisplayMonitor) onResolutionChanged(displayID string, resolution string) {
    if !m.config.SoundOnResolution {
        return
    }

    sound := m.config.Sounds["resolution_changed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| system_profiler | System Tool | Free | macOS display info |
| xrandr | X11 | Free | Linux display config |

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
| Linux | Supported | Uses xrandr |
| Windows | Not Supported | ccbell only supports macOS/Linux |
