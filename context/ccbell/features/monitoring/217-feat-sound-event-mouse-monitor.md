# Feature: Sound Event Mouse Monitor

Play sounds for mouse activity and click events.

## Summary

Monitor mouse activity, detecting clicks, movements, scroll events, and gesture patterns, playing sounds for specific mouse events.

## Motivation

- Click confirmation
- Scroll position awareness
- Mouse gesture feedback
- Trackpad gesture alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Mouse Events

| Event | Description | Example |
|-------|-------------|---------|
| Left Click | Left button click | Single click |
| Right Click | Right button click | Context menu |
| Double Click | Rapid double click | File selection |
| Scroll Up | Scroll wheel up | Page up |
| Scroll Down | Scroll wheel down | Page down |
| Scroll Extreme | Edge scroll reached | Scroll limit |
| Mouse Idle | Extended idle | 5 min no movement |

### Configuration

```go
type MouseMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    ClickSounds      bool              `json:"click_sounds"`
    ScrollSounds     bool              `json:"scroll_sounds"`
    IdleTimeout      int               `json:"idle_timeout_sec"` // 300 default
    MinScrollDelta   int               `json:"min_scroll_delta"` // 5 lines
    Sounds           map[string]string `json:"sounds"`
}

type MouseEvent struct {
    Button      string
    X           int
    Y           int
    DeltaX      int
    DeltaY      int
    ClickCount  int
    Timestamp   time.Time
}
```

### Commands

```bash
/ccbell:mouse status               # Show mouse status
/ccbell:mouse clicks on            # Enable click sounds
/ccbell:mouse scroll on            # Enable scroll sounds
/ccbell:mouse sound left <sound>
/ccbell:mouse sound right <sound>
/ccbell:mouse sound scroll <sound>
/ccbell:mouse test                 # Test mouse sounds
```

### Output

```
$ ccbell:mouse status

=== Sound Event Mouse Monitor ===

Status: Enabled
Click Sounds: Yes
Scroll Sounds: Yes
Idle Timeout: 300s

Current Position:
  X: 1200
  Y: 800

Activity:
  Clicks: 145 today
  Scroll Events: 892 today
  Idle Time: 2 min

Sound Settings:
  Left Click: bundled:stop
  Right Click: bundled:stop
  Double Click: bundled:stop
  Scroll: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Mouse monitoring doesn't play sounds directly:
- Monitoring feature using system input APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Mouse Monitor

```go
type MouseMonitor struct {
    config        *MouseMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastMoveTime  time.Time
    lastX, lastY  int
    clickCount    int
    lastClickTime time.Time
}

func (m *MouseMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastMoveTime = time.Now()
    go m.monitor()
}

func (m *MouseMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkMouse()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MouseMonitor) checkMouse() {
    now := time.Now()

    // Check for idle timeout
    if now.Sub(m.lastMoveTime) > time.Duration(m.config.IdleTimeout)*time.Second {
        m.onMouseIdle()
    }
}

func (m *MouseMonitor) onMouseMove(event *MouseEvent) {
    m.lastMoveTime = time.Now()
    m.lastX = event.X
    m.lastY = event.Y

    // Check for extreme scroll
    if m.config.MinScrollDelta > 0 {
        if abs(event.DeltaY) >= m.config.MinScrollDelta {
            m.onScroll(event)
        }
    }
}

func (m *MouseMonitor) onMouseClick(event *MouseEvent) {
    m.lastMoveTime = time.Now()

    // Check for double click
    if time.Since(m.lastClickTime) < 300*time.Millisecond {
        event.ClickCount = 2
    }
    m.lastClickTime = time.Now()

    // Determine click type
    var soundEvent string
    switch event.Button {
    case "left":
        if event.ClickCount == 2 {
            soundEvent = "double_click"
        } else {
            soundEvent = "left_click"
        }
    case "right":
        soundEvent = "right_click"
    case "middle":
        soundEvent = "middle_click"
    default:
        soundEvent = "click"
    }

    m.playSound(soundEvent)
}

func (m *MouseMonitor) onScroll(event *MouseEvent) {
    if !m.config.ScrollSounds {
        return
    }

    soundEvent := "scroll"
    if event.DeltaY > 0 {
        soundEvent = "scroll_up"
    } else if event.DeltaY < 0 {
        soundEvent = "scroll_down"
    }

    m.playSound(soundEvent)
}

func (m *MouseMonitor) onMouseIdle() {
    sound := m.config.Sounds["idle"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *MouseMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.2)
    }
}

func abs(n int) int {
    if n < 0 {
        return -n
    }
    return n
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Input monitoring | macOS API | Free | Mouse events |
| /dev/input | Linux | Free | Linux input devices |
| go-evdev | Go Module | Free | Input device handling |

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
| macOS | Supported | Uses CGEvent or IOHID |
| Linux | Supported | Uses /dev/input or X11 |
| Windows | Not Supported | ccbell only supports macOS/Linux |
