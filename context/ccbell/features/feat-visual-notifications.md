# Feature: Visual Notifications 👁️

## Summary

Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger. Users who are deaf or hard of hearing, or work in noisy environments, benefit from visual alerts.

## Benefit

- **Accessibility compliance**: Supports users with hearing differences
- **Noise-restricted environments**: Works in libraries, meetings, shared spaces
- **Multi-modal feedback**: See and hear notifications for better awareness
- **Screen periphery awareness**: Notifications appear without interrupting workflow

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Category** | Display |

## Technical Feasibility

### Configuration

```json
{
  "visual": {
    "enabled": true,
    "mode": "both",
    "notifications": {
      "stop": {
        "enabled": true,
        "message": "Claude finished",
        "urgency": "low"
      },
      "permission_prompt": {
        "enabled": true,
        "message": "Permission needed",
        "urgency": "critical"
      },
      "idle_prompt": {
        "enabled": true,
        "message": "Claude is waiting",
        "urgency": "low"
      },
      "subagent": {
        "enabled": true,
        "message": "Subagent task complete",
        "urgency": "normal"
      }
    }
  }
}
```

### Implementation

```go
type VisualNotifier interface {
    Notify(title, message string, urgency Urgency) error
    Supported() bool
}

type Urgency string

const (
    UrgencyLow      Urgency = "low"
    UrgencyNormal   Urgency = "normal"
    UrgencyCritical Urgency = "critical"
)

func (n *MacOSNotifier) Notify(title, message string, urgency Urgency) error {
    script := fmt.Sprintf(`display notification "%s" with title "%s"`,
        escapeAppleScript(message),
        escapeAppleScript(title))
    cmd := exec.Command("sh", "-c", script)
    return cmd.Run()
}

func (n *LinuxNotifier) Notify(title, message string, urgency Urgency) error {
    args := []string{"-a", "ccbell", "-t", "3000"}
    switch urgency {
    case UrgencyLow:
        args = append(args, "-u", "low")
    case UrgencyCritical:
        args = append(args, "-u", "critical")
    }
    args = append(args, title, message)
    cmd := exec.Command("notify-send", args...)
    return cmd.Run()
}
```

### Commands

```bash
/ccbell:configure visual              # Configure visual notifications
/ccbell:test --visual stop            # Test visual notification
/ccbell:status visual                 # Show visual notification status
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `visual` section with mode (audio-only/visual-only/both) |
| **Core Logic** | Add | Add `VisualNotifier` with Send() method |
| **New File** | Add | `internal/visual/visual.go` for platform-specific notifications |
| **Main Flow** | Modify | Call visual notifier alongside audio player |
| **Commands** | Add | New `visual` command (configure, test) |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/visual.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference visual options |
| **commands/test.md** | Update | Add --visual flag |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [AppleScript Notification](https://apple.stackexchange.com/questions/57412/how-can-i-trigger-a-notification-from-the-apple-command-line)
- [notify-send man page](https://man7.org/linux/man-pages/man1/notify-send.1.html)
- [Current ccbell audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)

---

[Back to Feature Index](index.md)
