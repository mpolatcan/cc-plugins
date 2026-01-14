# Feature: Sound Event Debugging

Debug sound event handling.

## Summary

Debug tools for troubleshooting sound event issues.

## Motivation

- Debug playback issues
- Trace event flow
- Identify problems

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Debug Modes

| Mode | Description | Output |
|------|-------------|--------|
| Trace | Full event trace | Detailed log |
| Verbose | Detailed output | Extended info |
| Step | Step-by-step | Interactive |
| Record | Record session | Log file |

### Implementation

```go
type DebugConfig struct {
    Enabled     bool     `json:"enabled"`
    Level       string   `json:"level"`        // trace, verbose, info
    Output      string   `json:"output"`       // stdout, file
    LogFile     string   `json:"log_file"`
    MaxSizeMB   int      `json:"max_size_mb"`
    Events      []string `json:"events"`       // specific events
    IncludeEnv  bool     `json:"include_env"`  // include env vars
    IncludePath bool     `json:"include_path"` // show paths
}

type DebugSession struct {
    ID          string        `json:"id"`
    StartTime   time.Time     `json:"start_time"`
    Events      []DebugEvent  `json:"events"`
    Summary     DebugSummary  `json:"summary"`
}
```

### Commands

```bash
/ccbell:debug enable              # Enable debug mode
/ccbell:debug disable             # Disable debug mode
/ccbell:debug level trace         # Set debug level
/ccbell:debug event stop          # Debug specific event
/ccbell:debug output file ~/ccbell.log
/ccbell:debug session start       # Start debug session
/ccbell:debug session show        # Show session log
/ccbell:debug session export      # Export session
/ccbell:debug analyze             # Analyze debug output
```

### Output

```
$ ccbell:debug event stop

=== Debug: stop event ===

[10:30:15.123] INFO  Event received: stop
[10:30:15.124] DEBUG Loading config from: ~/.config/ccbell/config.json
[10:30:15.125] DEBUG Event config: {enabled=true, sound=bundled:stop, volume=0.5}
[10:30:15.126] DEBUG Checking quiet hours: active=false
[10:30:15.127] DEBUG Checking cooldown: in_cooldown=false
[10:30:15.128] DEBUG Resolving sound: bundled:stop
[10:30:15.129] DEBUG Sound path: ~/.local/share/ccbell/sounds/bundled/stop.aiff
[10:30:15.130] INFO  Playing sound: afplay -v 0.50 ~/.local/share/ccbell/sounds/bundled/stop.aiff
[10:30:15.456] DEBUG Playback initiated successfully
[10:30:15.457] INFO  Event completed

Summary:
  Duration: 334ms
  Status: SUCCESS
  Sound played: bundled:stop
```

---

## Audio Player Compatibility

Debugging doesn't play sounds:
- Tracing feature
- No player changes required
- Logs player commands

---

## Implementation

### Event Tracing

```go
func (d *DebugManager) traceEvent(eventType string) error {
    d.logger.Printf("[%s] INFO  Event received: %s", time.Now().Format("15:04:05.000"), eventType)

    // Load config
    cfg, _, err := config.Load(d.homeDir)
    d.logger.Printf("[%s] DEBUG Config loaded: %v", time.Now().Format("15:04:05.000"), err == nil)

    eventCfg := cfg.GetEventConfig(eventType)
    d.logger.Printf("[%s] DEBUG Event config: %+v", time.Now().Format("15:04:05.000"), eventCfg)

    // Check quiet hours
    inQuietHours := cfg.IsInQuietHours()
    d.logger.Printf("[%s] DEBUG Quiet hours: active=%v", time.Now().Format("15:04:05.000"), inQuietHours)

    // Check cooldown
    stateManager := state.NewManager(d.homeDir)
    inCooldown, _ := stateManager.CheckCooldown(eventType, derefInt(eventCfg.Cooldown, 0))
    d.logger.Printf("[%s] DEBUG Cooldown: in_cooldown=%v", time.Now().Format("15:04:05.000"), inCooldown)

    // Resolve sound
    player := audio.NewPlayer(d.pluginRoot)
    soundPath, err := player.ResolveSoundPath(eventCfg.Sound, eventType)
    d.logger.Printf("[%s] DEBUG Sound path: %s (err=%v)", time.Now().Format("15:04:05.000"), soundPath, err)

    return nil
}
```

### Session Analysis

```go
func (d *DebugManager) analyzeSession(sessionID string) *DebugAnalysis {
    session := d.loadSession(sessionID)

    issues := []string{}
    successes := []string{}

    for _, event := range session.Events {
        if event.Status == "failed" {
            issues = append(issues, fmt.Sprintf("%s: %s", event.EventType, event.Error))
        } else {
            successes = append(successes, event.EventType)
        }
    }

    return &DebugAnalysis{
        TotalEvents:  len(session.Events),
        Successes:    len(successes),
        Failures:     len(issues),
        Issues:       issues,
        Duration:     session.EndTime.Sub(session.StartTime),
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling trace
- [Logger](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go) - Debug logging

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
