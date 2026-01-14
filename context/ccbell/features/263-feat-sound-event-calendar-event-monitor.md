# Feature: Sound Event Calendar Event Monitor

Play sounds for upcoming calendar events and meeting reminders.

## Summary

Monitor calendar events, meeting reminders, and schedule notifications, playing sounds for upcoming events.

## Motivation

- Meeting reminders
- Event awareness
- Schedule feedback
- Reminder alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Calendar Events

| Event | Description | Example |
|-------|-------------|---------|
| Event Starting | Event begins soon | Meeting in 5 min |
| Event Started | Event started now | Meeting now |
| Event Ended | Event finished | Meeting done |
| Reminder | Custom reminder | Call at 3pm |
| All Day Event | Day-long event | Birthday |

### Configuration

```go
type CalendarMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    Calendars          []string          `json:"calendars"` // "work", "personal"
    ReminderMinutes    int               `json:"reminder_minutes"` // 5 default
    SoundOnReminder    bool              `json:"sound_on_reminder"`
    SoundOnStart       bool              `json:"sound_on_start"`
    SoundOnEnd         bool              `json:"sound_on_end"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 60 default
}

type CalendarEvent struct {
    Title       string
    Calendar    string
    StartTime   time.Time
    EndTime     time.Time
    EventType   string // "reminder", "start", "end", "all_day"
    Location    string
    Attendees   []string
}
```

### Commands

```bash
/ccbell:calendar status                # Show calendar status
/ccbell:calendar add "work"            # Add calendar to watch
/ccbell:calendar remove "work"
/ccbell:calendar sound reminder <sound>
/ccbell:calendar sound start <sound>
/ccbell:calendar test                  # Test calendar sounds
```

### Output

```
$ ccbell:calendar status

=== Sound Event Calendar Monitor ===

Status: Enabled
Reminder: 5 minutes before
Start Sounds: Yes

Today's Events: 5

[1] Team Standup
    Calendar: Work
    Time: 9:00 AM - 9:30 AM
    Location: Conference Room A
    Starts in: - (Started 30 min ago)
    Sound: bundled:stop

[2] 1:1 with Manager
    Calendar: Work
    Time: 2:00 PM - 2:30 PM
    Location: Zoom
    Starts in: 1 hour 30 min
    Sound: bundled:stop

[3] Project Review
    Calendar: Work
    Time: 4:00 PM - 5:00 PM
    Location: Room B
    Starts in: 3 hours 30 min
    Sound: bundled:stop

Upcoming (Next 24h):
  - 1:1 with Manager in 1h 30m
  - Project Review in 3h 30m

Sound Settings:
  Reminder: bundled:stop
  Start: bundled:stop
  End: bundled:stop

[Configure] [Add Calendar] [Test All]
```

---

## Audio Player Compatibility

Calendar monitoring doesn't play sounds directly:
- Monitoring feature using calendar APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Calendar Monitor

```go
type CalendarMonitor struct {
    config         *CalendarMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    notifiedEvents map[string]time.Time // event ID -> notification time
}

func (m *CalendarMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.notifiedEvents = make(map[string]time.Time)
    go m.monitor()
}

func (m *CalendarMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CalendarMonitor) checkEvents() {
    events := m.getUpcomingEvents()

    now := time.Now()
    reminderThreshold := now.Add(time.Duration(m.config.ReminderMinutes) * time.Minute)

    for _, event := range events {
        eventID := m.getEventID(event)

        // Check for reminder
        if m.config.SoundOnReminder {
            if event.StartTime.After(now) && event.StartTime.Before(reminderThreshold) {
                if _, notified := m.notifiedEvents[eventID+"_reminder"]; !notified {
                    m.onEventReminder(event)
                    m.notifiedEvents[eventID+"_reminder"] = now
                }
            }
        }

        // Check for event start
        if m.config.SoundOnStart {
            if event.StartTime.After(now.Add(-time.Minute)) &&
               event.StartTime.Before(now.Add(time.Minute)) {
                if _, notified := m.notifiedEvents[eventID+"_start"]; !notified {
                    m.onEventStart(event)
                    m.notifiedEvents[eventID+"_start"] = now
                }
            }
        }

        // Check for event end
        if m.config.SoundOnEnd {
            if event.EndTime.After(now.Add(-time.Minute)) &&
               event.EndTime.Before(now.Add(time.Minute)) {
                if _, notified := m.notifiedEvents[eventID+"_end"]; !notified {
                    m.onEventEnd(event)
                    m.notifiedEvents[eventID+"_end"] = now
                }
            }
        }
    }

    // Clean old notifications (older than 24 hours)
    m.cleanOldNotifications()
}

func (m *CalendarMonitor) getUpcomingEvents() []*CalendarEvent {
    var events []*CalendarEvent

    if runtime.GOOS == "darwin" {
        events = m.getDarwinCalendarEvents()
    } else {
        events = m.getLinuxCalendarEvents()
    }

    return events
}

func (m *CalendarMonitor) getDarwinCalendarEvents() []*CalendarEvent {
    var events []*CalendarEvent

    // Use osascript to get calendar events
    now := time.Now()
    endOfDay := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, now.Location())

    script := fmt.Sprintf(`
        tell application "Calendar"
            tell calendar "Home"
                set theEvents to every event where start date >= (current date) and start date <= (date "%s")
            end tell
        end tell
    `, endOfDay.Format("2006-01-02 15:04:05"))

    cmd := exec.Command("osascript", "-e", script)
    output, err := cmd.Output()
    if err != nil {
        return events
    }

    // Parse output (simplified)
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "event id ") {
            // Extract event info
            parts := strings.Split(line, " | ")
            if len(parts) >= 2 {
                event := &CalendarEvent{
                    Title:    parts[0],
                    Calendar: "Calendar",
                }
                events = append(events, event)
            }
        }
    }

    return events
}

func (m *CalendarMonitor) getLinuxCalendarEvents() []*CalendarEvent {
    var events []*CalendarEvent

    // Try various calendar sources
    calendarSources := []string{
        filepath.Join(os.Getenv("HOME"), ".config/evolution/calendar"),
        filepath.Join(os.Getenv("HOME"), ".local/share/orage"),
    }

    for _, source := range calendarSources {
        if _, err := os.Stat(source); err == nil {
            events = append(events, m.parseCalendarSource(source)...)
        }
    }

    // Also try .ics files
    icsFiles, _ := filepath.Glob(filepath.Join(os.Getenv("HOME"), "**/*.ics"))
    for _, icsFile := range icsFiles {
        events = append(events, m.parseICSFile(icsFile)...)
    }

    return events
}

func (m *CalendarMonitor) parseCalendarSource(path string) []*CalendarEvent {
    var events []*CalendarEvent

    // This is a placeholder - real implementation would parse
    // the specific calendar format (evolution, orage, etc.)

    return events
}

func (m *CalendarMonitor) parseICSFile(filePath string) []*CalendarEvent {
    var events []*CalendarEvent

    data, err := os.ReadFile(filePath)
    if err != nil {
        return events
    }

    // Parse iCalendar format
    content := string(data)

    // Find VEVENT blocks
    re := regexp.MustCompile(`BEGIN:VEVENT[\s\S]*?END:VEVENT`)
    matches := re.FindAllString(content, -1)

    for _, match := range matches {
        event := &CalendarEvent{}

        // Extract summary
        summaryRe := regexp.MustCompile(`SUMMARY:([^\r\n]+)`)
        if match := summaryRe.FindStringSubmatch(match); len(match) >= 2 {
            event.Title = match[1]
        }

        // Extract start time
        startRe := regexp.MustCompile(`DTSTART(?:;[^:]*)?:(\d{8}T\d{6}Z?)`)
        if match := startRe.FindStringSubmatch(match); len(match) >= 2 {
            if t, err := parseICSDate(match[1]); err == nil {
                event.StartTime = t
            }
        }

        // Extract end time
        endRe := regexp.MustCompile(`DTEND(?:;[^:]*)?:(\d{8}T\d{6}Z?)`)
        if match := endRe.FindStringSubmatch(match); len(match) >= 2 {
            if t, err := parseICSDate(match[1]); err == nil {
                event.EndTime = t
            }
        }

        events = append(events, event)
    }

    return events
}

func parseICSDate(dateStr string) (time.Time, error) {
    // Parse ICS date format: 20240115T090000
    layout := "20060102T150405"
    return time.Parse(layout, dateStr)
}

func (m *CalendarMonitor) getEventID(event *CalendarEvent) string {
    return fmt.Sprintf("%s-%s", event.Title, event.StartTime.Format("20060102"))
}

func (m *CalendarMonitor) onEventReminder(event *CalendarEvent) {
    if !m.config.SoundOnReminder {
        return
    }

    sound := m.config.Sounds["reminder"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CalendarMonitor) onEventStart(event *CalendarEvent) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["start"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CalendarMonitor) onEventEnd(event *CalendarEvent) {
    if !m.config.SoundOnEnd {
        return
    }

    sound := m.config.Sounds["end"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *CalendarMonitor) cleanOldNotifications() {
    cutoff := time.Now().Add(-24 * time.Hour)
    for id, t := range m.notifiedEvents {
        if t.Before(cutoff) {
            delete(m.notifiedEvents, id)
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| osascript | System Tool | Free | macOS AppleScript |
| Calendar | App | Free | macOS Calendar app |
| evolution | App | Free | Linux calendar |
| orage | App | Free | Linux calendar |

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
| macOS | Supported | Uses Calendar app via osascript |
| Linux | Supported | Uses .ics files, evolution |
| Windows | Not Supported | ccbell only supports macOS/Linux |
