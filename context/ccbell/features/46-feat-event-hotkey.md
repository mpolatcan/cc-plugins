# Feature: Event Hotkey

Keyboard shortcut to trigger notification events.

## Summary

Define keyboard shortcuts to manually trigger notification events for testing and quick access.

## Motivation

- Quickly test sounds without waiting for events
- Use as a bell for attention
- Manual notification triggering

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Platform Hotkey Methods

| Platform | Method | Native Support | Feasibility |
|----------|--------|----------------|-------------|
| macOS | `cliclick` | No | ⚠️ Requires install |
| macOS | AppleScript | Yes | ✅ Easy |
| Linux | `xdotool` | No | ⚠️ Requires install |
| Linux | `xvkbd` | No | ⚠️ Requires install |
| Both | Shell alias | Yes | ✅ Easy |

### macOS Implementation (AppleScript)

```bash
# Simulate function key press via AppleScript
osascript -e 'tell application "System Events" to key code 107'

# Or use third-party tool
cliclick kp: KP_Enter
```

### Shell Alias Approach (Cross-platform)

```bash
# In shell profile
alias bell-stop='ccbell stop --dry-run'
alias bell-test='ccbell test all'
```

### Configuration

```json
{
  "hotkeys": {
    "enabled": true,
    "test_sound": "f12",
    "emergency_stop": "cmd+ctrl+shift+e",
    "mute_all": "cmd+ctrl+shift+m"
  }
}
```

### Commands

```bash
/ccbell:hotkey bind f12 stop         # Bind F12 to stop event
/ccbell:hotkey bind f12 test-stop    # Bind F12 to test stop
/ccbell:hotkey unbind f12            # Remove binding
/ccbell:hotkey list                  # Show all bindings
/ccbell:hotkey test f12              # Test hotkey
```

### Hotkey Trigger

```go
func handleHotkey(key string) error {
    binding, ok := config.Hotkeys[key]
    if !ok {
        return fmt.Errorf("no binding for key: %s", key)
    }

    switch binding.Action {
    case "test":
        return triggerTest(binding.Event)
    case "stop":
        return triggerEvent(binding.Event)
    case "mute":
        return toggleMute(true)
    case "unmute":
        return toggleMute(false)
    }

    return nil
}
```

---

## Audio Player Compatibility

Hotkey triggering uses existing audio player:
- Same `player.Play()` method
- Same format support
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Shell alias | Native | Free | Built-in |
| cliclick | Optional | Free | `brew install cliclick` |
| xdotool | Optional | Free | Linux package |

---

## References

### Research Sources

- [macOS key codes](https:// Eastman/ Eastman)
- [cliclick](https:// Eastman.com/cliclick/)
- [xdotool](https:// Eastman.semicomplete.com/projects/xdotool/)

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event triggering
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ⚠️ Partial | AppleScript or cliclick |
| Linux | ⚠️ Partial | xdotool or shell alias |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
