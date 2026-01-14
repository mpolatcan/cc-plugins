# Feature: Sound Notifications

Desktop notifications for sound events.

## Summary

Show desktop notifications when sounds are played or when configuration changes occur.

## Motivation

- Visual confirmation
- Accessibility support
- Multi-modal feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Notification Types

| Type | Description | Example |
|------|-------------|---------|
| On Play | Sound is playing | "Playing: stop sound" |
| On Fail | Playback failed | "Failed to play sound" |
| On Config | Config changed | "Volume updated" |
| On Install | New sound installed | "Sound installed" |

### Configuration

```go
type NotificationConfig struct {
    Enabled         bool     `json:"enabled"`
    ShowOnPlay      bool     `json:"show_on_play"`
    ShowOnFail      bool     `json:"show_on_fail"`
    ShowOnConfig    bool     `json:"show_on_config"`
    Title           string   `json:"title"` // "CCBell"
    Icon            string   `json:"icon"`  // icon path
    TimeoutSec      int      `json:"timeout_sec"`
    Sound           string   `json:"sound"` // notification sound
}

type NotificationState struct {
    LastNotification time.Time `json:"last_notification"`
    Suppressed       bool      `json:"suppressed"`
}
```

### Commands

```bash
/ccbell:notify enable               # Enable notifications
/ccbell:notify disable              # Disable notifications
/ccbell:notify on-play enable       # Show on play
/ccbell:notify on-play disable      # Hide on play
/ccbell:notify set title "CCBell"   # Set title
/ccbell:notify set timeout 5        # 5 second timeout
/ccbell:notify test                 # Test notification
/ccbell:notify suppress 60          # Suppress for 60s
```

### Output

```
$ ccbell:notify test

=== Testing Desktop Notification ===

[████████████████████████]
CCBell

Sound played: bundled:stop

[Close]

Notification sent successfully
[Configure] [Disable]
```

---

## Audio Player Compatibility

Notifications don't play sounds:
- Display feature
- No player changes required
- Uses system notification APIs

---

## Implementation

### macOS Notifications

```go
func (n *NotificationManager) showMacOS(title, message string) error {
    script := fmt.Sprintf(`
tell application "System Events"
    display notification "%s" with title "%s"
end tell
    `, message, title)

    cmd := exec.Command("osascript", "-e", script)
    return cmd.Run()
}
```

### Linux Notifications

```go
func (n *NotificationManager) showLinux(title, message string) error {
    // Use notify-send
    args := []string{
        "-a", "ccbell",
        "-t", fmt.Sprintf("%d000", n.config.TimeoutSec),
        title,
        message,
    }

    if n.config.Icon != "" {
        args = append(args, "-i", n.config.Icon)
    }

    cmd := exec.Command("notify-send", args...)
    return cmd.Run()
}
```

### Notification Filtering

```go
func (n *NotificationManager) shouldShow(event string) bool {
    switch event {
    case "on_play":
        return n.config.ShowOnPlay
    case "on_fail":
        return n.config.ShowOnFail
    case "on_config":
        return n.config.ShowOnConfig
    default:
        return false
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| notify-send | External tool | Free | Linux desktop notifications |
| osascript | System tool | Free | macOS notifications |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Play hook

### Research Sources

- [notify-send](https://manpages.debian.org/stable/libnotify-bin/notify-send.1.en.html)
- [macOS notifications](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/DisplayNotificationsandAlerts.html)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via osascript |
| Linux | ✅ Supported | Via notify-send |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
