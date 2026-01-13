# Feature: Notification Dashboard

History of recent notifications with statistics.

## Summary

Track when notifications fired, show frequency, and display daily counts. Useful for understanding notification patterns.

## Technical Feasibility

### Event History Storage

```go
type NotificationRecord struct {
    ID        string    `json:"id"`
    Event     string    `json:"event"`
    Timestamp time.Time `json:"timestamp"`
    Duration  float64   `json:"duration_seconds,omitempty"`
    Profile   string    `json:"profile"`
    Played    bool      `json:"played"`
}

type HistoryStore struct {
    records    []NotificationRecord
    maxRecords int
}
```

### Statistics

| Metric | Description |
|--------|-------------|
| Today count | Notifications today |
| This week | Weekly distribution |
| Most frequent | Top event types |
| Average response | Claude response times |

## Commands

```bash
/ccbell:history          # Show recent notifications
/ccbell:history --stats  # Show statistics
/ccbell:history --clear  # Clear history

/ccbell:stats today      # Today's count
/ccbell:stats week       # Weekly breakdown
/ccbell:stats top        # Most frequent events
```

## Output

```
=== ccbell History ===

[1] stop      10:32:05  3.2s  profile:default
[2] stop      10:28:41  2.1s  profile:default
[3] permission 10:25:00  -    profile:default
[4] stop      10:20:15  4.5s  profile:focus

=== Statistics ===

Today: 23 notifications
This week: 156

Event breakdown:
  stop:           120 (77%)
  permission:     20 (13%)
  idle:           10 (6%)
  subagent:       6 (4%)

Average response time: 3.1s
```

## Configuration

```json
{
  "history": {
    "enabled": true,
    "max_entries": 1000,
    "retention_days": 30
  }
}
```
