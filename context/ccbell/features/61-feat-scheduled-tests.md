# Feature: Scheduled Tests

Automatically test notification sounds at regular intervals.

## Summary

Run periodic tests to verify sounds and configuration are working correctly.

## Motivation

- Detect broken sounds early
- Ensure audio system is functional
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

### Test Schedule Configuration

```json
{
  "scheduled_tests": {
    "enabled": true,
    "interval_hours": 24,
    "time": "09:00",
    "events": ["stop", "permission_prompt", "idle_prompt", "subagent"],
    "skip_quiet_hours": true,
    "volume": 0.3
  }
}
```

### Implementation

```go
type ScheduledTest struct {
    Enabled      bool     `json:"enabled"`
    IntervalHrs  int      `json:"interval_hours"`
    Time         string   `json:"time"`  // HH:MM
    Events       []string `json:"events"`
    SkipQuietHrs bool     `json:"skip_quiet_hours"`
    Volume       float64  `json:"volume"`
}

type TestScheduler struct {
    config *ScheduledTest
    ticker *time.Ticker
    stopCh chan struct{}
}
```

### Test Execution

```go
func (s *TestScheduler) RunTests() error {
    cfg, _, err := config.Load(homeDir)
    if err != nil {
        return err
    }

    // Check if quiet hours and skip
    if s.config.SkipQuietHrs && cfg.IsInQuietHours() {
        log.Debug("Skipping scheduled test - in quiet hours")
        return nil
    }

    player := audio.NewPlayer(pluginRoot)

    for _, eventType := range s.config.Events {
        eventCfg := cfg.GetEventConfig(eventType)
        if !*eventCfg.Enabled {
            log.Debug("Skipping disabled event: %s", eventType)
            continue
        }

        soundPath, _ := player.ResolveSoundPath(eventCfg.Sound, eventType)
        volume := s.config.Volume
        if volume == 0 {
            volume = *eventCfg.Volume
        }

        log.Info("Scheduled test: %s", eventType)
        if err := player.Play(soundPath, volume); err != nil {
            log.Error("Test failed for %s: %v", eventType, err)
            return err
        }

        // Wait between sounds
        time.Sleep(2 * time.Second)
    }

    return nil
}
```

### Scheduler Loop

```go
func (s *TestScheduler) Start() {
    s.stopCh = make(chan struct{})

    // Calculate next run time
    nextRun := s.calculateNextRun()

    go func() {
        for {
            select {
            case <-s.stopCh:
                return
            case <-time.After(time.Until(nextRun)):
                s.RunTests()
                nextRun = s.calculateNextRun()
            }
        }
    }()
}
```

### Commands

```bash
/ccbell:test scheduled           # Run scheduled test now
/ccbell:test scheduled --status  # Show next scheduled time
/ccbell:test scheduled disable   # Disable scheduled tests
/ccbell:test scheduled set 24h   # Set 24-hour interval
/ccbell:test scheduled set 09:00 # Set daily at 9 AM
```

### Output

```
$ ccbell test scheduled --status

Scheduled Tests: Enabled
Next test: Jan 15, 09:00 (in 18h 32m)
Events: stop, permission_prompt, idle_prompt, subagent
Interval: 24 hours
Skip quiet hours: true

$ ccbell test scheduled

Running scheduled tests...
[OK] stop: bundled:stop (0.50)
[OK] permission_prompt: bundled:permission_prompt (0.70)
[OK] idle_prompt: bundled:idle_prompt (0.50)
[OK] subagent: bundled:subagent (0.50)

All tests passed
```

---

## Audio Player Compatibility

Scheduled tests use existing audio player:
- Same `player.Play()` method
- Same format support
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Test playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Test config
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Skip logic

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | time-based scheduler |
| Linux | ✅ Supported | time-based scheduler |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
