# Feature: Sound Event Notification Center Monitor

Play sounds for macOS Notification Center events.

## Summary

Monitor macOS Notification Center and notification delivery, playing sounds for notification events.

## Motivation

- Notification delivery feedback
- Widget update alerts
- Notification center access
- Do Not Disturb state changes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Notification Center Events

| Event | Description | Example |
|-------|-------------|---------|
| Notification | New notification delivered | Email received |
| Notification Center | NC opened/closed | Cmd+Space opened |
| Do Not Disturb | DND state changed | DND enabled |
| Widget Updated | Widget content changed | Weather updated |
| Notification Banner | Banner appeared | Transient alert |

### Configuration

```go
type NotificationCenterMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    SoundOnNotification bool             `json:"sound_on_notification"`
    SoundOnDND         bool              `json:"sound_on_dnd"`
    WatchApps          []string          `json:"watch_apps"` // Specific apps
    ExcludeApps        []string          `json:"exclude_apps"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 1 default
}

type NotificationCenterEvent struct {
    AppName    string
    EventType  string // "notification", "dnd_on", "dnd_off", "widget_updated"
    Title      string
    Message    string
}
```

### Commands

```bash
/ccbell:notification-center status  # Show NC status
/ccbell:notification-center on      # Enable monitoring
/ccbell:notification-center dnd on  # Enable DND sounds
/ccbell:add Mail                    # Add app to watch
/ccbell:sound notification <sound>
/ccbell:test                        # Test NC sounds
```

### Output

```
$ ccbell:notification-center status

=== Sound Event Notification Center Monitor ===

Status: Enabled
Notification Sounds: Yes
DND Sounds: Yes

Do Not Disturb: OFF
  Last Changed: 2 hours ago

Recent Notifications: 12

[1] Mail
    Subject: "New Message"
    Time: 5 min ago
    Sound: bundled:stop

[2] Slack
    @username mentioned you
    Time: 15 min ago
    Sound: bundled:stop

[3] Calendar
    Meeting in 30 minutes
    Time: 30 min ago
    Sound: bundled:stop

Watched Apps: 5
  Mail, Slack, Calendar, Messages, Telegram

Excluded Apps: 2
  Spotify, Finder

Sound Settings:
  Notification: bundled:stop
  DND On: bundled:stop
  DND Off: bundled:stop

[Configure] [Add App] [Test All]
```

---

## Audio Player Compatibility

Notification Center monitoring doesn't play sounds directly:
- Monitoring feature using macOS APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Notification Center Monitor

```go
type NotificationCenterMonitor struct {
    config         *NotificationCenterMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    lastDND        bool
    notificationCount int
}

func (m *NotificationCenterMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastDND = m.isDoNotDisturbOn()
    go m.monitor()
}

func (m *NotificationCenterMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkNotificationCenter()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NotificationCenterMonitor) checkNotificationCenter() {
    // Check Do Not Disturb state
    dndOn := m.isDoNotDisturbOn()
    if dndOn != m.lastDND {
        if dndOn {
            m.onDNDOn()
        } else {
            m.onDNDOff()
        }
        m.lastDND = dndOn
    }

    // Check for new notifications
    count := m.getNotificationCount()
    if count > m.notificationCount {
        m.onNewNotification()
    }
    m.notificationCount = count
}

func (m *NotificationCenterMonitor) isDoNotDisturbOn() bool {
    // macOS: Use defaults to check DND state
    cmd := exec.Command("defaults", "read", "com.apple.notificationcenterui",
        "doNotDisturbEnabled")
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.TrimSpace(string(output)) == "1"
}

func (m *NotificationCenterMonitor) getNotificationCount() int {
    // Use osascript or AppKit to get notification count
    cmd := exec.Command("osascript", "-e",
        `tell application "System Events" to count of notification`)
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    count, _ := strconv.Atoi(strings.TrimSpace(string(output)))
    return count
}

func (m *NotificationCenterMonitor) getRecentNotifications() []NotificationCenterEvent {
    var events []NotificationCenterEvent

    // Use log to get notification history
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'NOTIFICATION'",
        "--last", "5m")
    output, err := cmd.Output()
    if err != nil {
        return events
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        event := m.parseNotificationLine(line)
        if event != nil {
            events = append(events, *event)
        }
    }

    return events
}

func (m *NotificationCenterMonitor) parseNotificationLine(line string) *NotificationCenterEvent {
    if !strings.Contains(line, "NOTIFICATION") {
        return nil
    }

    event := &NotificationCenterEvent{
        EventType: "notification",
    }

    // Extract app name
    appMatch := regexp.MustCompile(`app = (\w+)`).FindStringSubmatch(line)
    if appMatch != nil {
        event.AppName = appMatch[1]
    }

    // Check if app should be watched
    if !m.shouldProcessApp(event.AppName) {
        return nil
    }

    return event
}

func (m *NotificationCenterMonitor) shouldProcessApp(appName string) bool {
    // Check exclusion list
    for _, app := range m.config.ExcludeApps {
        if strings.EqualFold(appName, app) {
            return false
        }
    }

    // If watch list is empty, process all
    if len(m.config.WatchApps) == 0 {
        return true
    }

    // Check watch list
    for _, app := range m.config.WatchApps {
        if strings.EqualFold(appName, app) {
            return true
        }
    }

    return false
}

func (m *NotificationCenterMonitor) onNewNotification() {
    if !m.config.SoundOnNotification {
        return
    }

    sound := m.config.Sounds["notification"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *NotificationCenterMonitor) onDNDOn() {
    if !m.config.SoundOnDND {
        return
    }

    sound := m.config.Sounds["dnd_on"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *NotificationCenterMonitor) onDNDOff() {
    if !m.config.SoundOnDND {
        return
    }

    sound := m.config.Sounds["dnd_off"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| defaults | System Tool | Free | macOS preferences |
| log | System Tool | Free | macOS system log |
| osascript | System Tool | Free | macOS automation |

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
| macOS | Supported | Uses defaults/log |
| Linux | Not Supported | No native Notification Center |
| Windows | Not Supported | ccbell only supports macOS/Linux |
