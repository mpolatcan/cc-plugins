# Feature: Sound Event System Load Monitor

Play sounds for high CPU load, load average thresholds, and system overload events.

## Summary

Monitor system load averages, CPU usage, and performance thresholds, playing sounds when load exceeds defined limits.

## Motivation

- Performance awareness
- Load tracking
- Overload detection
- Capacity planning
- Response time monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### System Load Events

| Event | Description | Example |
|-------|-------------|---------|
| Load Warning | load > CPU count | load 8 on 4 CPUs |
| Load Critical | load > 2x CPU count | load 12 on 4 CPUs |
| High CPU | CPU > 80% | 90% CPU |
| CPU Spikes | Sudden CPU spike | 100% spike |
| Load Average 1m | 1 min load high | load 10 |
| Load Average 15m | 15 min load high | load 8 |

### Configuration

```go
type SystemLoadMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WarningLoadPerCPU   float64           `json:"warning_load_per_cpu"` // 1.0 default
    CriticalLoadPerCPU  float64           `json:"critical_load_per_cpu"` // 2.0 default
    WarningCPUPercent   int               `json:"warning_cpu_percent"` // 80 default
    SoundOnWarning      bool              `json:"sound_on_warning"`
    SoundOnCritical     bool              `json:"sound_on_critical"`
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:load status                 # Show system load
/ccbell:load warning 1.0            # Set warning threshold
/ccbell:load sound warning <sound>
/ccbell:load test                   # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event System Load Monitor ===

Status: Enabled
Warning: 1.0 load per CPU
Critical: 2.0 load per CPU

System Load:

[1] Load Average
    1 min: 8.5 *** WARNING ***
    5 min: 6.2
    15 min: 4.5
    CPUs: 4
    Sound: bundled:load *** WARNING ***

[2] CPU Usage
    User: 65%
    System: 15%
    Idle: 20%
    Load: 80% *** WARNING ***
    Sound: bundled:load-cpu

[3] Per-Core Load

    Core 0: 95% *** HIGH ***
    Core 1: 85% *** HIGH ***
    Core 2: 70%
    Core 3: 60%

Recent Events:

[1] Load Average: Warning (5 min ago)
       8.5 load on 4 CPUs (2.1x threshold)
       Sound: bundled:load-warning
  [2] CPU Usage: High CPU (10 min ago)
       CPU usage at 90%
       Sound: bundled:load-cpu-warning
  [3] Load Average: Critical (30 min ago)
       12.0 load on 4 CPUs (3.0x threshold)
       Sound: bundled:load-critical

Load Statistics:
  CPUs: 4
  Current Load: 8.5
  Warning Count: 12
  Critical Count: 3
  Uptime: 45 days

Sound Settings:
  Warning: bundled:load-warning
  Critical: bundled:load-critical
  CPU Warning: bundled:load-cpu-warning

[Configure] [Test All]
```

---

## Audio Player Compatibility

Load monitoring doesn't play sounds directly:
- Monitoring feature using uptime, top, sysctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### System Load Monitor

```go
type SystemLoadMonitor struct {
    config        *SystemLoadMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    loadState     *LoadInfo
    lastEventTime time.Time
}

type LoadInfo struct {
    Load1m        float64
    Load5m        float64
    Load15m       float64
    CPUCount      int
    CPUPercent    float64
    Status        string // "healthy", "warning", "critical"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| uptime | System Tool | Free | Load average (POSIX) |
| sysctl | System Tool | Free | CPU count |
| nproc | System Tool | Free | Number of processors |
| top | System Tool | Free | CPU usage |

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
| macOS | Supported | Uses uptime, sysctl, top |
| Linux | Supported | Uses uptime, nproc, top |
