# Feature: Sound Event Process Limit Monitor

Play sounds for process and file descriptor limit changes.

## Summary

Monitor system limits, limit changes, and threshold warnings, playing sounds for limit events.

## Motivation

- Resource limit awareness
- Limit exhaustion alerts
- System configuration feedback
- Process count tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Process Limit Events

| Event | Description | Example |
|-------|-------------|---------|
| Limit Near | Process limit warning | 90% of max proc |
| Limit Changed | ulimit modified | max proc increased |
| PID Max Changed | PID max modified | 32768 -> 65536 |
| File Limit | FD limit warning | 90% of max |

### Configuration

```go
type ProcessLimitMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WarningThreshold  int               `json:"warning_threshold"` // 80 default
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnChange     bool              `json:"sound_on_change"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type ProcessLimitEvent struct {
    LimitType   string // "processes", "files", "pids"
    Current     int64
    Max         int64
    Percent     float64
    EventType   string // "warning", "changed", "critical"
}
```

### Commands

```bash
/ccbell:limits status                 # Show limit status
/ccbell:limits warning 80             # Set warning threshold
/ccbell:limits sound warning <sound>
/ccbell:limits sound change <sound>
/ccbell:limits test                   # Test limit sounds
```

### Output

```
$ ccbell:limits status

=== Sound Event Process Limit Monitor ===

Status: Enabled
Warning: 80%
Warning Sounds: Yes

System Limits:
  Max Processes: 2,048
  Current Processes: 1,500 (73%)
  Status: OK

  Max Files (FD): 2,097,152
  Current Files: 1,500,000 (71%)
  Status: OK

  Max PID: 32,768
  Current PID: 1,234
  Status: OK

Recent Events:
  [1] Process Warning (5 min ago)
       Processes at 80%
  [2] Limit Changed (1 hour ago)
       Max processes: 1024 -> 2048
  [3] PID Max Changed (2 hours ago)
       PID max: 32768

Limit Statistics:
  Warnings: 5
  Limit changes: 3

Sound Settings:
  Warning: bundled:limits-warning
  Change: bundled:limits-change
  Critical: bundled:limits-critical

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Process limit monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Limit Monitor

```go
type ProcessLimitMonitor struct {
    config           *ProcessLimitMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    limitState       *LimitState
    lastEventTime    map[string]time.Time
}

type LimitState struct {
    MaxProcesses int64
    CurrentProcs int64
    MaxFDs       int64
    CurrentFDs   int64
    MaxPID       int64
}

func (m *ProcessLimitMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.limitState = &LimitState{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ProcessLimitMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotLimitState()

    for {
        select {
        case <-ticker.C:
            m.checkLimitState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ProcessLimitMonitor) snapshotLimitState() {
    m.readCurrentLimits()
}

func (m *ProcessLimitMonitor) checkLimitState() {
    m.readCurrentLimits()
}

func (m *ProcessLimitMonitor) readCurrentLimits() {
    // Get max processes
    maxProcs := m.getMaxProcesses()
    currentProcs := m.getCurrentProcessCount()

    // Get max FDs
    maxFDs := m.getMaxFDs()
    currentFDs := m.getCurrentFDCount()

    // Get max PID
    maxPID := m.getMaxPID()

    state := &LimitState{
        MaxProcesses: maxProcs,
        CurrentProcs: currentProcs,
        MaxFDs:       maxFDs,
        CurrentFDs:   currentFDs,
        MaxPID:       maxPID,
    }

    if m.limitState.MaxProcesses == 0 {
        m.limitState = state
        return
    }

    // Check for limit changes
    if state.MaxProcesses != m.limitState.MaxProcesses {
        m.onLimitChanged("processes", state.MaxProcesses)
    }
    if state.MaxFDs != m.limitState.MaxFDs {
        m.onLimitChanged("files", state.MaxFDs)
    }
    if state.MaxPID != m.limitState.MaxPID {
        m.onLimitChanged("pids", state.MaxPID)
    }

    // Check for threshold warnings
    m.checkWarnings(state)

    m.limitState = state
}

func (m *ProcessLimitMonitor) getMaxProcesses() int64 {
    data, err := os.ReadFile("/proc/sys/kernel/pid_max")
    if err != nil {
        cmd := exec.Command("sysctl", "-n", "kern.maxproc")
        output, err := cmd.Output()
        if err != nil {
            return 0
        }
        val, _ := strconv.ParseInt(strings.TrimSpace(string(output)), 10, 64)
        return val
    }

    val, _ := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
    return val
}

func (m *ProcessLimitMonitor) getCurrentProcessCount() int64 {
    entries, err := os.ReadDir("/proc")
    if err != nil {
        return 0
    }

    count := int64(0)
    for _, entry := range entries {
        if _, err := strconv.Atoi(entry.Name()); err == nil {
            count++
        }
    }

    return count
}

func (m *ProcessLimitMonitor) getMaxFDs() int64 {
    data, err := os.ReadFile("/proc/sys/fs/file-max")
    if err != nil {
        return 0
    }

    val, _ := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
    return val
}

func (m *ProcessLimitMonitor) getCurrentFDCount() int64 {
    data, err := os.ReadFile("/proc/sys/fs/file-nr")
    if err != nil {
        return 0
    }

    parts := strings.Fields(string(data))
    if len(parts) >= 1 {
        val, _ := strconv.ParseInt(parts[0], 10, 64)
        return val
    }

    return 0
}

func (m *ProcessLimitMonitor) getMaxPID() int64 {
    return m.getMaxProcesses() // Same as pid_max
}

func (m *ProcessLimitMonitor) checkWarnings(state *LimitState) {
    // Check process warning
    if state.MaxProcesses > 0 {
        procPct := float64(state.CurrentProcs) / float64(state.MaxProcesses) * 100
        lastPct := float64(m.limitState.CurrentProcs) / float64(m.limitState.MaxProcesses) * 100

        if procPct >= float64(m.config.WarningThreshold) && lastPct < float64(m.config.WarningThreshold) {
            m.onLimitWarning("processes", state.CurrentProcs, state.MaxProcesses, procPct)
        }
    }

    // Check FD warning
    if state.MaxFDs > 0 {
        fdPct := float64(state.CurrentFDs) / float64(state.MaxFDs) * 100
        lastPct := float64(m.limitState.CurrentFDs) / float64(m.limitState.MaxFDs) * 100

        if fdPct >= float64(m.config.WarningThreshold) && lastPct < float64(m.config.WarningThreshold) {
            m.onLimitWarning("files", state.CurrentFDs, state.MaxFDs, fdPct)
        }
    }
}

func (m *ProcessLimitMonitor) onLimitWarning(limitType string, current int64, max int64, percent float64) {
    if !m.config.SoundOnWarning {
        return
    }

    eventType := "warning"
    if percent >= 95 {
        eventType = "critical"
    }

    key := fmt.Sprintf("warning:%s:%.0f", limitType, percent)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds[eventType]
        if sound != "" {
            volume := 0.5
            if eventType == "critical" {
                volume = 0.7
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *ProcessLimitMonitor) onLimitChanged(limitType string, newLimit int64) {
    if !m.config.SoundOnChange {
        return
    }

    key := fmt.Sprintf("change:%s", limitType)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ProcessLimitMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /proc/sys/kernel/pid_max | File | Free | Max processes |
| /proc/sys/fs/file-max | File | Free | Max file descriptors |
| /proc/sys/fs/file-nr | File | Free | Current FDs |

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
| macOS | Supported | Uses sysctl |
| Linux | Supported | Uses /proc/sys |
| Windows | Not Supported | ccbell only supports macOS/Linux |
