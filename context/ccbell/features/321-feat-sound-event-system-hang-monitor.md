# Feature: Sound Event System Hang Monitor

Play sounds for system hangs, freezes, and unresponsiveness events.

## Summary

Monitor system responsiveness, detect hangs and freezes, playing sounds for unresponsiveness events.

## Motivation

- Hang detection
- Performance degradation alerts
- System health monitoring
- Recovery feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### System Hang Events

| Event | Description | Example |
|-------|-------------|---------|
| Load Spike | Sudden load increase | load > 50 |
| Process Hung | Process unresponsive | D state |
| IO Wait High | High iowait | > 50% CPU iowait |
| Memory Swap | Heavy swapping | > 50% swap used |

### Configuration

```go
type SystemHangMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    LoadThreshold    float64           `json:"load_threshold"` // 50.0 default
    IOWaitThreshold  float64           `json:"iowait_threshold"` // 50.0 default
    ProcessTimeout   int               `json:"process_timeout_sec"` // 300 default
    SoundOnHang      bool              `json:"sound_on_hang"]
    SoundOnRecovery  bool              `json:"sound_on_recovery"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type SystemHangEvent struct {
    EventType string // "load_spike", "iowait_high", "process_hung", "recovery"
    Value     float64
    Process   string
    Duration  time.Duration
}
```

### Commands

```bash
/ccbell:hang status                   # Show hang monitor status
/ccbell:hang load 50                  # Set load threshold
/ccbell:hang sound hang <sound>
/ccbell:hang sound recovery <sound>
/ccbell:hang test                     # Test hang sounds
```

### Output

```
$ ccbell:hang status

=== Sound Event System Hang Monitor ===

Status: Enabled
Load Threshold: 50.0
IO Wait Threshold: 50%
Process Timeout: 300s

System Status: OK

Current Load: 2.5
IO Wait: 2%
Hung Processes: 0

Recent Events:
  [1] Load Spike (5 min ago)
       Load: 55.0 (threshold: 50.0)
  [2] Recovery (10 min ago)
       System recovered from load spike
  [3] IO Wait High (2 hours ago)
       IO Wait: 55%

Hang Statistics:
  Load spikes: 5
  IO wait events: 2
  Total downtime: 30 min

Sound Settings:
  Hang: bundled:hang-alert
  Recovery: bundled:hang-recovery

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

System hang monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Hang Monitor

```go
type SystemHangMonitor struct {
    config           *SystemHangMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    systemState      *HangState
    lastEventTime    map[string]time.Time
}

type HangState struct {
    LoadAverage      float64
    IOWait           float64
    HungProcessCount int
    IsHanging        bool
    HangStartTime    time.Time
}

func (m *SystemHangMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.systemState = &HangState{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemHangMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSystemState()

    for {
        select {
        case <-ticker.C:
            m.checkSystemHang()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemHangMonitor) snapshotSystemState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinState()
    } else {
        m.snapshotLinuxState()
    }
}

func (m *SystemHangMonitor) snapshotDarwinState() {
    cmd := exec.Command("sysctl", "vm.loadavg")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLoadAvg(string(output))
}

func (m *SystemHangMonitor) snapshotLinuxState() {
    // Read load average
    data, err := os.ReadFile("/proc/loadavg")
    if err != nil {
        return
    }

    m.parseLoadAvg(string(data))

    // Read /proc/stat for iowait
    statData, err := os.ReadFile("/proc/stat")
    if err == nil {
        m.parseIOWait(string(statData))
    }

    // Check for hung processes
    m.checkHungProcesses()
}

func (m *SystemHangMonitor) checkSystemHang() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinHang()
    } else {
        m.checkLinuxHang()
    }
}

func (m *SystemHangMonitor) checkDarwinHang() {
    m.snapshotDarwinState()
}

func (m *SystemHangMonitor) checkLinuxHang() {
    // Check load average
    data, err := os.ReadFile("/proc/loadavg")
    if err != nil {
        return
    }

    m.parseLoadAvg(string(data))

    // Check iowait
    statData, err := os.ReadFile("/proc/stat")
    if err == nil {
        m.parseIOWait(string(statData))
    }

    // Check for hung processes
    m.checkHungProcesses()
}

func (m *SystemHangMonitor) parseLoadAvg(data string) {
    parts := strings.Fields(data)
    if len(parts) >= 3 {
        load1, _ := strconv.ParseFloat(parts[0], 64)
        m.systemState.LoadAverage = load1
    }
}

func (m *SystemHangMonitor) parseIOWait(data string) {
    lines := strings.Split(data, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "cpu") {
            parts := strings.Fields(line)
            if len(parts) >= 8 {
                // Format: cpu user nice system idle iowait irq softirq steal guest guest_nice
                iowaitIdx := 4 // approximately
                if iowaitIdx < len(parts) {
                    iowait, _ := strconv.ParseFloat(parts[iowaitIdx], 64)
                    m.systemState.IOWait = iowait
                }
            }
            break
        }
    }
}

func (m *SystemHangMonitor) checkHungProcesses() {
    cmd := exec.Command("ps", "axo", "pid,stat,comm")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    hungCount := 0
    lines := strings.Split(string(output), "\n")

    for _, line := range lines {
        if strings.Contains(line, " D ") {
            // D state = uninterruptible sleep (usually I/O waiting)
            hungCount++
        }
    }

    m.systemState.HungProcessCount = hungCount
}

func (m *SystemHangMonitor) evaluateHangState() {
    // Check for load spike
    if m.systemState.LoadAverage > m.config.LoadThreshold {
        if !m.systemState.IsHanging {
            m.onLoadSpike(m.systemState.LoadAverage)
        }
        m.systemState.IsHanging = true
        m.systemState.HangStartTime = time.Now()
    }

    // Check for high iowait
    if m.systemState.IOWait > m.config.IOWaitThreshold {
        if !m.systemState.IsHanging {
            m.onIOWaitHigh(m.systemState.IOWait)
        }
        m.systemState.IsHanging = true
        m.systemState.HangStartTime = time.Now()
    }

    // Check for hung processes
    if m.systemState.HungProcessCount > 3 {
        if !m.systemState.IsHanging {
            m.onProcessHung(m.systemState.HungProcessCount)
        }
        m.systemState.IsHanging = true
        m.systemState.HangStartTime = time.Now()
    }

    // Check for recovery
    isNormal := m.systemState.LoadAverage < m.config.LoadThreshold/2 &&
        m.systemState.IOWait < m.config.IOWaitThreshold/2 &&
        m.systemState.HungProcessCount == 0

    if m.systemState.IsHanging && isNormal {
        m.onHangRecovery(time.Since(m.systemState.HangStartTime))
        m.systemState.IsHanging = false
    }
}

func (m *SystemHangMonitor) onLoadSpike(load float64) {
    if !m.config.SoundOnHang {
        return
    }

    key := fmt.Sprintf("load:%.1f", load)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["hang"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemHangMonitor) onIOWaitHigh(iowait float64) {
    if !m.config.SoundOnHang {
        return
    }

    key := fmt.Sprintf("iowait:%.1f", iowait)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["hang"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemHangMonitor) onProcessHung(count int) {
    if !m.config.SoundOnHang {
        return
    }

    key := fmt.Sprintf("hung:%d", count)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["hang"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *SystemHangMonitor) onHangRecovery(duration time.Duration) {
    if !m.config.SoundOnRecovery {
        return
    }

    key := fmt.Sprintf("recovery:%s", duration.String())
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["recovery"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemHangMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| sysctl | System Tool | Free | macOS load average |
| /proc/loadavg | File | Free | Linux load average |
| /proc/stat | File | Free | Linux CPU stats |

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
| Linux | Supported | Uses /proc/loadavg, /proc/stat |
| Windows | Not Supported | ccbell only supports macOS/Linux |
