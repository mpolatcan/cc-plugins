# Feature: Sound Event Calendar Monitor

Play sounds for calendar event reminders.

## Summary

Monitor calendar events and play sounds for upcoming meetings, reminders, and events.

## Motivation

- Meeting start reminders
- Focus time alerts
- Break reminders
- Schedule awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Calendar Events

| Event | Description | Example |
|-------|-------------|---------|
| Meeting Start | Event beginning now | Meeting in 0 min |
| Meeting Soon | Event in 5 minutes | 5 min warning |
| Reminder | Calendar reminder | Task reminder |
| All Day Event | All day event | Birthday |
| Free Time | No events scheduled | Free until 3pm |

### Configuration

```go
type CalendarMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    CalendarType  string            `json:"calendar_type"` // "caldav", "google", "apple"
    Config        map[string]string `json:"config"`
    ReminderTimes []int             `json:"reminder_times"` // minutes before event
    Sounds        map[string]string `json:"sounds"`
    WorkHoursOnly bool              `json:"work_hours_only"`
    WorkStart     string            `json:"work_start"` // "09:00"
    WorkEnd       string            `json:"work_end"` // "18:00"
}

type CalendarEvent struct {
    ID          string
    Title       string
    Start       time.Time
    End         time.Time
    Location    string
    AllDay      bool
    Reminders   []time.Time
}
```

### Commands

```bash
/ccbell:calendar status            # Show calendar status
/ccbell:calendar add google        # Add Google Calendar
/ccbell:calendar remove google     # Remove calendar
/ccbell:calendar reminder 5        # Set 5 min reminder
/ccbell:calendar sound meeting <sound>
/ccbell:calendar sound reminder <sound>
/ccbell:calendar test              # Test calendar sounds
```

### Output

```
$ ccbell:calendar status

=== Sound Event Calendar Monitor ===

Status: Enabled
Calendar: Google Calendar
Reminders: 5 min, 15 min
Work Hours Only: Yes (9:00 - 18:00)

Upcoming Events (Today):

[1] Team Standup
    Time: 10:00 AM (in 5 min)
    Duration: 30 min
    Location: Conference Room A
    Sound: bundled:stop

[2] Code Review
    Time: 2:00 PM (in 4 hours)
    Duration: 60 min
    Location: Remote
    Sound: bundled:stop

[3] Sprint Planning
    Time: 4:00 PM (in 6 hours)
    Duration: 90 min
    Location: Main Room
    Sound: bundled:stop

Status: Working Hours
  Next event: 5 min

[Configure] [Add Calendar] [Test]
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
    config     *CalendarMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastEvents map[string]bool
}

func (m *CalendarMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEvents = make(map[string]bool)
    go m.monitor()
}

func (m *CalendarMonitor) monitor() {
    ticker := time.NewTicker(time.Minute)
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

func (m *CalendarMonitor) checkCalendar() {
    now := time.Now()

    // Check work hours
    if m.config.WorkHoursOnly {
        if !m.isWithinWorkHours(now) {
            return
        }
    }

    events := m.getUpcomingEvents()
    m.evaluateEvents(events, now)
}

func (m *CalendarMonitor) isWithinWorkHours(t time.Time) bool {
    start, _ := time.Parse("15:04", m.config.WorkStart)
    end, _ := time.Parse("15:04", m.config.WorkEnd)

    current := t.Format("15:04")
    nowTime, _ := time.Parse("15:04", current)

    return nowTime.After(start) && nowTime.Before(end)
}

func (m *CalendarMonitor) getUpcomingEvents() []*CalendarEvent {
    var events []*CalendarEvent

    switch m.config.CalendarType {
    case "apple":
        events = m.getAppleCalendarEvents()
    case "caldav":
        events = m.getCalDAVEvents()
    case "google":
        events = m.getGoogleCalendarEvents()
    }

    return events
}

func (m *CalendarMonitor) getAppleCalendarEvents() []*CalendarEvent {
    var events []*CalendarEvent

    // macOS: Use calendar command or sqlite
    cmd := exec.Command("cal", "-n", "3")
    output, err := cmd.Output()
    if err != nil {
        return events
    }

    // Parse calendar output for events
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        event := m.parseCalendarLine(line)
        if event != nil {
            events = append(events, event)
        }
    }

    return events
}

func (m *CalendarMonitor) parseCalendarLine(line string) *CalendarEvent {
    // Simple parsing - looks for time slots
    // This is a simplified version
    if strings.Contains(line, "Today") {
        return nil // Skip header
    }

    // Look for time patterns like "10:00"
    timeMatch := regexp.MustCompile(`(\d{1,2}:\d{2})`).FindStringSubmatch(line)
    if timeMatch == nil {
        return nil
    }

    startStr := timeMatch[1]
    today := time.Now()

    start, err := time.Parse("15:04", startStr)
    if err != nil {
        return nil
    }

    event := &CalendarEvent{
        Title: strings.TrimSpace(line),
        Start: today.Add(time.Duration(start.Hour()-today.Hour()) * time.Hour),
        End:   today.Add(time.Duration(start.Hour()-today.Hour()+1) * time.Hour),
    }

    return event
}

func (m *CalendarMonitor) getCalDAVEvents() []*CalendarEvent {
    var events []*CalendarEvent

    server := m.config.Config["server"]
    username := m.config.Config["username"]
    password := m.config.Config["password"]
    calendar := m.config.Config["calendar"]

    // Build calendar URL
    calURL := fmt.Sprintf("%s/%s.ics", server, calendar)

    // Create HTTP client with auth
    client := &http.Client{}
    req, _ := http.NewRequest("GET", calURL, nil)
    req.SetBasicAuth(username, password)

    resp, err := client.Do(req)
    if err != nil {
        return events
    }
    defer resp.Body.Close()

    // Parse ICS format
    body, _ := io.ReadAll(resp.Body)
    events = m.parseICS(string(body))

    return events
}

func (m *CalendarMonitor) getGoogleCalendarEvents() []*CalendarEvent {
    var events []*CalendarEvent

    apiKey := m.config.Config["api_key"]
    calendarID := m.config.Config["calendar_id"]
    if calendarID == "" {
        calendarID = "primary"
    }

    // Google Calendar API
    url := fmt.Sprintf(
        "https://www.googleapis.com/calendar/v3/calendars/%s/events?key=%s&timeMin=%s&maxResults=10",
        url.QueryEscape(calendarID),
        apiKey,
        time.Now().Format(time.RFC3339),
    )

    resp, err := http.Get(url)
    if err != nil {
        return events
    }
    defer resp.Body.Close()

    var result struct {
        Items []struct {
            Summary     string `json:"summary"`
            Start       struct {
                DateTime string `json:"dateTime"`
                Date     string `json:"date"`
            } `json:"start"`
            End struct {
                DateTime string `json:"dateTime"`
                Date     string `json:"date"`
            } `json:"end"`
        } `json:"items"`
    }

    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return events
    }

    for _, item := range result.Items {
        event := &CalendarEvent{
            Title: item.Summary,
        }

        if item.Start.DateTime != "" {
            event.Start, _ = time.Parse(time.RFC3339, item.Start.DateTime)
        } else if item.Start.Date != "" {
            event.Start, _ = time.Parse("2006-01-02", item.Start.Date)
            event.AllDay = true
        }

        if item.End.DateTime != "" {
            event.End, _ = time.Parse(time.RFC3339, item.End.DateTime)
        }

        events = append(events, &event)
    }

    return events
}

func (m *CalendarMonitor) parseICS(data string) []*CalendarEvent {
    var events []*CalendarEvent
    lines := strings.Split(data, "\n")

    var currentEvent *CalendarEvent

    for _, line := range lines {
        if strings.HasPrefix(line, "BEGIN:VEVENT") {
            currentEvent = &CalendarEvent{}
        } else if strings.HasPrefix(line, "END:VEVENT") {
            if currentEvent != nil {
                events = append(events, currentEvent)
                currentEvent = nil
            }
        } else if currentEvent != nil {
            if strings.HasPrefix(line, "SUMMARY:") {
                currentEvent.Title = strings.TrimPrefix(line, "SUMMARY:")
            } else if strings.HasPrefix(line, "DTSTART:") {
                currentEvent.Start = m.parseICSDate(strings.TrimPrefix(line, "DTSTART:"))
            } else if strings.HasPrefix(line, "DTEND:") {
                currentEvent.End = m.parseICSDate(strings.TrimPrefix(line, "DTEND:"))
            }
        }
    }

    return events
}

func (m *CalendarMonitor) parseICSDate(dateStr string) time.Time {
    // Parse ICS date format: 20240115T100000Z
    formats := []string{
        "20060115T150405Z",
        "20060115T150405",
        "2006-01-02T15:04:05Z",
    }

    for _, format := range formats {
        if t, err := time.Parse(format, dateStr); err == nil {
            return t
        }
    }

    return time.Time{}
}

func (m *CalendarMonitor) evaluateEvents(events []*CalendarEvent, now time.Time) {
    for _, event := range events {
        // Check for upcoming events based on reminder times
        for _, reminderMinutes := range m.config.ReminderTimes {
            reminderTime := event.Start.Add(-time.Duration(reminderMinutes) * time.Minute)

            if now.After(reminderTime) && now.Before(event.Start) {
                eventID := fmt.Sprintf("%s-%d", event.ID, reminderMinutes)
                if !m.lastEvents[eventID] {
                    if event.AllDay {
                        m.playSound("all_day")
                    } else if reminderMinutes == 0 {
                        m.playSound("meeting")
                    } else {
                        m.playSound("reminder")
                    }
                    m.lastEvents[eventID] = true
                }
            }
        }
    }

    // Check for free time (no events)
    if len(events) == 0 {
        m.playSound("free_time")
    }
}

func (m *CalendarMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| cal | System Tool | Free | macOS calendar |
| http | Go Stdlib | Free | API calls |
| google-calendar-api | Free | Google API | API calls |
| caldav-server | Server | Free/Varies | Self-hosted CalDAV |

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
| macOS | Supported | Uses cal command, API |
| Linux | Supported | Uses API (cal not available) |
| Windows | Not Supported | ccbell only supports macOS/Linux |
