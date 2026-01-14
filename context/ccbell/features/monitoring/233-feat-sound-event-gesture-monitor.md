# Feature: Sound Event Gesture Monitor

Play sounds for touchpad and gesture events.

## Summary

Monitor touchpad gestures including multi-touch gestures, swipe events, and tap actions, playing sounds for gesture events.

## Motivation

- Gesture feedback
- Scroll confirmation
- Desktop navigation alerts
- Accessibility support

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Gesture Events

| Event | Description | Example |
|-------|-------------|---------|
| Swipe Left | Three-finger swipe left | Desktop left |
| Swipe Right | Three-finger swipe right | Desktop right |
| Swipe Up | Three-finger swipe up | Mission Control |
| Swipe Down | Three-finger swipe down | App expose |
| Pinch | Pinch gesture | Zoom in/out |
| Tap | Tap to click | Touchpad tap |

### Configuration

```go
type GestureMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    SoundOnSwipe    bool              `json:"sound_on_swipe"`
    SoundOnPinch    bool              `json:"sound_on_pinch"`
    SoundOnTap      bool              `json:"sound_on_tap"`
    GesturesToWatch []string          `json:"gestures_to_watch"`
    Sounds          map[string]string `json:"sounds"`
}

type GestureEvent struct {
    GestureType string // "swipe_left", "swipe_right", "pinch", "tap"
    Direction   string // "left", "right", "up", "down", "in", "out"
    Fingers     int
}
```

### Commands

```bash
/ccbell:gesture status            # Show gesture status
/ccbell:gesture swipe on          # Enable swipe sounds
/ccbell:gesture pinch on          # Enable pinch sounds
/ccbell:gesture add swipe_up      # Add gesture to watch
/ccbell:gesture sound swipe <sound>
/ccbell:gesture test              # Test gesture sounds
```

### Output

```
$ ccbell:gesture status

=== Sound Event Gesture Monitor ===

Status: Enabled
Swipe Sounds: Yes
Pinch Sounds: Yes
Tap Sounds: No

Watched Gestures: 6

[1] Swipe Left
    Sound: bundled:stop
    Status: Active

[2] Swipe Right
    Sound: bundled:stop
    Status: Active

[3] Swipe Up
    Sound: bundled:stop
    Status: Active

[4] Swipe Down
    Sound: bundled:stop
    Status: Active

[5] Pinch In
    Sound: bundled:stop
    Status: Active

[6] Pinch Out
    Sound: bundled:stop
    Status: Active

Recent Events:
  [1] Swipe Left (3 fingers) - 5 min ago
  [2] Swipe Up (3 fingers) - 15 min ago
  [3] Pinch In (2 fingers) - 30 min ago

[Configure] [Add Gesture] [Test All]
```

---

## Audio Player Compatibility

Gesture monitoring doesn't play sounds directly:
- Monitoring feature using touchpad APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Gesture Monitor

```go
type GestureMonitor struct {
    config        *GestureMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastGestures  map[string]time.Time
}

func (m *GestureMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastGestures = make(map[string]time.Time)
    go m.monitor()
}

func (m *GestureMonitor) monitor() {
    ticker := time.NewTicker(100 * time.Millisecond)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkGestures()
        case <-m.stopCh:
            return
        }
    }
}

func (m *GestureMonitor) checkGestures() {
    gesture := m.detectGesture()

    if gesture != nil {
        m.onGesture(gesture)
    }
}

func (m *GestureMonitor) detectGesture() *GestureEvent {
    if runtime.GOOS == "darwin" {
        return m.detectMacOSGesture()
    }
    if runtime.GOOS == "linux" {
        return m.detectLinuxGesture()
    }
    return nil
}

func (m *GestureMonitor) detectMacOSGesture() *GestureEvent {
    // macOS: Use BetterTouchTool API or trackpad preferences
    // For now, use input monitoring

    // Check for swipe gestures via BetterTouchTool if installed
    cmd := exec.Command("pgrep", "-x", "BetterTouchTool")
    if cmd.Run() == nil {
        return m.getBetterTouchToolGesture()
    }

    // Fallback: Use defaults for trackpad settings
    return m.getTrackpadGesture()
}

func (m *GestureMonitor) getBetterTouchToolGesture() *GestureEvent {
    // Query BTT for recent gesture
    // This is a simplified version

    cmd := exec.Command("defaults", "read", "com.hegenberg.BetterTouchTool",
        "BTTLastTriggeredAction")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    gestureStr := strings.TrimSpace(string(output))
    if gestureStr == "" {
        return nil
    }

    return m.parseGestureString(gestureStr)
}

func (m *GestureMonitor) getTrackpadGesture() *GestureEvent {
    // Check trackpad gesture preferences
    cmd := exec.Command("defaults", "read", "com.apple.AppleMultitouchTrackpad",
        "TrackpadThreeFingerHorizSwipeGesture")
    _, err := cmd.Output()
    if err != nil {
        return nil
    }

    // This only tells us if gestures are enabled, not actual detection
    // Real implementation would use Input Monitoring API

    return nil
}

func (m *GestureMonitor) detectLinuxGesture() *GestureEvent {
    // Linux: Use libinput or touchpad driver
    // Check for gesture support via synaptics

    cmd := exec.Command("xinput", "list")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    if strings.Contains(string(output), "Touchpad") {
        return m.getLibinputGesture()
    }

    return nil
}

func (m *GestureMonitor) getLibinputGesture() *GestureEvent {
    // Check libinput debug-events for gestures
    // This would typically run as a daemon

    // Simplified: Check for touchegg
    cmd := exec.Command("pgrep", "-x", "touchegg")
    if cmd.Run() == nil {
        return m.getTouchEggGesture()
    }

    return nil
}

func (m *GestureMonitor) getTouchEggGesture() *GestureEvent {
    // TouchEgg configuration would indicate active gestures

    return nil
}

func (m *GestureMonitor) parseGestureString(gestureStr string) *GestureEvent {
    event := &GestureEvent{}

    if strings.Contains(gestureStr, "swipe") {
        event.GestureType = "swipe"
        if strings.Contains(gestureStr, "left") {
            event.Direction = "left"
        } else if strings.Contains(gestureStr, "right") {
            event.Direction = "right"
        } else if strings.Contains(gestureStr, "up") {
            event.Direction = "up"
        } else if strings.Contains(gestureStr, "down") {
            event.Direction = "down"
        }
    } else if strings.Contains(gestureStr, "pinch") {
        event.GestureType = "pinch"
        if strings.Contains(gestureStr, "in") {
            event.Direction = "in"
        } else {
            event.Direction = "out"
        }
    }

    return event
}

func (m *GestureMonitor) onGesture(event *GestureEvent) {
    if event == nil {
        return
    }

    key := event.GestureType + "_" + event.Direction
    lastTime := m.lastGestures[key]

    // Debounce: don't trigger if same gesture within 500ms
    if lastTime.Add(500 * time.Millisecond).After(time.Now()) {
        return
    }

    m.lastGestures[key] = time.Now()

    if !m.shouldWatchGesture(event.GestureType) {
        return
    }

    switch event.GestureType {
    case "swipe":
        m.onSwipe(event)
    case "pinch":
        m.onPinch(event)
    case "tap":
        m.onTap(event)
    }
}

func (m *GestureMonitor) shouldWatchGesture(gestureType string) bool {
    if len(m.config.GesturesToWatch) == 0 {
        return true
    }

    for _, g := range m.config.GesturesToWatch {
        if g == gestureType {
            return true
        }
    }

    return false
}

func (m *GestureMonitor) onSwipe(event *GestureEvent) {
    if !m.config.SoundOnSwipe {
        return
    }

    sound := m.config.Sounds["swipe"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *GestureMonitor) onPinch(event *GestureEvent) {
    if !m.config.SoundOnPinch {
        return
    }

    sound := m.config.Sounds["pinch"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *GestureMonitor) onTap(event *GestureEvent) {
    if !m.config.SoundOnTap {
        return
    }

    sound := m.config.Sounds["tap"]
    if sound != "" {
        m.player.Play(sound, 0.1)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| BetterTouchTool | App | Free | macOS gestures |
| touchegg | APT | Free | Linux gestures |
| xinput | X11 | Free | Linux input |

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
| macOS | Supported | Uses BetterTouchTool |
| Linux | Supported | Uses touchegg |
| Windows | Not Supported | ccbell only supports macOS/Linux |