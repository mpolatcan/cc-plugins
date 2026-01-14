# Feature: Sound Event System Journal Monitor

Play sounds for systemd journal entries, log priorities, and filtering events.

## Summary

Monitor systemd journal for log entries matching patterns, priority levels, and custom filters, playing sounds for journal events.

## Motivation

- Log awareness
- Priority alerts
- Event detection
- System monitoring
- Debug feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Journal Events

| Event | Description | Example |
|-------|-------------|---------|
| Critical Log | Priority 0-2 | emerg, alert, crit |
| Error Log | Priority 3 | error |
| Warning Log | Priority 4 | warning |
| Pattern Match | Custom pattern | "ERROR" |
| Service Restart | Service restarted | restarted |
| Boot Complete | System booted | booted |

### Configuration

```go
type SystemJournalMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    PriorityFilter    string            `json:"priority_filter"` // "err", "warning", "crit"
    PatternFilters    []string          `json:"pattern_filters"` // "ERROR", "FAILED"
    SoundOnPriority   bool              `json:"sound_on_priority"`
    SoundOnPattern    bool              `json:"sound_on_pattern"`
    SoundOnBoot       bool              `json:"sound_on_boot"`
    SuppressSeconds   int               `json:"suppress_seconds"` // 30 default
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:journal status              # Show journal status
/ccbell:journal add err             # Add priority filter
/ccbell:journal pattern "ERROR"     # Add pattern filter
/ccbell:journal sound error <sound>
/ccbell:journal test                # Test journal sounds
```

### Output

```
$ ccbell:journal status

=== Sound Event System Journal Monitor ===

Status: Enabled
Priority Filter: err
Pattern Filters: ERROR, FAILED, panic

Journal Events (Last 1 hour):

[1] systemd: Critical (5 min ago)
       CRITICAL: nginx.service: Main process exited
       Sound: bundled:journal-critical

[2] kernel: Error (10 min ago)
       ERROR: I/O error on device sda, sector 12345
       Sound: bundled:journal-error

[3] sshd: Warning (30 min ago)
       WARNING: Failed password for root from 10.0.0.1
       Sound: bundled:journal-warning

[4] mysql: Pattern Match (1 hour ago)
       ERROR: Table 'users' doesn't exist
       Sound: bundled:journal-pattern

Recent Events:

[1] systemd: Critical Event (5 min ago)
       nginx.service failed
       Sound: bundled:journal-critical
  [2] kernel: I/O Error (10 min ago)
       Sector read error
       Sound: bundled:journal-error
  [3] sshd: Failed Login (30 min ago)
       Failed password attempt
       Sound: bundled:journal-warning
  [4] System: Boot Complete (2 hours ago)
       System boot completed
       Sound: bundled:journal-boot

Journal Statistics:
  Events Today: 1,234
  Critical: 2
  Error: 15
  Warning: 45
  Pattern Matches: 12

Sound Settings:
  Critical: bundled:journal-critical
  Error: bundled:journal-error
  Warning: bundled:journal-warning
  Pattern: bundled:journal-pattern

[Configure] [Add Filter] [Test All]
```

---

## Audio Player Compatibility

Journal monitoring doesn't play sounds directly:
- Monitoring feature using journalctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS - N/A) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### System Journal Monitor

```go
type SystemJournalMonitor struct {
    config        *SystemJournalMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    journalState  *JournalInfo
    lastEventTime map[string]time.Time
    suppressUntil time.Time
}

type JournalInfo struct {
    Priority   string // "emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"
    Message    string
    Unit       string
    Host       string
    Timestamp  time.Time
    Count      int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| journalctl | System Tool | Free | Systemd journal |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Not Supported | journalctl not available |
| Linux | Supported | Uses journalctl |
