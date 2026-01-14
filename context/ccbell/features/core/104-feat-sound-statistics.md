# Feature: Sound Statistics

Detailed usage statistics and reports.

## Summary

Comprehensive statistics about sound usage, preferences, and patterns.

## Motivation

- Understand usage patterns
- Identify optimization opportunities
- Usage-based decisions

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Statistics Types

| Statistic | Description | Metric |
|-----------|-------------|--------|
| Play count | Total plays per sound | Count |
| Duration | Total play time | Time |
| Events | Events triggered | Count |
| Failures | Failed playbacks | Count |
| Peak hours | busiest hours | Hour distribution |

### Implementation

```go
type SoundStatistics struct {
    Period        string            `json:"period"`        // "daily", "weekly", "monthly"
    StartDate     time.Time         `json:"start_date"`
    EndDate       time.Time         `json:"end_date"`
    TotalPlays    int               `json:"total_plays"`
    TotalDuration time.Duration     `json:"total_duration"`
    BySound       map[string]int    `json:"by_sound"`      // sound -> count
    ByEvent       map[string]int    `json:"by_event"`      // event -> count
    ByHour        map[int]int       `json:"by_hour"`       // hour -> count
    ByDay         map[int]int       `json:"by_day"`        // day -> count
    Failures      int               `json:"failures"`
    TopSounds     []SoundRank       `json:"top_sounds"`
    Trends        map[string]float64 `json:"trends"`       // period -> % change
}

type SoundRank struct {
    SoundID    string  `json:"sound_id"`
    PlayCount  int     `json:"play_count"`
    Percentage float64 `json:"percentage"`
}
```

### Commands

```bash
/ccbell:stats                  # Show all statistics
/ccbell:stats today            # Today's stats
/ccbell:stats weekly           # This week
/ccbell:stats monthly          # This month
/ccbell:stats by-sound         # Breakdown by sound
/ccbell:stats by-event         # Breakdown by event
/ccbell:stats by-hour          # Usage by hour
/ccbell:stats trends           # Show trends
/ccbell:stats export           # Export report
/ccbell:stats reset            # Reset statistics
```

### Output

```
$ ccbell:stats weekly

=== Sound Statistics ===

Period: Jan 8 - Jan 14, 2024
Total Plays: 1,234
Total Duration: 42m 15s
Failed: 3

=== By Sound ===

[1] bundled:stop              456 (37%) ████████████████
[2] bundled:permission_prompt 234 (19%) ████████
[3] bundled:idle_prompt       198 (16%) ██████
[4] bundled:subagent          178 (14%) █████
[5] custom:notification       123 (10%) ████

=== By Hour ===

Peak: 10:00-11:00 (89 plays)
Quiet: 03:00-04:00 (2 plays)

00-04: █░░░░░░░░░░░░░░░░░ 12
04-08: ██░░░░░░░░░░░░░░░░ 34
08-12: ████████████░░░░░░ 312
12-16: ███████████░░░░░░░ 278
16-20: ██████████░░░░░░░░ 234
20-24: ████████░░░░░░░░░░ 156

=== Trends ===

Last week: +12%
Last month: +8%
Last year: +45%

[Export] [Reset] [More]
```

---

## Audio Player Compatibility

Statistics don't play sounds:
- Tracking feature
- No player changes required

---

## Implementation

### Statistics Collection

```go
func (s *StatisticsManager) RecordPlay(soundID, eventType string) {
    now := time.Now()

    s.stats.TotalPlays++
    s.stats.BySound[soundID]++
    s.stats.ByEvent[eventType]++
    s.stats.ByHour[now.Hour()]++
    s.stats.ByDay[int(now.Weekday())]++

    // Update total duration (estimate)
    duration := s.getEstimatedDuration(soundID)
    s.stats.TotalDuration += duration

    s.saveStatistics()
}
```

### Trend Calculation

```go
func (s *StatisticsManager) CalculateTrends() map[string]float64 {
    trends := make(map[string]float64)

    // Last 7 days vs previous 7 days
    recent := s.getStatsForPeriod(7)
    previous := s.getStatsForPeriod(14, 7)

    if previous.TotalPlays > 0 {
        trends["7d"] = float64(recent.TotalPlays-previous.TotalPlays) / float64(previous.TotalPlays) * 100
    }

    // Last 30 days vs previous 30 days
    recent = s.getStatsForPeriod(30)
    previous = s.getStatsForPeriod(60, 30)

    if previous.TotalPlays > 0 {
        trends["30d"] = float64(recent.TotalPlays-previous.TotalPlays) / float64(previous.TotalPlays) * 100
    }

    return trends
}
```

### Report Generation

```go
func (s *StatisticsManager) GenerateReport(period string) (*Report, error) {
    stats := s.getStatsForPeriod(period)

    report := &Report{
        Title:      fmt.Sprintf("CCBell Statistics - %s", period),
        Generated:  time.Now(),
        Statistics: stats,
    }

    // Calculate rankings
    report.TopSounds = s.calculateRankings(stats.BySound)

    return report, nil
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Playback tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
