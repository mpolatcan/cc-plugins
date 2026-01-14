# Feature: Sound Event Crash Dump Monitor

Play sounds for crash dump generation, core dump creation, and kernel panic events.

## Summary

Monitor crash dump locations (core dumps, kernel dumps, crash reports) for new dumps and system crashes, playing sounds for crash events.

## Motivation

- Crash awareness
- Debug notification
- System stability
- Memory dump detection
- Problem identification

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Crash Dump Events

| Event | Description | Example |
|-------|-------------|---------|
| Core Dump | Process crashed | core dumped |
| Kernel Panic | Kernel panic | panic |
| Crash Report | Report generated | report created |
| Oops Message | Kernel oops | oops |
| Hung Task | Task hung | hung task |
| Dump Size | Large dump | > 100MB |

### Configuration

```go
type CrashDumpMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchPaths       []string          `json:"watch_paths"` // "/var/crash", "/cores", "*"
    SizeThresholdMB  int               `json:"size_threshold_mb"` // 100 default
    SoundOnCore      bool              `json:"sound_on_core"`
    SoundOnPanic     bool              `json:"sound_on_panic"`
    SoundOnReport    bool              `json:"sound_on_report"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:crash status                # Show crash dump status
/ccbell:crash add /var/crash        # Add path to watch
/ccbell:crash size 100              # Set size threshold
/ccbell:crash sound core <sound>
/ccbell:crash test                  # Test crash sounds
```

### Output

```
$ ccbell:crash status

=== Sound Event Crash Dump Monitor ===

Status: Enabled
Watch Paths: /var/crash, /cores
Size Threshold: 100 MB

Crash Dump Status:

[1] /var/crash
    Status: CLEAN
    Dumps Today: 2
    Total Size: 250 MB
    Last Dump: Jan 14 10:30
    Sound: bundled:crash-var

[2] /cores
    Status: NEW DUMP *** CRASH ***
    Dumps Today: 1
    Total Size: 150 MB *** LARGE ***
    Last Dump: 5 min ago (nginx.core)
    Size: 150 MB
    Sound: bundled:crash-core *** FAILED ***

Recent Events:

[1] /cores: Core Dump (5 min ago)
       nginx.core (150 MB)
       PID: 12345
       Signal: SIGSEGV
       Sound: bundled:crash-core
  [2] /var/crash: Kernel Panic (1 hour ago)
       kernelpanic-2026-01-14-09:30.dump
       Size: 100 MB
       Sound: bundled:crash-panic
  [3] /var/crash: Crash Report (2 hours ago)
       apache2-crash-report.tar.gz
       Size: 50 MB
       Sound: bundled:crash-report

Crash Dump Statistics:
  Total Dumps: 3
  Core Dumps: 1
  Kernel Panics: 1
  Crash Reports: 1
  Total Size: 300 MB

Sound Settings:
  Core: bundled:crash-core
  Panic: bundled:crash-panic
  Report: bundled:crash-report
  Large: bundled:crash-large

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Crash dump monitoring doesn't play sounds directly:
- Monitoring feature using find, ls
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Crash Dump Monitor

```go
type CrashDumpMonitor struct {
    config        *CrashDumpMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    dumpState     map[string]*DumpInfo
    lastEventTime map[string]time.Time
}

type DumpInfo struct {
    Path       string
    Type       string // "core", "panic", "report"
    Status     string // "clean", "new"
    Count      int
    TotalSize  int64
    LastDump   time.Time
    LastSize   int64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| find | System Tool | Free | File search |
| ls | System Tool | Free | Directory listing |

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
| macOS | Supported | Uses ~/Library/Logs/DiagnosticReports |
| Linux | Supported | Uses /var/crash, /cores |
