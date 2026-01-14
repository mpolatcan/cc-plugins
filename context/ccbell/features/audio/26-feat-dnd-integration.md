# Feature: Do Not Disturb Integration

Respect system Do Not Disturb mode for notifications.

## Summary

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled.

## Motivation

- Avoid notifications during meetings
- Respect user focus time
- Prevent noise during presentations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---


## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Technical Feasibility

### Platform DND Detection

| Platform | Method | Native Support | Feasibility |
|----------|--------|----------------|-------------|
| macOS | `defaults read` | Yes | ✅ Easy |
| macOS | `osascript` | Yes | ✅ Easy |
| Linux (GNOME) | `gsettings` | Yes | ✅ Easy |
| Linux (KDE) | `qdbus` | Yes | ✅ Easy |
| Linux (general) | `dbus` | Yes | ⚠️ Moderate |

### macOS Implementation

```bash
# Check DND status via defaults
defaults -currentHost read com.apple.notificationcenterui doNotDisturb

# Or via osascript
osascript -e 'tell application "System Events" to get bundle identifier of every process whose background only is true'
```

### Linux Implementation (GNOME)

```bash
# Check DND via gsettings
gsettings get org.gnome.desktop.notifications show-banners

# Check via dbus
dbus-send --session --type=method_call --print-reply \
    --dest=org.gnome.Shell \
    /org/gnome/Shell \
    org.gnome.Shell.Eval \
    'Main.notificationQueue._doNotDisturb'
```

### Implementation

```go
func isDoNotDisturb() (bool, error) {
    switch detectPlatform() {
    case PlatformMacOS:
        return checkMacOSDND()
    case PlatformLinux:
        return checkLinuxDND()
    }
    return false, nil
}

func checkMacOSDND() (bool, error) {
    cmd := exec.Command("defaults", "-currentHost", "read",
        "com.apple.notificationcenterui", "doNotDisturb")
    output, err := cmd.Output()
    if err != nil {
        return false, err
    }
    return strings.TrimSpace(string(output)) == "1", nil
}
```

### Configuration

```json
{
  "dnd": {
    "enabled": true,
    "respect_system_dnd": true,
    "fallback_quiet_hours": false
  }
}
```

---

## Audio Player Compatibility

DND integration doesn't interact with audio playback:
- Runs before audio player is invoked
- Uses native platform APIs only
- No changes to player required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `defaults` | Native (macOS) | Free | Built-in |
| `gsettings` | Native (GNOME) | Free | Built-in |
| `dbus-send` | Native (Linux) | Free | Built-in |

---


---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### Research Sources

- [macOS DND via defaults](https://developer.apple.com/documentation/foundation/preferences)
- [GNOME notifications](https://developer.gnome.org/notification-spec/)
- [D-Bus notification interface](https://specifications.freedesktop.org/notification-spec/)

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point for DND check
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For DND config
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91) - Platform detection

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via defaults read |
| Linux | ⚠️ Partial | GNOME/KDE supported |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
