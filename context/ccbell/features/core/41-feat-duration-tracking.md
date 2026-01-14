# Feature: Event Duration Tracking

Track how long Claude took to respond for each event.

## Summary

Record response duration (time between hook trigger and stop) to analyze performance.

## Motivation

- Understand response time patterns
- Identify slow requests
- Performance optimization insights

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Duration Storage

Claude Code hooks receive a context but don't include timing data. This feature requires environment variable tracking.

**Key Finding**: Current architecture doesn't pass timing data between hooks.

### Implementation Approach

```go
// Store start time in environment
const startTimeEnv = "CCBELL_START_TIME"

// On event trigger (permission_prompt, idle_prompt)
startTime := time.Now().UnixMilli()
os.Setenv(startTimeEnv, strconv.FormatInt(startTime, 10))

// On stop event - calculate duration
if startTimeStr := os.Getenv(startTimeEnv); startTimeStr != "" {
    startTime, _ := strconv.ParseInt(startTimeEnv, 10, 64)
    duration := time.Now().UnixMilli() - startTime

    // Store in state
    state.RecordDuration(eventType, duration)
}
```

### Duration Storage

```go
type DurationStore struct {
    Durations map[string][]int64  // event -> list of durations (ms)
    MaxEntries int                // Max durations to store per event
}

func (s *DurationStore) RecordDuration(eventType string, durationMs int64) {
    if s.Durations == nil {
        s.Durations = make(map[string][]int64)
    }
    s.Durations[eventType] = append(s.Durations[eventType], durationMs)

    // Trim old entries
    if len(s.Durations[eventType]) > s.MaxEntries {
        s.Durations[eventType] = s.Durations[eventType][len(s.Durations[eventType])-s.MaxEntries:]
    }
}
```

### Commands

```bash
/ccbell:stats duration          # Show duration statistics
/ccbell:stats duration --today  # Today's durations
/ccbell:stats duration stop     # Stop event only
/ccbell:stats duration --json   # JSON output

# Output
=== Duration Statistics ===

stop:
  Count:    1,234
  Average:  3.2s
  Min:      0.5s
  Max:      45.6s
  P50:      2.8s
  P95:      8.1s

permission_prompt:
  Count:    456
  Average:  1.2s
  ...
```

---

## Audio Player Compatibility

Duration tracking doesn't interact with audio playback:
- Purely state tracking feature
- No player changes required
- Runs before/after playback

---

## Implementation

### Hook Configuration

```json
{
  "hooks": [
    {
      "events": ["permission_prompt", "idle_prompt"],
      "matcher": "*",
      "type": "command",
      "command": "ccbell start-timer"
    },
    {
      "events": ["stop"],
      "matcher": "*",
      "type": "command",
      "command": "ccbell stop-timer"
    }
  ]
}
```

### State Extension

```go
type State struct {
    LastPlayed     map[string]time.Time `json:"lastPlayed,omitempty"`
    Cooldowns      map[string]time.Time `json:"cooldowns,omitempty"`
    EventCounters  map[string]int       `json:"eventCounters,omitempty"`
    Durations      map[string][]int64   `json:"durations,omitempty"`
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
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Hooks](https://github.com/mpolatcan/ccbell/blob/main/hooks/hooks.json) - Hook integration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time tracking |
| Linux | ✅ Supported | Time tracking |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
