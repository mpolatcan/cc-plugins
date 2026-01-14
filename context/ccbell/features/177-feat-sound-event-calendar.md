# Feature: Sound Event Calendar

Play sounds based on calendar events.

## Summary

Play different sounds based on calendar event types and status.

## Motivation

- Meeting awareness
- Schedule notifications
- Calendar integration

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Calendar Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Meeting Start | Calendar event begins | Meeting in 5 min |
| Meeting End | Calendar event ends | Meeting ended |
| Free/Busy | Status change | Became busy |
| All Day | All-day event | Birthday |
| Reminder | Calendar reminder | 15 min before |

### Configuration

```go
type CalendarConfig struct {
    Enabled     bool              `json:"enabled"`
    Source      string            `json:"source"` // "calendars", "ics"
    CalendarIDs []string          `json:"calendar_ids,omitempty"` // macOS calendar names
    ICSPath     string            `json:"ics_path,omitempty"`
    Lookahead   int               `json:"lookahead_minutes"` // 15 default
    LeadTime    int               `json:"lead_time_minutes"` // 5 default
    Sounds      map[string]string `json:"sounds"` // trigger -> sound
}
```

### Commands

```bash
/ccbell:calendar status              # Show current calendar status
/ccbell:calendar list                # List calendars
/ccbell:calendar source "Work"       # Set calendar source
/ccbell:calendar sound meeting_start <sound>
/ccbell:calendar sound meeting_end <sound>
/ccbell:calendar sound reminder <sound>
/ccbell:calendar lead 10             # Set lead time (minutes)
/ccbell:calendar enable              # Enable calendar monitoring
/ccbell:calendar disable             # Disable calendar monitoring
/ccbell:calendar test                # Test calendar sounds
```

### Output

```
$ ccbell:calendar status

=== Sound Event Calendar ===

Status: Enabled
Source: Work Calendar
Lookahead: 15 min
Lead Time: 5 min

Upcoming Events:
  [1] Team Standup (in 5 min)
      Sound: bundled:stop
      Status: Pending

  [2] Code Review (in 1 hour)
      Sound: bundled:stop
      Status: Pending

Current Status: Free

Sounds:
  Meeting Start: bundled:stop
  Meeting End: bundled:stop
  Reminder: bundled:stop
  Status Change: bundled:stop

[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Calendar monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Calendar Monitoring

```go
type CalendarManager struct {
    config   *CalendarConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastEvents map[string]time.Time
}

func (m *CalendarManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *CalendarManager) monitor() {
    ticker := time.NewTicker(1 * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkCalendar()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CalendarManager) checkCalendar() {
    events, err := m.getUpcomingEvents()
    if err != nil {
        log.Debug("Failed to get calendar: %v", err)
        return
    }

    now := time.Now()
    lookaheadEnd := now.Add(time.Duration(m.config.Lookahead) * time.Minute)

    for _, event := range events {
        eventStart := event.StartTime
        eventEnd := event.EndTime

        // Check for meeting start
        if eventStart.After(now) && eventStart.Before(lookaheadEnd) {
            leadTimeEnd := now.Add(time.Duration(m.config.LeadTime) * time.Minute)
            if eventStart.Before(leadTimeEnd) {
                if !m.wasNotified(event.ID) {
                    m.playCalendarEvent("meeting_start", event)
                    m.markNotified(event.ID)
                }
            }
        }

        // Check for meeting end
        if eventEnd.After(now) && eventEnd.Before(lookaheadEnd) {
            if !m.wasNotified(event.ID + "_end") {
                m.playCalendarEvent("meeting_end", event)
                m.markNotified(event.ID + "_end")
            }
        }
    }

    m.cleanupOldNotifications(events)
}

// getUpcomingEvents reads calendar (macOS: calcommand)
func (m *CalendarManager) getUpcomingEvents() ([]*CalendarEvent, error) {
    // macOS: Use calcommand or osascript
    cmd := exec.Command("osascript", "-e",
        `tell application "Calendar"
            get events of calendar "Work" where start date > (current date)
        end tell`)
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    // Parse output
    return m.parseCalendarOutput(output)
}

type CalendarEvent struct {
    ID        string
    Title     string
    StartTime time.Time
    EndTime   time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| osascript | System Tool | Free | macOS automation |
| cal | System Tool | Free | Command-line calendar |
| icalBuddy | Homebrew | Free | Enhanced calendar access |

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
| macOS | ✅ Supported | Uses osascript/Calendar app |
| Linux | ✅ Supported | Uses icalBuddy or khal |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
