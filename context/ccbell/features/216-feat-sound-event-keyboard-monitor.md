# Feature: Sound Event Keyboard Monitor

Play sounds for keyboard activity and shortcut events.

## Summary

Monitor keyboard activity, detecting key presses, shortcut combinations, and typing patterns, playing sounds for specific keyboard events.

## Motivation

- Keyboard shortcut confirmation
- Typing efficiency feedback
- Caps lock state changes
- Key binding alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Keyboard Events

| Event | Description | Example |
|-------|-------------|---------|
| Key Press | Individual key press | Any key pressed |
| Shortcut | Special combination | Cmd+C, Ctrl+Alt+Del |
| Caps Lock | Caps state toggle | On/Off |
| Fast Typing | Typing speed alert | > 100 WPM |
| Keyboard Idle | Extended idle period | 5 min no typing |

### Configuration

```go
type KeyboardMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchShortcuts   []*KeyboardShortcut `json:"watch_shortcuts"`
    SoundOnTyping    bool              `json:"sound_on_typing"`
    TypingSpeedThreshold int           `json:"typing_speed_threshold_wpm"` // 100 default
    IdleTimeout      int               `json:"idle_timeout_sec"` // 300 default
    Sounds           map[string]string `json:"sounds"`
}

type KeyboardShortcut struct {
    Name       string  `json:"name"`
    Keys       []string `json:"keys"` // ["cmd", "c"]
    Modifiers  []string `json:"modifiers"` // ["ctrl", "alt"]
    Sound      string  `json:"sound"`
    Enabled    bool    `json:"enabled"`
}

type KeyboardEvent struct {
    Key        string
    Modifiers  []string
    Timestamp  time.Time
    TypingSpeed float64 // WPM
}
```

### Commands

```bash
/ccbell:keyboard status            # Show keyboard status
/ccbell:keyboard add "Copy" --keys cmd+c
/ccbell:keyboard remove "Copy"
/ccbell:keyboard sound typing <sound>
/ccbell:keyboard sound caps_on <sound>
/ccbell:keyboard test              # Test keyboard sounds
```

### Output

```
$ ccbell:keyboard status

=== Sound Event Keyboard Monitor ===

Status: Enabled
Typing Speed Threshold: 100 WPM
Idle Timeout: 300s

Watched Shortcuts: 4

[1] Copy
    Keys: Cmd+C
    Sound: bundled:stop
    [Edit] [Remove]

[2] Paste
    Keys: Cmd+V
    Sound: bundled:stop
    [Edit] [Remove]

[3] Undo
    Keys: Cmd+Z
    Sound: bundled:stop
    [Edit] [Remove]

[4] Screenshot
    Keys: Cmd+Shift+4
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] Copy: Pressed (2 min ago)
  [2] Undo: Pressed (5 min ago)
  [3] Screenshot: Pressed (1 hour ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Keyboard monitoring doesn't play sounds directly:
- Monitoring feature using system input APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Keyboard Monitor

```go
type KeyboardMonitor struct {
    config        *KeyboardMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastKeyTime   time.Time
    keyCount      int
    lastWPMCheck  time.Time
    currentWPM    float64
    lastStatus    *KeyboardEvent
}

func (m *KeyboardMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastKeyTime = time.Now()
    go m.monitor()
}

func (m *KeyboardMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkKeyboard()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KeyboardMonitor) checkKeyboard() {
    now := time.Now()

    // Check for idle timeout
    if now.Sub(m.lastKeyTime) > time.Duration(m.config.IdleTimeout)*time.Second {
        m.onKeyboardIdle()
    }

    // Calculate typing speed every 10 seconds
    if now.Sub(m.lastWPMCheck) > 10*time.Second {
        m.calculateTypingSpeed()
    }
}

func (m *KeyboardMonitor) calculateTypingSpeed() {
    elapsed := time.Since(m.lastWPMCheck)
    if elapsed > 0 {
        m.currentWPM = float64(m.keyCount) / (elapsed.Seconds() / 60)
    }
    m.keyCount = 0
    m.lastWPMCheck = time.Now()

    // Check threshold
    if m.currentWPM >= float64(m.config.TypingSpeedThreshold) {
        m.onFastTyping()
    }
}

func (m *KeyboardMonitor) onKeyPress(event *KeyboardEvent) {
    m.lastKeyTime = time.Now()
    m.keyCount++

    // Check for caps lock
    if event.Key == "caps_lock" {
        m.onCapsLock(event)
        return
    }

    // Check watched shortcuts
    for _, shortcut := range m.config.WatchShortcuts {
        if shortcut.Enabled && m.matchesShortcut(event, shortcut) {
            m.onShortcut(shortcut)
            return
        }
    }
}

func (m *KeyboardMonitor) matchesShortcut(event *KeyboardEvent, shortcut *KeyboardShortcut) bool {
    // Check if event keys match shortcut
    for _, mod := range shortcut.Modifiers {
        found := false
        for _, eventMod := range event.Modifiers {
            if mod == eventMod {
                found = true
                break
            }
        }
        if !found {
            return false
        }
    }

    for _, key := range shortcut.Keys {
        if key == event.Key {
            return true
        }
    }

    return false
}

func (m *KeyboardMonitor) onShortcut(shortcut *KeyboardShortcut) {
    sound := shortcut.Sound
    if sound == "" {
        sound = m.config.Sounds["shortcut"]
    }
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *KeyboardMonitor) onCapsLock(event *KeyboardEvent) {
    sound := m.config.Sounds["caps_on"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *KeyboardMonitor) onFastTyping() {
    sound := m.config.Sounds["fast_typing"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *KeyboardMonitor) onKeyboardIdle() {
    sound := m.config.Sounds["idle"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Input monitoring | macOS API | Free | Keyboard events |
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
| macOS | Supported | Uses Input Monitoring API |
| Linux | Supported | Uses /dev/input or X11 |
| Windows | Not Supported | ccbell only supports macOS/Linux |
