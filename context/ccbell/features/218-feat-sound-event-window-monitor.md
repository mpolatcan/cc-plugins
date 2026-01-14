# Feature: Sound Event Window Monitor

Play sounds for window management events.

## Summary

Monitor window focus changes, open/close events, and window state transitions, playing sounds for specific window events.

## Motivation

- Focus change awareness
- Window switching confirmation
- Application launch detection
- Workspace change alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Window Events

| Event | Description | Example |
|-------|-------------|---------|
| Window Focus | Window gained focus | Clicked on browser |
| Window Blur | Window lost focus | Clicked elsewhere |
| Window Open | New window opened | New tab opened |
| Window Closed | Window closed | Tab closed |
| Window Move | Window position changed | Dragged to new spot |
| Window Resize | Window size changed | Maximized |

### Configuration

```go
type WindowMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchApps         []string          `json:"watch_apps"` // "Safari", "Terminal"
    WatchWindows      []string          `json:"watch_windows"`
    FocusSounds       bool              `json:"focus_sounds"`
    OpenCloseSounds   bool              `json:"open_close_sounds"`
    Sounds            map[string]string `json:"sounds"`
}

type WindowEvent struct {
    AppName    string
    WindowName string
    EventType  string // "focus", "blur", "open", "close", "move", "resize"
    X, Y       int
    Width      int
    Height     int
}
```

### Commands

```bash
/ccbell:window status             # Show window status
/ccbell:window add Safari         # Add app to watch
/ccbell:window remove Safari      # Remove app
/ccbell:window sound focus <sound>
/ccbell:window sound open <sound>
/ccbell:window test               # Test window sounds
```

### Output

```
$ ccbell:window status

=== Sound Event Window Monitor ===

Status: Enabled
Focus Sounds: Yes
Open/Close Sounds: Yes

Watched Applications: 2

[1] Safari
    Windows: 3 open
    Last Focus: 5 min ago
    Sound: bundled:stop
    [Edit] [Remove]

[2] Terminal
    Windows: 1 open
    Last Focus: 1 hour ago
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] Safari: Focus gained (5 min ago)
  [2] Terminal: Window closed (30 min ago)
  [3] Safari: Window opened (1 hour ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Window monitoring doesn't play sounds directly:
- Monitoring feature using window management APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Window Monitor

```go
type WindowMonitor struct {
    config     *WindowMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastWindow map[string]*WindowEvent
}

func (m *WindowMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastWindow = make(map[string]*WindowEvent)
    go m.monitor()
}

func (m *WindowMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkWindows()
        case <-m.stopCh:
            return
        }
    }
}

func (m *WindowMonitor) checkWindows() {
    windows := m.getActiveWindows()

    for _, window := range windows {
        m.evaluateWindow(window)
    }
}

func (m *WindowMonitor) getActiveWindows() []*WindowEvent {
    var windows []*WindowEvent

    if runtime.GOOS == "darwin" {
        windows = m.getMacOSWindows()
    } else if runtime.GOOS == "linux" {
        windows = m.getLinuxWindows()
    }

    return windows
}

func (m *WindowMonitor) getMacOSWindows() []*WindowEvent {
    var windows []*WindowEvent

    // macOS: Use osascript or Accessibility API
    cmd := exec.Command("osascript", "-e",
        `tell application "System Events" to get name of every window of every process`)
    output, err := cmd.Output()
    if err != nil {
        return windows
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        window := &WindowEvent{
            WindowName: strings.TrimSpace(line),
            EventType:  "open",
        }

        // Get app name from process
        appCmd := exec.Command("osascript", "-e",
            fmt.Sprintf(`tell application "System Events" to get name of first process whose frontmost is true`))
        appOutput, _ := appCmd.Output()
        window.AppName = strings.TrimSpace(string(appOutput))

        windows = append(windows, window)
    }

    return windows
}

func (m *WindowMonitor) getLinuxWindows() []*WindowEvent {
    var windows []*WindowEvent

    // Linux: Use xdotool or wmctrl
    cmd := exec.Command("xdotool", "search", "--name", ".")
    output, err := cmd.Output()
    if err != nil {
        return windows
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        // Get window name
        nameCmd := exec.Command("xdotool", "getwindowname", line)
        nameOutput, _ := nameCmd.Output()

        // Get window class
        classCmd := exec.Command("xdotool", "getwindowclassname", line)
        classOutput, _ := classCmd.Output()

        window := &WindowEvent{
            WindowName: strings.TrimSpace(string(nameOutput)),
            AppName:    strings.TrimSpace(string(classOutput)),
            EventType:  "open",
        }

        windows = append(windows, window)
    }

    return windows
}

func (m *WindowMonitor) evaluateWindow(window *WindowEvent) {
    key := window.AppName + ":" + window.WindowName
    lastEvent := m.lastWindow[key]

    // Track new windows
    if lastEvent == nil {
        window.EventType = "open"
        m.onWindowOpen(window)
        m.lastWindow[key] = window
        return
    }

    // Check for focus changes (frontmost window)
    if window.AppName != lastEvent.AppName {
        window.EventType = "focus"
        m.onWindowFocus(window)

        // Mark last window as blurred
        lastEvent.EventType = "blur"
        m.onWindowBlur(lastEvent)
    }

    // Check for position/size changes
    if window.X != lastEvent.X || window.Y != lastEvent.Y {
        window.EventType = "move"
        m.onWindowMove(window)
    }

    if window.Width != lastEvent.Width || window.Height != lastEvent.Height {
        window.EventType = "resize"
        m.onWindowResize(window)
    }

    m.lastWindow[key] = window
}

func (m *WindowMonitor) onWindowOpen(window *WindowEvent) {
    if !m.config.OpenCloseSounds {
        return
    }

    // Check if app is watched
    if m.isWatchedApp(window.AppName) {
        m.playSound("open")
    }
}

func (m *WindowMonitor) onWindowClose(window *WindowEvent) {
    if !m.config.OpenCloseSounds {
        return
    }

    delete(m.lastWindow, window.AppName+":"+window.WindowName)
    m.playSound("close")
}

func (m *WindowMonitor) onWindowFocus(window *WindowEvent) {
    if !m.config.FocusSounds {
        return
    }

    if m.isWatchedApp(window.AppName) {
        m.playSound("focus")
    }
}

func (m *WindowMonitor) onWindowBlur(window *WindowEvent) {
    if !m.config.FocusSounds {
        return
    }

    m.playSound("blur")
}

func (m *WindowMonitor) onWindowMove(window *WindowEvent) {
    m.playSound("move")
}

func (m *WindowMonitor) onWindowResize(window *WindowEvent) {
    m.playSound("resize")
}

func (m *WindowMonitor) isWatchedApp(appName string) bool {
    for _, app := range m.config.WatchApps {
        if strings.Contains(strings.ToLower(appName), strings.ToLower(app)) {
            return true
        }
    }
    return len(m.config.WatchApps) == 0
}

func (m *WindowMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| osascript | System Tool | Free | macOS Automation |
| Accessibility API | macOS API | Free | Window access |
| xdotool | APT | Free | Linux X11 automation |
| wmctrl | APT | Free | Window manager control |

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
| macOS | Supported | Uses osascript/Accessibility API |
| Linux | Supported | Uses xdotool or wmctrl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
