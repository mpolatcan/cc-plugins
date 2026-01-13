# Feature: Smart Quieting

Calendar-aware quiet periods that auto-silence notifications during meetings.

## Summary

Integrate with calendar APIs (Google Calendar, Outlook) to automatically enable quiet hours when the user has a meeting.

## Technical Feasibility

### Calendar APIs

| Service | API | Auth | Library |
|---------|-----|------|---------|
| Google Calendar | Google Calendar API | OAuth2 | google.golang.org/api/calendar/v3 |
| Outlook | Microsoft Graph API | OAuth | github.com/microsoftgraph/msgraph-sdk-go |
| CalDAV | Standard | Basic/Digest | github.com/emersion/go- CalDAV |

### Implementation

```go
type CalendarService interface {
    GetBusyIntervals(start, end time.Time) ([]BusyInterval, error)
}

func (c *CCBell) isInMeeting() bool {
    now := time.Now()
    intervals, _ := c.calendar.GetBusyIntervals(now, now.Add(1*time.Hour))

    for _, interval := range intervals {
        if now.After(interval.Start) && now.Before(interval.End) {
            return true
        }
    }
    return false
}
```

## Configuration

```json
{
  "smart_quieting": {
    "enabled": true,
    "provider": "google",
    "calendar_id": "primary",
    "buffer_minutes": 5,
    "fallback_profile": "silent"
  }
}
```

## Commands

```bash
/ccbell:calendar connect --provider google
/ccbell:calendar status
/ccbell:calendar sync
```
