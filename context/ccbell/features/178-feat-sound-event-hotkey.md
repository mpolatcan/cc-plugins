# Feature: Sound Event Hotkey

Trigger sounds with keyboard shortcuts.

## Summary

Play sounds when specific keyboard shortcuts are pressed.

## Motivation

- Quick manual sounds
- Custom alerts
- Workflow integration

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Hotkey Types

| Type | Description | Example |
|------|-------------|---------|
| Global | Anywhere in system | Cmd+Shift+S |
| App-Specific | Only in certain apps | Only in terminal |
| Modifier-Only | Single modifier | Caps Lock |
| Sequence | Key sequence | Ctrl+A, then B |

### Configuration

```go
type HotkeyConfig struct {
    Enabled     bool              `json:"enabled"`
    Hotkeys     map[string]*Hotkey `json:"hotkeys"`
}

type Hotkey struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Key         string   `json:"key"` // "F12", "s", "space"
    Modifiers   []string `json:"modifiers"` // "cmd", "ctrl", "shift", "option"
    Sound       string   `json:"sound"`
    Volume      float64  `json:"volume,omitempty"`
    Global      bool     `json:"global"` // System-wide
    AppBundleID string   `json:"app_bundle_id,omitempty"` // App-specific
    Repeat      bool     `json:"repeat"` // Allow repeat
}
```

### Commands

```bash
/ccbell:hotkey list                 # List hotkeys
/ccbell:hotkey create "Alert" --key F12 --sound bundled:stop --global
/ccbell:hotkey create "Quick Stop" --key s --modifiers cmd,shift --global
/ccbell:hotkey create "Terminal" --key p --modifiers ctrl --app com.apple.Terminal
/ccbell:hotkey delete <id>          # Remove hotkey
/ccbell:hotkey enable <id>          # Enable hotkey
/ccbell:hotkey disable <id>         # Disable hotkey
/ccbell:hotkey test <id>            # Test hotkey
```

### Output

```
$ ccbell:hotkey list

=== Sound Event Hotkeys ===

Status: Enabled

Hotkeys: 3

[1] Alert
    Key: F12
    Modifiers: (none)
    Global: Yes
    Sound: bundled:stop
    Status: Active
    [Edit] [Disable] [Delete]

[2] Quick Stop
    Key: S
    Modifiers: Cmd + Shift
    Global: Yes
    Sound: bundled:stop
    Status: Active
    [Edit] [Disable] [Delete]

[3] Terminal
    Key: P
    Modifiers: Ctrl
    App: Terminal
    Sound: bundled:stop
    Status: Active
    [Edit] [Disable] [Delete]

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Hotkey triggers work with all audio players:
- Manual trigger, not automatic
- No player changes required

---

## Implementation

### Hotkey Monitoring

```go
type HotkeyManager struct {
    config   *HotkeyConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
}

func (m *HotkeyManager) Start() error {
    m.running = true
    m.stopCh = make(chan struct{})

    go m.listenForHotkeys()
    return nil
}

func (m *HotkeyManager) listenForHotkeys() {
    // Register hotkeys using macOS accessibility API
    // or use a library like skhd/yabai

    for _, hotkey := range m.config.Hotkeys {
        if !hotkey.Global {
            continue
        }

        if err := m.registerHotkey(hotkey); err != nil {
            log.Debug("Failed to register hotkey %s: %v", hotkey.Name, err)
        }
    }

    <-m.stopCh
}

func (m *HotkeyManager) registerHotkey(hotkey *Hotkey) error {
    // Use macOS CGEventTap or third-party tool
    // Example using skhd:

    mods := strings.Join(hotkey.Modifiers, "-")
    combo := fmt.Sprintf("%s::%s", mods, hotkey.Key)

    cmd := exec.Command("skhd", "-k", combo)
    // skhd would call ccbell with hotkey trigger
    return cmd.Start()
}

// Alternative: Use CGEventTap for native implementation
func (m *HotkeyManager) listenWithCGEventTap() {
    // Register for key down events
    // Check for hotkey combination
    // Trigger sound if match
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| skhd | Homebrew | Free | Hotkey daemon (macOS) |
| hammerspoon | Free | Free | Automation (macOS) |
| xbindkeys | APT | Free | Hotkey daemon (Linux) |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses skhd or hammerspoon |
| Linux | ✅ Supported | Uses xbindkeys |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
