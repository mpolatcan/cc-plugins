# Feature: Do Not Disturb Integration 🔕

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled.

## Motivation

- Avoid notifications during meetings
- Respect user focus time
- Prevent noise during presentations

---

## Benefit

- **Seamless focus time**: No need to manually toggle ccbell when entering DnD mode
- **Meeting-friendly**: Automatically silences during screen-sharing presentations
- **Single source of truth**: System-level DnD controls everything, reducing cognitive load
- **Prevents embarrassment**: No unexpected sounds during client calls or pair programming

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Category** | Scheduling |

---

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `DND` section with enabled, mode, respect options |
| **Core Logic** | Add | Add `IsDoNotDisturb() bool` function |
| **New File** | Add | `internal/dnd/dnd.go` for platform-specific DND detection |
| **Main Flow** | Modify | Check DND status before playing sound |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add DND configuration section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/dnd/dnd.go:**
```go
type DNDManager struct{}

func (d *DNDManager) IsDoNotDisturb() bool {
    switch runtime.GOOS {
    case "darwin":
        return d.isMacOSDND()
    case "linux":
        return d.isLinuxDND()
    }
    return false
}

func (d *DNDManager) isMacOSDND() bool {
    // Check macOS Notification Center DND status
    cmd := exec.Command("defaults", "read", "com.apple.notificationcenterui", "doNotDisturb")
    out, err := cmd.Output()
    if err != nil { return false }
    return strings.TrimSpace(string(out)) == "1"
}

func (d *DNDManager) isLinuxDND() bool {
    // Try gsettings (GNOME)
    cmd := exec.Command("gsettings", "get", "org.gnome.desktop.notifications", "show-banners")
    out, err := cmd.Output()
    if err == nil {
        if strings.TrimSpace(string(out)) == "false" { return true }
    }

    // Try D-Bus
    cmd = exec.Command("dbus-send", "--session",
        "--type=method_call", "--print-reply",
        "--dest=org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus.GetNameOwner",
        "string:org.gnome.Shell")
    return cmd.Run() != nil // Simplified check
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    cfg := config.Load()
    dnd := dnd.NewManager()

    // Check DND before proceeding
    if cfg.DND.Enabled && dnd.IsDoNotDisturb() {
        if cfg.DND.Behavior == "silence" {
            return // Exit silently
        }
        log.Info("Do Not Disturb active, but notifications enabled")
    }
}
```

**ccbell - internal/config/config.go:**
```go
type DNDConfig struct {
    Enabled  *bool    `json:"enabled,omitempty"`
    Behavior string   `json:"behavior,omitempty"` // "silence" or "notify"
    Except   []string `json:"except,omitempty"`   // Events that bypass DND
}
```

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

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/configure.md` with DND integration settings |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `dnd` section to config (see Configuration section)
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/configure.md` (add DND configuration section)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag
- **Platform Detection**: Uses `defaults` (macOS) or `gsettings`/`dbus` (Linux)

### Implementation Checklist

- [ ] Update `commands/configure.md` with DND integration options
- [ ] Document platform-specific DND detection methods
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via defaults read |
| Linux | ⚠️ Partial | GNOME/KDE supported |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
