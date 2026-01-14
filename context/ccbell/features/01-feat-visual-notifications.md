# Feature: Visual Notifications

Display visual alerts alongside or instead of audio notifications.

## Summary

Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger. Users who are deaf or hard of hearing, or work in noisy environments, benefit from visual alerts.

## Motivation

- Accessibility for deaf/hard-of-hearing users
- Works in noise-restricted environments (libraries, meetings)
- Silent mode alternative
- Dual-channel confirmation (audio + visual)

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Current Audio Player Analysis

The current ccbell audio player (`internal/audio/player.go`) uses:
- **macOS**: `afplay` (built-in)
- **Linux**: `mpv`, `paplay`, `aplay`, `ffplay`

**Key Finding**: The audio player is command-line based and doesn't natively support visual notifications. Visual notifications require separate platform-specific tools.

### Platform Options

| Platform | Tool | Native Support | Feasibility |
|----------|------|----------------|-------------|
| macOS | AppleScript (`osascript`) | Yes - Built-in | ✅ Easy |
| macOS | Terminal Notifier (gem) | No - Requires install | ⚠️ Optional |
| Linux | `notify-send` (libnotify) | Yes - Most distros | ✅ Easy |
| Linux | `dunst` | No - Requires install | ⚠️ Optional |

### macOS Implementation (AppleScript)

```bash
# Simple notification
osascript -e 'display notification "Claude finished" with title "ccbell"'

# With sound (uses system notification sound)
osascript -e 'display notification "Permission needed" with title "ccbell" sound name "Ping"'
```

**Pros:** No dependencies, works on all macOS versions
**Cons:** Limited customization

### Linux Implementation (notify-send)

```bash
# Basic
notify-send "ccbell" "Claude finished"

# With icon
notify-send -i audio-volume-high "ccbell" "Permission needed"

# With urgency
notify-send -u critical "ccbell" "Error occurred"
```

**Pros:** Works on most distros, no install needed
**Cons:** Requires notify-osd/libnotify

### Recommended Approach

**Phase 1:** Use existing CLI tools (notify-send, osascript)
**Phase 2:** Native implementations if needed

### macOS Options

#### Option A: AppleScript via osascript

```bash
# Simple notification
osascript -e 'display notification "Claude finished" with title "ccbell"'

# With sound (uses system notification sound)
osascript -e 'display notification "Permission needed" with title "ccbell" sound name "Ping"'
```

**Pros:** No dependencies, works on all macOS versions
**Cons:** Limited customization

#### Option B: Terminal Notifier

```bash
# Install: gem install terminal-notifier
terminal-notifier -message "Claude finished" -title "ccbell" -sound default
```

**Pros:** Better customization, grouped notifications
**Cons:** Requires Ruby/Gem installation

### Linux Options

#### Option A: notify-send (libnotify)

```bash
# Basic
notify-send "ccbell" "Claude finished"

# With icon
notify-send -i audio-volume-high "ccbell" "Permission needed"

# With urgency
notify-send -u critical "ccbell" "Error occurred"
```

**Pros:** Works on most distros, no install needed
**Cons:** Requires notify-osd/libnotify

#### Option B: dunst

```bash
# dunst is a notification daemon
notify-send "ccbell" "message" -h string:x-dunst-stack-tag:ccbell
```

**Pros:** Highly configurable
**Cons:** Requires dunst installation

## Implementation

### Visual Notification Interface

```go
type VisualNotifier interface {
    Notify(title, message string, urgency Urgency) error
    Supported() bool
}

type Urgency string

const (
    UrgencyLow    Urgency = "low"
    UrgencyNormal Urgency = "normal"
    UrgencyCritical Urgency = "critical"
)
```

### macOS Implementation (AppleScript)

```go
type MacOSNotifier struct{}

func (n *MacOSNotifier) Notify(title, message string, urgency Urgency) error {
    script := fmt.Sprintf(`osascript -e 'display notification "%s" with title "%s"'`,
        escapeAppleScript(message),
        escapeAppleScript(title),
    )

    // Add sound if critical
    if urgency == UrgencyCritical {
        script += fmt.Sprintf(` sound name "%s"`, n.criticalSound())
    }

    cmd := exec.Command("sh", "-c", script)
    return cmd.Run()
}

func (n *MacOSNotifier) Supported() bool {
    _, err := exec.LookPath("osascript")
    return err == nil
}
```

### Linux Implementation (notify-send)

```go
type LinuxNotifier struct{}

func (n *LinuxNotifier) Notify(title, message string, urgency Urgency) error {
    args := []string{
        "-a", "ccbell",
        "-t", "3000", // 3 seconds
    }

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

func (n *LinuxNotifier) Supported() bool {
    _, err := exec.LookPath("notify-send")
    return err == nil
}
```

### Unified Manager

```go
type VisualManager struct {
    notifiers []VisualNotifier
    config    VisualConfig
}

func NewVisualManager() *VisualManager {
    m := &VisualManager{
        notifiers: []VisualNotifier{
            &MacOSNotifier{},
            &LinuxNotifier{},
        },
    }

    // Auto-detect best notifier
    for _, n := range m.notifiers {
        if n.Supported() {
            m.notifier = n
            break
        }
    }

    return m
}

func (m *VisualManager) NotifyEvent(event string) error {
    if !m.config.Enabled {
        return nil
    }

    title := "ccbell"
    message := m.eventMessage(event)
    urgency := m.eventUrgency(event)

    return m.notifier.Notify(title, message, urgency)
}
```

## Configuration

### Config Schema

```json
{
  "type": "object",
  "properties": {
    "visual": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "mode": {
          "type": "string",
          "enum": ["audio-only", "visual-only", "both"]
        },
        "notifications": {
          "type": "object",
          "properties": {
            "stop": {
              "type": "object",
              "properties": {
                "enabled": { "type": "boolean" },
                "message": { "type": "string" },
                "urgency": { "type": "string", "enum": ["low", "normal", "critical"] }
              }
            },
            "permission_prompt": { "$ref": "#/properties/visual/properties/notifications/properties/stop" },
            "idle_prompt": { "$ref": "#/properties/visual/properties/notifications/properties/stop" },
            "subagent": { "$ref": "#/properties/visual/properties/notifications/properties/stop" }
          }
        },
        "icon": { "type": "string" },
        "timeout": { "type": "integer" }
      }
    }
  }
}
```

### Example Config

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
    },
    "icon": "bundled:ccbell.png",
    "timeout": 3000
  }
}
```

## Commands

### Configure Visual

```bash
/ccbell:configure visual
```

**Interactive:**
```
Enable visual notifications? [y/n]: y
Notification mode:
  [1] Audio only (current)
  [2] Visual only
  [3] Both audio and visual
Select [1-3]: 3

Configure per-event:
stop: [y] message: "Claude finished" urgency: low [change]
permission: [y] message: "Permission needed" urgency: critical [change]
idle: [y] message: "Claude is waiting" urgency: low [change]
subagent: [y] message: "Subagent done" urgency: normal [change]

Test visual notification? [y/n]: y
[Shows notification]
Save? [y/n]: y
```

### Test Visual

```bash
/ccbell:test --visual stop
/ccbell:test --visual all
```

### Status

```bash
/ccbell:status visual
Visual Notifications: Enabled
Mode: Both (audio + visual)
Platform: macOS (Notification Center)
Events: 4/4 enabled
```

## Platform-Specific Icons

| Platform | Icon Type | Fallback |
|----------|-----------|----------|
| macOS | SF Symbols or app icon | System info icon |
| Linux | Desktop icon | Notification icon |

```bash
# macOS: Use system icons via AppleScript
osascript -e 'display notification "msg" with title "ccbell" subtitle "subtitle"'
```

## Future Enhancements

- **Custom icons:** User-provided icon per event
- **Notification history:** Show past notifications
- **Notification groups:** Stack same-type notifications
- **Do Not Disturb integration:** Respect system DND
- **Brightness/flash:** Screen flash for critical alerts

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Notifications don't show | Fallback to audio-only, log error |
| Platform not supported | Detect and disable gracefully |
| Too many notifications | Respect cooldown settings |
| Privacy concerns | Don't include sensitive content |

## Dependencies

| Dependency | Purpose | Link |
|------------|---------|------|
| AppleScript | macOS notifications | Built-in |
| notify-send | Linux notifications | Built-in on most distros |
| go-exec | Command execution | `github.com/google/go-exec` |

## Feasibility Research

### Audio Player Compatibility

The current audio player uses non-blocking playback (`cmd.Start()`). Visual notifications are independent of audio playback and can be triggered alongside or separately.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `osascript` | Native (macOS) | Free | Built-in, no install needed |
| `notify-send` | Native (Linux) | Free | Pre-installed on most distros |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via AppleScript |
| Linux | ✅ Supported | Via notify-send |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Integration with Current Architecture

Visual notifications can be added as a separate `VisualNotifier` interface that follows the same pattern as `Player`:

```go
type VisualNotifier interface {
    Notify(title, message string, urgency Urgency) error
    Supported() bool
}
```

### Configuration Changes

Add to `internal/config/config.go`:
```go
type VisualConfig struct {
    Enabled *bool              `json:"enabled,omitempty"`
    Mode    string             `json:"mode,omitempty"` // "audio-only", "visual-only", "both"
    Events  map[string]*Event  `json:"events,omitempty"`
}
```

---

## References

### Research Sources

- [AppleScript Notification](https://apple.stackexchange.com/questions/57412/how-can-i-trigger-a-notification-from-the-apple-command-line)
- [notify-send man page](https://man7.org/linux/man-pages/man1/notify-send.1.html)

### ccbell Implementation Research

- [Current ccbell audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Used for audio playback via `afplay` (macOS) and `mpv/paplay/aplay/ffplay` (Linux)
- [Platform detection code](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L34-L91) - Shows supported platforms (macOS, Linux only)
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Reference for adding new config sections
