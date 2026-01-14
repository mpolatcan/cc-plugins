# Feature: Sound Shortcuts

Assign keyboard shortcuts to play sounds.

## Summary

Create keyboard shortcuts that trigger sound playback.

## Motivation

- Quick sound testing
- Manual triggers
- Sound board functionality

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Shortcut Types

| Type | Description | Example |
|------|-------------|---------|
| Global | System-wide shortcut | Cmd+Shift+S |
| Terminal | Terminal-only shortcut | Ctrl+G |
| Desktop | Desktop environment | D-Bus |

### Configuration

```go
type SoundShortcut struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Sound       string   `json:"sound"`
    Volume      float64  `json:"volume"`
    KeyCombo    string   `json:"key_combo"`    // "Cmd+Shift+S"
    Platform    string   `json:"platform"`     // "macos", "linux", "*"
    Enabled     bool     `json:"enabled"`
    Repeatable  bool     `json:"repeatable"`   // allow key repeat
}

type ShortcutConfig struct {
    Shortcuts   []*SoundShortcut `json:"shortcuts"`
    ListenerPort int             `json:"listener_port"` // for IPC
}
```

### Commands

```bash
/ccbell:shortcut list                    # List shortcuts
/ccbell:shortcut add "Test Stop" --key Cmd+Shift+S --sound bundled:stop
/ccbell:shortcut add "Alert" --key Ctrl+Alt+A --sound custom:alert
/ccbell:shortcut enable <id>             # Enable shortcut
/ccbell:shortcut disable <id>            # Disable shortcut
/ccbell:shortcut test <id>               # Test shortcut
/ccbell:shortcut remove <id>             # Remove shortcut
/ccbell:shortcut daemon                  # Start shortcut listener
```

### Output

```
$ ccbell:shortcut list

=== Sound Shortcuts ===

[1] Test Stop
    Sound: bundled:stop
    Key: Cmd+Shift+S
    Platform: macOS
    Enabled: Yes
    [Test] [Edit] [Remove]

[2] Alert Sound
    Sound: custom:alert.aiff
    Key: Ctrl+Alt+A
    Platform: Linux
    Enabled: Yes
    [Test] [Edit] [Remove]

[3] Notification
    Sound: bundled:idle_prompt
    Key: F12
    Platform: *
    Enabled: No
    [Test] [Edit] [Remove]

[Add New] [Start Daemon]
```

---

## Audio Player Compatibility

Shortcuts use existing audio player:
- Calls `player.Play()` on shortcut trigger
- Same format support
- No player changes required

---

## Implementation

### macOS Shortcuts

```go
func (s *ShortcutManager) registerMacOS(shortcut *SoundShortcut) error {
    // Use AppleScript for global hotkeys via Hammerspoon or similar
    script := fmt.Sprintf(`
tell application "System Events"
    set the clipboard to "%s"
end tell
    `, shortcut.KeyCombo)

    // Alternative: Use skhd or Hammerspoon integration
    // This requires external tools on macOS
    return nil
}
```

### Linux Shortcuts

```go
func (s *ShortcutManager) registerLinux(shortcut *SoundShortcut) error {
    // Register via D-Bus
    // Use xbindkeys or sxhkd configuration

    config := fmt.Sprintf("\"ccbell play %s --volume %.2f\"\n  %s",
        shortcut.Sound, shortcut.Volume, shortcut.KeyCombo)

    // Write to xbindkeys config
    configPath := filepath.Join(os.Getenv("HOME"), ".xbindkeysrc")
    appendToFile(configPath, config)

    // Reload xbindkeys
    exec.Command("pkill", "-HUP", "xbindkeys").Run()

    return nil
}
```

### IPC Listener

```go
func (s *ShortcutManager) startListener() error {
    listener, err := net.Listen("tcp", fmt.Sprintf(":%d", s.config.ListenerPort))
    if err != nil {
        return err
    }

    for {
        conn, err := listener.Accept()
        if err != nil {
            continue
        }

        go func(conn net.Conn) {
            defer conn.Close()

            soundID, _ := io.ReadAll(conn)
            s.player.Play(string(soundID), 0.5)
        }(conn)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| xbindkeys | External tool | Free | Linux keyboard shortcuts |
| Hammerspoon | External tool | Free | macOS hotkeys |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via Hammerspoon/applescript |
| Linux | ✅ Supported | Via xbindkeys/sxhkd |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
