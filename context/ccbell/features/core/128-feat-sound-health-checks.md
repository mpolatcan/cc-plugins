# Feature: Sound Health Checks

Monitor sound system health.

## Summary

Monitor and report on the health of the sound system.

## Motivation

- Detect issues early
- Monitor system status
- Proactive maintenance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Health Checks

| Check | Description | Status |
|-------|-------------|--------|
| Player | Audio player available | ✅/❌ |
| Sounds | All sounds accessible | ✅/❌ |
| Config | Config valid | ✅/❌ |
| Disk | Disk space OK | ✅/❌ |
| Permissions | File permissions OK | ✅/❌ |

### Implementation

```go
type HealthCheck struct {
    Name        string    `json:"name"`
    Status      string    `json:"status"` // healthy, warning, critical
    Message     string    `json:"message"`
    LastChecked time.Time `json:"last_checked"`
    Duration    int64     `json:"duration_ms"`
}

type HealthReport struct {
    Overall      string        `json:"overall"` // healthy, warning, critical
    Timestamp    time.Time     `json:"timestamp"`
    Checks       []HealthCheck `json:"checks"`
    Uptime       time.Duration `json:"uptime"`
    Version      string        `json:"version"`
    Platform     string        `json:"platform"`
}
```

### Commands

```bash
/ccbell:health                 # Run health checks
/ccbell:health --json          # JSON output
/ccbell:health --verbose       # Detailed output
/ccbell:health --check player  # Specific check
/ccbell:health monitor         # Continuous monitoring
/ccbell:health history         # Check history
/ccbell:health notify          # Notify on issues
```

### Output

```
$ ccbell:health

=== Sound Health Report ===

Overall: HEALTHY
Timestamp: Jan 15, 2024 10:30:15 AM
Version: 1.0.0
Platform: macOS (afplay)

Checks:
  [✓] Audio Player
      Status: healthy
      Message: afplay available
      Duration: 2ms

  [✓] Sound Files
      Status: healthy
      Message: 24/24 sounds accessible
      Duration: 45ms

  [✓] Configuration
      Status: healthy
      Message: Config valid
      Duration: 5ms

  [✓] Disk Space
      Status: healthy
      Message: 45GB available
      Duration: 3ms

  [✓] Permissions
      Status: healthy
      Message: All files readable
      Duration: 8ms

Uptime: 7d 12h 34m
[Monitor] [History] [Notify]
```

---

## Audio Player Compatibility

Health checks use existing audio player:
- Checks player availability
- Same format support
- No player changes required

---

## Implementation

### Health Check Execution

```go
func (h *HealthManager) runCheck(checkName string) *HealthCheck {
    start := time.Now()

    switch checkName {
    case "player":
        return h.checkPlayer(start)
    case "sounds":
        return h.checkSounds(start)
    case "config":
        return h.checkConfig(start)
    case "disk":
        return h.checkDisk(start)
    case "permissions":
        return h.checkPermissions(start)
    default:
        return &HealthCheck{
            Name:    checkName,
            Status:  "unknown",
            Message: fmt.Sprintf("Unknown check: %s", checkName),
        }
    }
}

func (h *HealthManager) checkPlayer(start time.Time) *HealthCheck {
    player := audio.NewPlayer(h.pluginRoot)
    hasPlayer := player.HasAudioPlayer()

    if hasPlayer {
        return &HealthCheck{
            Name:        "Audio Player",
            Status:      "healthy",
            Message:     fmt.Sprintf("%s available", player.Platform()),
            LastChecked: time.Now(),
            Duration:    time.Since(start).Milliseconds(),
        }
    }

    return &HealthCheck{
        Name:        "Audio Player",
        Status:      "critical",
        Message:     "No audio player available",
        LastChecked: time.Now(),
        Duration:    time.Since(start).Milliseconds(),
    }
}
```

### Continuous Monitoring

```go
func (h *HealthManager) startMonitoring(interval time.Duration) {
    ticker := time.NewTicker(interval)

    for range ticker.C {
        report := h.RunAllChecks()

        if report.Overall != "healthy" && h.config.NotifyOnIssues {
            h.notifyIssues(report)
        }

        h.saveReport(report)
    }
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

- [Player.HasAudioPlayer](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L217-235) - Player availability
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Sound accessibility

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
