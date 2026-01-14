# Feature: Sound Event Screen Monitor

Play sounds for screen lock, unlock, and display events.

## Summary

Monitor screen states including lock/unlock, display changes, screen saver activation, and session management events.

## Motivation

- Security awareness
- Session state feedback
- Display configuration alerts
- Privacy protection alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Screen Events

| Event | Description | Example |
|-------|-------------|---------|
| Screen Locked | Screen locked | Ctrl+Cmd+Q pressed |
| Screen Unlocked | Screen unlocked | Password entered |
| Screen Saver | Saver started | Idle timeout |
| Display Connected | External display plugged in | Monitor attached |
| Display Disconnected | External display unplugged | Monitor detached |
| Sleep | System going to sleep | Lid closed |
| Wake | System waking up | Lid opened |

### Configuration

```go
type ScreenMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    LockSound         string            `json:"lock_sound"`
    UnlockSound       string            `json:"unlock_sound"`
    SleepSound        string            `json:"sleep_sound"`
    WakeSound         string            `json:"wake_sound"`
    DisplaySound      string            `json:"display_sound"`
    NotifyDisplay     bool              `json:"notify_display_changes"`
    Sounds            map[string]string `json:"sounds"`
}

type ScreenEvent struct {
    EventType  string // "locked", "unlocked", "sleep", "wake", "display_connected", "display_disconnected"
    DisplayID  string
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:screen status             # Show screen status
/ccbell:screen sound locked <sound>
/ccbell:screen sound unlocked <sound>
/ccbell:screen sound sleep <sound>
/ccbell:screen sound wake <sound>
/ccbell:screen display on         # Enable display change sounds
/ccbell:screen test               # Test screen sounds
```

### Output

```
$ ccbell:screen status

=== Sound Event Screen Monitor ===

Status: Enabled
Display Changes: Yes

Current State:
  Status: Unlocked
  Last Unlock: 2 hours ago
  Idle Time: 15 min
  Displays: 2 connected

[1] Built-in Display
    ID: 1234567890
    Status: Active

[2] External Monitor
    ID: 0987654321
    Status: Active

Sound Settings:
  Locked: bundled:stop
  Unlocked: bundled:stop
  Sleep: bundled:stop
  Wake: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Screen monitoring doesn't play sounds directly:
- Monitoring feature using system power/display APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Screen Monitor

```go
type ScreenMonitor struct {
    config     *ScreenMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastState  string // "locked", "unlocked", "sleeping"
    displays   map[string]bool
}

func (m *ScreenMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.displays = make(map[string]bool)
    m.lastState = "unlocked"
    go m.monitor()
}

func (m *ScreenMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkScreen()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ScreenMonitor) checkScreen() {
    state := m.getScreenState()

    if state != m.lastState {
        m.onStateChange(state)
    }

    m.lastState = state
}

func (m *ScreenMonitor) getScreenState() string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSScreenState()
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxScreenState()
    }

    return "unknown"
}

func (m *ScreenMonitor) getMacOSScreenState() string {
    // Check if screen is locked using pmset or security
    cmd := exec.Command("security", "show-keychain-info")
    err := cmd.Run()

    // If command fails, keychain may be locked
    if err != nil {
        return "locked"
    }

    // Check screen saver status
    cmd = exec.Command("defaults", "read", "com.apple.screensaver", "askForPasswordDelay")
    output, _ := cmd.Output()

    if len(output) > 0 && strings.Contains(string(output), "0") {
        return "unlocked"
    }

    return "unlocked"
}

func (m *ScreenMonitor) getLinuxScreenState() string {
    // Check X session state
    cmd := exec.Command("xset", "q")
    output, err := cmd.Output()
    if err != nil {
        return "unknown"
    }

    if strings.Contains(string(output), "Monitor is Off") {
        return "sleeping"
    }

    // Check for screen lock using xdg-screensaver or dm-tool
    cmd = exec.Command("xdg-screensaver", "status")
    statusOutput, _ := cmd.Output()

    if strings.Contains(string(statusOutput), "active") {
        return "locked"
    }

    return "unlocked"
}

func (m *ScreenMonitor) onStateChange(newState string) {
    switch newState {
    case "locked":
        m.onScreenLocked()
    case "unlocked":
        if m.lastState == "locked" || m.lastState == "sleeping" {
            m.onScreenUnlocked()
        }
    case "sleeping":
        if m.lastState == "unlocked" {
            m.onScreenSleep()
        }
    }

    // Check display changes
    m.checkDisplays()
}

func (m *ScreenMonitor) checkDisplays() {
    displays := m.getDisplays()

    for id, connected := range displays {
        wasConnected := m.displays[id]
        m.displays[id] = connected

        if connected && !wasConnected {
            m.onDisplayConnected(id)
        } else if !connected && wasConnected {
            m.onDisplayDisconnected(id)
        }
    }
}

func (m *ScreenMonitor) getDisplays() map[string]bool {
    displays := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        // macOS: system_profiler
        cmd := exec.Command("system_profiler", "SPDisplaysDataType")
        output, err := cmd.Output()
        if err != nil {
            return displays
        }

        // Parse display info
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "Resolution:") {
                id := strings.TrimSpace(line)
                displays[id] = true
            }
        }
    } else if runtime.GOOS == "linux" {
        // Linux: xrandr
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
    }

    return displays
}

func (m *ScreenMonitor) onScreenLocked() {
    sound := m.config.LockSound
    if sound == "" {
        sound = m.config.Sounds["locked"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenMonitor) onScreenUnlocked() {
    sound := m.config.UnlockSound
    if sound == "" {
        sound = m.config.Sounds["unlocked"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenMonitor) onScreenSleep() {
    sound := m.config.SleepSound
    if sound == "" {
        sound = m.config.Sounds["sleep"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenMonitor) onScreenWake() {
    sound := m.config.WakeSound
    if sound == "" {
        sound = m.config.Sounds["wake"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenMonitor) onDisplayConnected(displayID string) {
    if !m.config.NotifyDisplay {
        return
    }

    sound := m.config.DisplaySound
    if sound == "" {
        sound = m.config.Sounds["display_connected"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenMonitor) onDisplayDisconnected(displayID string) {
    if !m.config.NotifyDisplay {
        return
    }

    sound := m.config.Sounds["display_disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| security | System Tool | Free | macOS keychain |
| xset | X11 | Free | X display settings |
| xrandr | X11 | Free | X display configuration |
| xdg-screensaver | FreeDesktop | Free | Screensaver status |

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
| macOS | Supported | Uses security and system_profiler |
| Linux | Supported | Uses xset, xrandr, xdg-screensaver |
| Windows | Not Supported | ccbell only supports macOS/Linux |
