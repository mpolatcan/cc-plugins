# Feature: Smart Quieting

Calendar-aware quiet periods that auto-silence notifications during meetings.

## Summary

Integrate with calendar APIs (Google Calendar, Outlook) to automatically enable quiet hours when the user has a meeting.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | High |
| **Estimated Effort** | 7-10 days |

---

## Technical Feasibility

### Current Quiet Hours Analysis

The current `internal/config/quiethours.go` implements:
- Time-based quiet hours (start/end HH:MM)
- `IsInQuietHours()` method

**Key Finding**: Smart quieting extends this by checking calendar events, not just time windows.

### Calendar APIs

| Service | API | Auth | Library | Free Tier |
|---------|-----|------|---------|-----------|
| Google Calendar | Google Calendar API | OAuth2 | google.golang.org/api/calendar/v3 | Yes (limited) |
| Outlook | Microsoft Graph API | OAuth | github.com/microsoftgraph/msgraph-sdk-go | Yes (limited) |
| CalDAV | Standard | Basic/Digest | github.com/emersion/go-caldav | Yes (self-hosted) |

### Implementation

```go
type CalendarService interface {
    GetBusyIntervals(start, end time.Time) ([]BusyInterval, error)
    IsConfigured() bool
}

func (c *CCBell) isInMeeting() bool {
    if c.calendar == nil || !c.calendar.IsConfigured() {
        return false
    }

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

---

## Feasibility Research

### Audio Player Compatibility

Smart quieting doesn't directly interact with audio playback. It affects the quiet hours check logic only.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Google Calendar API | External service | Free tier | Requires OAuth setup |
| Microsoft Graph API | External service | Free tier | Requires OAuth setup |
| CalDAV | Local/service | Free | Self-hosted option |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | OAuth flow works |
| Linux | ✅ Supported | OAuth flow works |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

### OAuth Complexity

**High Complexity Items:**
1. OAuth token management (refresh, storage)
2. Browser-based auth flow
3. Token security

**Recommendation:** Start with CalDAV (no OAuth) as it's simpler and works with local servers like Baikal.

---

## Implementation Notes

### Integration Point

In `cmd/ccbell/main.go`, modify the quiet hours check:

```go
// Check smart quiet hours (calendar)
if cfg.SmartQuieting != nil && cfg.SmartQuieting.Enabled {
    if c.isInMeeting() {
        log.Debug("In meeting, suppressing notification")
        return nil
    }
}
```

### Token Storage

Store OAuth tokens in `~/.claude/ccbell/calendar_tokens.json` with proper encryption.

### Caching

Cache calendar data for 5-10 minutes to reduce API calls.

---

## References

- [Google Calendar API](https://developers.google.com/calendar/api)
- [Microsoft Graph API](https://docs.microsoft.com/en-us/graph/api/resources/calendar)
- [Current quiet hours implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go)
