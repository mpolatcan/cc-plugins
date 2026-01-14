# Feature: Do Not Disturb Integration 🔕

## Summary

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled.

## Benefit

- **Seamless focus time**: No manual toggling when entering DnD mode
- **Meeting-friendly**: Automatically silences during presentations
- **Single source of truth**: System-level DnD controls everything
- **Prevents embarrassment**: No unexpected sounds during calls

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Category** | Scheduling |

## Technical Feasibility

### Platform DND Detection

| Platform | Method | Support |
|----------|--------|---------|
| macOS | `defaults read` | ✅ Easy |
| Linux (GNOME) | `gsettings` | ✅ Easy |
| Linux (KDE) | `qdbus` | ✅ Easy |

### Implementation

```go
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
    cmd := exec.Command("defaults", "read", "com.apple.notificationcenterui", "doNotDisturb")
    out, err := cmd.Output()
    if err != nil { return false }
    return strings.TrimSpace(string(out)) == "1"
}
```

### Commands

No new commands - automatic detection.

## Configuration

```json
{
  "dnd": {
    "enabled": true,
    "behavior": "silence"
  }
}
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `DND` section |
| **Core Logic** | Add | `IsDoNotDisturb()` function |
| **New File** | Add | `internal/dnd/dnd.go` |
| **Main Flow** | Modify | Check DND before playing |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add DND section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [macOS DND via defaults](https://developer.apple.com/documentation/foundation/preferences)
- [GNOME notifications](https://developer.gnome.org/notification-spec/)
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91)

---

[Back to Feature Index](index.md)
