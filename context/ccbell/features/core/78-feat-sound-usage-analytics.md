# Feature: Sound Usage Analytics

Track and analyze sound usage patterns.

## Summary

Detailed statistics on which sounds are played, when, and how often.

## Motivation

- Understand notification patterns
- Optimize sound selection
- Usage-based sound recommendations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Analytics Data

```go
type SoundAnalytics struct {
    SoundID        string            `json:"sound_id"`
    SoundPath      string            `json:"sound_path"`
    PlayCount      int               `json:"play_count"`
    LastPlayed     time.Time         `json:"last_played"`
    TotalDuration  time.Duration     `json:"total_duration"`
    HourlyUsage    map[int]int       `json:"hourly_usage"`    // Hour -> count
    DailyUsage     map[int]int       `json:"daily_usage"`     // Day -> count
    PeakHour       int               `json:"peak_hour"`
    PeakDay        int               `json:"peak_day"`
}

type AnalyticsStore struct {
    Sounds    map[string]*SoundAnalytics
    TotalPlays int
    StartDate time.Time
}
```

### Commands

```bash
/ccbell:analytics show               # Show all analytics
/ccbell:analytics show bundled:stop  # Specific sound
/ccbell:analytics top 10             # Most used sounds
/ccbell:analytics daily              # Daily breakdown
/ccbell:analytics hourly             # Hourly breakdown
/ccbell:analytics export             # Export data
/ccbell:analytics reset              # Reset all data
/ccbell:analytics trends             # Show trends
```

### Output

```
$ ccbell:analytics top 10

=== Most Used Sounds ===

[1] bundled:stop              1,234 plays (32.1%)
[2] bundled:permission_prompt   456 plays (11.8%)
[3] custom:notification         389 plays (10.1%)
[4] bundled:idle_prompt         234 plays (6.1%)
[5] bundled:subagent            198 plays (5.1%)

Total plays: 3,847

=== Usage by Hour ===

Peak: 10:00 (245 plays)
Quietest: 03:00 (12 plays)

00-04: ████░░░░░░░░░░░ 124
04-08: ██░░░░░░░░░░░░░ 89
08-12: ██████████░░░░░ 567
12-16: █████████░░░░░░ 512
16-20: ████████░░░░░░░ 456
20-24: ██████░░░░░░░░░ 345

=== Trends ===

Last 7 days: +12% increase
Last 30 days: +8% increase
```

---

## Audio Player Compatibility

Analytics doesn't interact with audio playback:
- Pure tracking feature
- No player changes required
- Reads from event triggers

---

## Implementation

### Tracking Integration

```go
func (c *CCBell) trackPlayback(eventType, soundPath string, volume float64) {
    if c.analyticsStore == nil {
        return
    }

    now := time.Now()

    analytics := c.analyticsStore.GetOrCreate(soundPath)
    analytics.PlayCount++
    analytics.LastPlayed = now
    analytics.HourlyUsage[now.Hour()]++
    analytics.DailyUsage[int(now.Weekday())]++

    // Update peak statistics
    if analytics.HourlyUsage[now.Hour()] > analytics.HourlyUsage[analytics.PeakHour] {
        analytics.PeakHour = now.Hour()
    }

    c.analyticsStore.Save()
}
```

### Trend Calculation

```go
func (a *AnalyticsStore) GetTrends() map[string]float64 {
    trends := make(map[string]float64)

    // Compare recent vs previous periods
    recentCount := a.getPlaysLastDays(7)
    previousCount := a.getPlaysDays(7, 14)

    if previousCount > 0 {
        trends["7d"] = float64(recentCount-previousCount) / float64(previousCount) * 100
    }

    return trends
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Analytics storage
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Tracking integration
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Analytics config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
