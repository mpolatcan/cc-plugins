# Feature: Sound Event Keyboard Shortcut Monitor

Play sounds for custom keyboard shortcut activations.

## Summary

Monitor keyboard shortcut activations and hotkey triggers, playing sounds when shortcuts are pressed.

## Motivation

- Shortcut feedback
- Productivity tracking
- Macro activation alerts
- Workflow awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Keyboard Shortcut Events

| Event | Description | Example |
|-------|-------------|---------|
| Shortcut Pressed | Hotkey combination | Cmd+Space |
| Macro Triggered | Automation activated | Custom shortcut |
| Text Expansion | Snippet triggered | --email |
| App Shortcut | Application shortcut | Cmd+N |

### Configuration

```go
type KeyboardShortcutMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchShortcuts []string          `json:"watch_shortcuts"` // "cmd+space", "ctrl+c"
    SoundOnShortcut bool             `json:"sound_on_shortcut"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 1 default
}

type KeyboardShortcutEvent struct {
    Shortcut string
    AppName  string
    EventType string // "shortcut", "macro", "expansion"
}
```

### Commands

```bash
/ccbell:shortcut status              # Show shortcut status
/ccbell:shortcut add "cmd+space"     # Add shortcut to watch
/ccbell:shortcut remove "cmd+space"
/ccbell:shortcut sound <shortcut> <sound>
/ccbell:shortcut test                # Test shortcut sounds
```

### Output

```
$ ccbell:shortcut status

=== Sound Event Keyboard Shortcut Monitor ===

Status: Enabled
Watched Shortcuts: 4

[1] Cmd+Space
    App: Global
    Triggers Today: 245
    Sound: bundled:stop

[2] Cmd+C
    App: Global
    Triggers Today: 1234
    Sound: bundled:stop

[3] Cmd+V
    App: Global
    Triggers Today: 892
    Sound: bundled:stop

[4] Ctrl+Shift+T
    App: Terminal
    Triggers Today: 12
    Sound: bundled:stop

Recent Events:
  [1] Cmd+Space (5 min ago)
  [2] Cmd+C (10 min ago)
  [3] Cmd+V (15 min ago)

Top Shortcuts Today:
  1. Cmd+C: 1234
  2. Cmd+V: 892
  3. Cmd+Space: 245
  4. Cmd+A: 156

Sound Settings:
  Cmd+Space: bundled:stop
  Cmd+C: bundled:stop
  Cmd+V: bundled:stop

[Configure] [Add Shortcut] [Test All]
```

---

## Audio Player Compatibility

Keyboard shortcut monitoring doesn't play sounds directly:
- Monitoring feature using input event tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Keyboard Shortcut Monitor

```go
type KeyboardShortcutMonitor struct {
    config          *KeyboardShortcutMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    shortcutCount   map[string]int
    lastTriggerTime map[string]time.Time
}

func (m *KeyboardShortcutMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.shortcutCount = make(map[string]int)
    m.lastTriggerTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *KeyboardShortcutMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkShortcuts()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KeyboardShortcutMonitor) checkShortcuts() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinShortcuts()
    } else {
        m.checkLinuxShortcuts()
    }
}

func (m *KeyboardShortcutMonitor) checkDarwinShortcuts() {
    // Use logging to detect shortcut presses
    logPath := "/private/var/log/system.log"

    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        // Look for accessibility or spotlight events
        if strings.Contains(line, "com.apple.Spotlight") ||
           strings.Contains(line, "NSFileSystemVolume") {
            m.onShortcutTriggered("Cmd+Space")
        }
    }
}

func (m *KeyboardShortcutMonitor) checkLinuxShortcuts() {
    // Check for registered shortcuts using xdotool or similar
    cmd := exec.Command("xdotool", "getactivekeys")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    keys := strings.Split(strings.TrimSpace(string(output)), "\n")
    for _, key := range keys {
        shortcut := m.normalizeShortcut(key)
        if m.shouldWatch(shortcut) {
            m.onShortcutTriggered(shortcut)
        }
    }
}

func (m *KeyboardShortcutMonitor) normalizeShortcut(key string) string {
    // Normalize key to standard format
    key = strings.ToLower(key)
    key = strings.ReplaceAll(key, "control", "ctrl")
    key = strings.ReplaceAll(key, "command", "cmd")
    key = strings.ReplaceAll(key, "option", "alt")
    key = strings.ReplaceAll(key, "super", "win")
    return key
}

func (m *KeyboardShortcutMonitor) shouldWatch(shortcut string) bool {
    if len(m.config.WatchShortcuts) == 0 {
        return true
    }

    for _, watch := range m.config.WatchShortcuts {
        if shortcut == watch {
            return true
        }
    }
    return false
}

func (m *KeyboardShortcutMonitor) onShortcutTriggered(shortcut string) {
    if !m.config.SoundOnShortcut {
        return
    }

    // Debounce: don't repeat same shortcut within 500ms
    if lastTime := m.lastTriggerTime[shortcut]; lastTime.Add(500*time.Millisecond).After(time.Now()) {
        return
    }

    m.lastTriggerTime[shortcut] = time.Now()
    m.shortcutCount[shortcut]++

    // Check if custom sound exists for this shortcut
    sound := m.config.Sounds[shortcut]
    if sound == "" {
        sound = m.config.Sounds["default"]
    }

    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| xdotool | System Tool | Free | Linux X11 automation |
| /var/log/system.log | File | Free | macOS system log |

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
| macOS | Supported | Uses system log |
| Linux | Supported | Uses xdotool |
| Windows | Not Supported | ccbell only supports macOS/Linux |
