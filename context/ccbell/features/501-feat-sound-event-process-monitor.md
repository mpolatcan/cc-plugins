# Feature: Sound Event Process Monitor

Play sounds for process starts, stops, crashes, and resource threshold events.

## Summary

Monitor specific processes for status changes, crashes, and resource usage thresholds, playing sounds for process events.

## Motivation

- Process awareness
- Crash detection
- Resource tracking
- Service monitoring
- Anomaly detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Process Events

| Event | Description | Example |
|-------|-------------|---------|
| Process Started | Process started | new process |
| Process Stopped | Process exited | exited |
| Process Crashed | Process crashed | exit code != 0 |
| High Memory | Memory > threshold | 2GB used |
| High CPU | CPU > threshold | 80% CPU |
| Zombie Detected | Zombie process | zombie |

### Configuration

```go
type ProcessMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchProcesses   []string          `json:"watch_processes"` // "nginx", "postgres", "*"
    MemoryThresholdMB int              `json:"memory_threshold_mb"` // 1024
    CPUThresholdPercent int            `json:"cpu_threshold_percent"` // 80
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnStop      bool              `json:"sound_on_stop"`
    SoundOnCrash     bool              `json:"sound_on_crash"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:process status              # Show process status
/ccbell:process add nginx           # Add process to watch
/ccbell:process sound crash <sound>
/ccbell:process test                # Test process sounds
```

### Output

```
$ ccbell:process status

=== Sound Event Process Monitor ===

Status: Enabled
Watch Processes: all

Process Status:

[1] nginx (running)
    PID: 1234
    Memory: 150 MB
    CPU: 5%
    Status: Running
    Started: 2 hours ago
    Sound: bundled:process-nginx

[2] postgres (running)
    PID: 5678
    Memory: 2.5 GB
    CPU: 15%
    Status: Running
    Started: 2 hours ago
    Sound: bundled:process-postgres

[3] redis (stopped) *** STOPPED ***
    PID: N/A
    Memory: N/A
    CPU: N/A
    Status: Exited (0)
    Stopped: 5 min ago
    Sound: bundled:process-redis *** STOPPED ***

[4] app-api (running) *** HIGH MEMORY ***
    PID: 9999
    Memory: 3 GB *** HIGH ***
    CPU: 45%
    Status: Running
    Started: 1 hour ago
    Sound: bundled:process-app *** WARNING ***

Recent Events:

[1] redis: Process Stopped (5 min ago)
       Exited with code 0
       Sound: bundled:process-stop
  [2] app-api: High Memory (10 min ago)
       Memory usage 3 GB > 2 GB threshold
       Sound: bundled:process-high-mem
  [3] app-api: Process Started (1 hour ago)
       PID 9999 started
       Sound: bundled:process-start
  [4] worker: Process Crashed (2 hours ago)
       Exit code 139 (SIGSEGV)
       Sound: bundled:process-crash

Process Statistics:
  Total Processes: 4
  Running: 3
  Stopped: 1
  Crashes: 1
  High Memory: 1

Sound Settings:
  Start: bundled:process-start
  Stop: bundled:process-stop
  Crash: bundled:process-crash
  High Memory: bundled:process-high-mem

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds directly:
- Monitoring feature using ps, top, lsof
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Process Monitor

```go
type ProcessMonitor struct {
    config        *ProcessMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    processState  map[string]*ProcessInfo
    lastEventTime map[string]time.Time
}

type ProcessInfo struct {
    Name          string
    PID           int
    Status        string // "running", "stopped", "zombie"
    MemoryMB      float64
    CPUPercent    float64
    StartedAt     time.Time
    ExitCode      int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | System Tool | Free | Process status (POSIX) |
| top | System Tool | Free | Resource usage |
| pgrep | System Tool | Free | Process grep |

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
| macOS | Supported | Uses ps, top, pgrep |
| Linux | Supported | Uses ps, top, pgrep |
