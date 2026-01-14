# Feature: Sound Event X11 Event Monitor

Play sounds for X11 server events and display changes.

## Summary

Monitor X11 server status, display changes, and application focus events, playing sounds for X11 events.

## Motivation

- X11 awareness
- Display change feedback
- Focus detection
- Session management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### X11 Events

| Event | Description | Example |
|-------|-------------|---------|
| Display Changed | Display variable changed | :0 -> :1 |
| X11 Started | X server started | startx |
| X11 Stopped | X server stopped | X server killed |
| Window Focus | Focus changed | New active window |

### Configuration

```go
type X11MonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchDisplays      []string          `json:"watch_displays"] // ":0", ":1"
    SoundOnDisplay     bool              `json:"sound_on_display"]
    SoundOnStart       bool              `json:"sound_on_start"]
    SoundOnStop        bool              `json:"sound_on_stop"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type X11Event struct {
    Display   string
    Server    string
    PID       int
    EventType string // "display_change", "start", "stop", "focus"
}
```

### Commands

```bash
/ccbell:x11 status                    # Show X11 status
/ccbell:x11 add :0                    # Add display to watch
/ccbell:x11 remove :0
/ccbell:x11 sound start <sound>
/ccbell:x11 sound display <sound>
/ccbell:x11 test                      # Test X11 sounds
```

### Output

```
$ ccbell:x11 status

=== Sound Event X11 Monitor ===

Status: Enabled
Display Sounds: Yes
Start Sounds: Yes

Watched Displays: 1

[1] :0
    Server: /usr/bin/X
    PID: 1234
    Status: RUNNING
    Clients: 15
    Sound: bundled:stop

Recent Events:
  [1] :0: X11 Started (5 min ago)
       PID: 1234
  [2] :0: Display Changed (1 hour ago)
       DISPLAY=:0
  [3] :0: Client Connected (2 hours ago)
       New client: firefox

X11 Statistics:
  Uptime: 5 hours
  Clients connected: 15

Sound Settings:
  Start: bundled:x11-start
  Stop: bundled:x11-stop
  Display: bundled:stop

[Configure] [Add Display] [Test All]
```

---

## Audio Player Compatibility

X11 monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### X11 Event Monitor

```go
type X11Monitor struct {
    config          *X11MonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    x11State        map[string]*X11Info
    lastEventTime   map[string]time.Time
}

type X11Info struct {
    Display   string
    Server    string
    PID       int
    Running   bool
}

func (m *X11Monitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.x11State = make(map[string]*X11Info)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *X11Monitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotX11State()

    for {
        select {
        case <-ticker.C:
            m.checkX11State()
        case <-m.stopCh:
            return
        }
    }
}

func (m *X11Monitor) snapshotX11State() {
    // Check DISPLAY environment variable
    display := os.Getenv("DISPLAY")
    if display == "" {
        return
    }

    m.checkX11Display(display)
}

func (m *X11Monitor) checkX11State() {
    display := os.Getenv("DISPLAY")
    if display == "" {
        // X might have stopped
        for name, info := range m.x11State {
            if info.Running {
                m.onX11Stopped(name, info)
                info.Running = false
            }
        }
        return
    }

    m.checkX11Display(display)
}

func (m *X11Monitor) checkX11Display(display string) {
    // Get X server info
    cmd := exec.Command("ps", "aux")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Check if X is running for this display
    xPattern := fmt.Sprintf("X %s", display)
    xRunning := strings.Contains(string(output), xPattern)

    lastInfo := m.x11State[display]
    if lastInfo == nil {
        // First time seeing this display
        m.x11State[display] = &X11Info{
            Display: display,
            Running: xRunning,
        }

        if xRunning {
            m.onX11Started(display, nil)
        }
        return
    }

    // Check state changes
    if xRunning && !lastInfo.Running {
        m.onX11Started(display, lastInfo)
    } else if !xRunning && lastInfo.Running {
        m.onX11Stopped(display, lastInfo)
    }

    // Check display change
    if lastInfo.Display != display {
        m.onDisplayChanged(display, lastInfo)
    }

    lastInfo.Running = xRunning
    lastInfo.Display = display
}

func (m *X11Monitor) onX11Started(display string, lastInfo *X11Info) {
    if !m.config.SoundOnStart {
        return
    }

    if !m.shouldWatchDisplay(display) {
        return
    }

    key := fmt.Sprintf("start:%s", display)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *X11Monitor) onX11Stopped(display string, lastInfo *X11Info) {
    if !m.config.SoundOnStop {
        return
    }

    key := fmt.Sprintf("stop:%s", display)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["stop"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *X11Monitor) onDisplayChanged(display string, lastInfo *X11Info) {
    if !m.config.SoundOnDisplay {
        return
    }

    if lastInfo != nil && !m.shouldWatchDisplay(lastInfo.Display) {
        return
    }

    key := fmt.Sprintf("display:%s->%s", lastInfo.Display, display)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["display"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *X11Monitor) shouldWatchDisplay(display string) bool {
    if len(m.config.WatchDisplays) == 0 {
        return true
    }

    for _, d := range m.config.WatchDisplays {
        if d == display {
            return true
        }
    }

    return false
}

func (m *X11Monitor) shouldAlert(key string, interval time.Duration) bool {
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
| ps | System Tool | Free | Process listing |
| DISPLAY | Environment | Free | X11 display |

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
| macOS | Not Supported | No native X11 |
| Linux | Supported | Uses DISPLAY env, ps |
| Windows | Not Supported | ccbell only supports macOS/Linux |
