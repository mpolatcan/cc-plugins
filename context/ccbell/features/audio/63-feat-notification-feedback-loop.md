# Feature: Notification Feedback Loop

Count and report failed notification attempts.

## Summary

Track failed notification events and provide diagnostics on why notifications didn't play.

## Motivation

- Debug notification issues
- Understand failure patterns
- Proactive troubleshooting

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Failure Tracking

```go
type NotificationFeedback struct {
    Timestamp   time.Time
    EventType   string
    Success     bool
    FailureType string  // "quiet_hours", "cooldown", "no_player", "missing_file", "disabled"
    Details     string
}
```

### Feedback Storage

```go
type FeedbackStore struct {
    Feedback    []NotificationFeedback
    MaxEntries  int
}

func (f *FeedbackStore) Add(feedback NotificationFeedback) {
    f.Feedback = append(f.Feedback, feedback)
    if len(f.Feedback) > f.MaxEntries {
        f.Feedback = f.Feedback[len(f.Feedback)-f.MaxEntries:]
    }
}
```

### Tracking Integration

```go
func (c *CCBell) runWithFeedback(eventType string) error {
    var feedback NotificationFeedback
    feedback.EventType = eventType
    feedback.Timestamp = time.Now()

    cfg, _, err := config.Load(homeDir)
    if err != nil {
        feedback.Success = false
        feedback.FailureType = "config_error"
        feedback.Details = err.Error()
        c.feedbackStore.Add(feedback)
        return err
    }

    // Check enabled
    eventCfg := cfg.GetEventConfig(eventType)
    if eventCfg.Enabled == nil || !*eventCfg.Enabled {
        feedback.Success = false
        feedback.FailureType = "disabled"
        feedback.Details = "Event disabled in config"
        c.feedbackStore.Add(feedback)
        return nil // Not an error, just suppressed
    }

    // Check quiet hours
    if cfg.IsInQuietHours() {
        feedback.Success = false
        feedback.FailureType = "quiet_hours"
        feedback.Details = "In quiet hours"
        c.feedbackStore.Add(feedback)
        return nil
    }

    // Check cooldown
    if c.isInCooldown(eventType) {
        feedback.Success = false
        feedback.FailureType = "cooldown"
        feedback.Details = "In cooldown period"
        c.feedbackStore.Add(feedback)
        return nil
    }

    // Try to play
    player := audio.NewPlayer(pluginRoot)
    soundPath, _ := player.ResolveSoundPath(eventCfg.Sound, eventType)

    err = player.Play(soundPath, *eventCfg.Volume)
    if err != nil {
        feedback.Success = false
        feedback.FailureType = "playback_failed"
        feedback.Details = err.Error()
        c.feedbackStore.Add(feedback)
        return err
    }

    feedback.Success = true
    c.feedbackStore.Add(feedback)
    return nil
}
```

### Commands

```bash
/ccbell:feedback show              # Show recent feedback
/ccbell:feedback show --failed     # Show only failures
/ccbell:feedback show stop         # Feedback for specific event
/ccbell:feedback stats             # Show statistics
/ccbell:feedback clear             # Clear feedback history
/ccbell:feedback export            # Export as JSON
```

### Output

```
$ ccbell feedback show --failed

=== Notification Feedback (Failed) ===

[1] 10:32:05 stop         cooldown          30s remaining
[2] 10:30:15 permission  quiet_hours       22:00-07:00
[3] 10:15:00 subagent    playback_failed   no audio player found

$ ccbell feedback stats

=== Feedback Statistics (24h) ===

Total attempts:  1,234
Successful:      1,100 (89.1%)
Failed:          134 (10.9%)

Failure breakdown:
  quiet_hours:    80 (59.7%)
  cooldown:       40 (29.9%)
  disabled:       10 (7.5%)
  playback_error:  4 (3.0%)
```

---

## Audio Player Compatibility

Feedback loop tracks player errors:
- Works with all audio players
- No player changes required
- Captures error information

---

## Implementation

### Config Extension

```go
type FeedbackConfig struct {
    Enabled    bool   `json:"enabled"`
    MaxEntries int    `json:"max_entries"`
    StorePath  string `json:"store_path"`
}
```

### Statistics Generation

```go
func (f *FeedbackStore) GetStats() FeedbackStats {
    stats := FeedbackStats{}

    for _, fb := range f.Feedback {
        if fb.Success {
            stats.Successful++
        } else {
            stats.Failed++
            stats.FailureTypes[fb.FailureType]++
        }
    }

    return stats
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Feedback integration point
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State pattern
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config checking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
