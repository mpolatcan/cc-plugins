# Feature: Sound Event CPU Monitor

Play sounds based on CPU usage.

## Summary

Play different sounds when CPU usage crosses thresholds.

## Motivation

- Performance awareness
- Overload warnings
- Build completion

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### CPU Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Load Average | System load | Load > 8 |
| Per Core | Per-core usage | Any core > 90% |
| Total | Total CPU usage | Total > 80% |
| Sustained | Sustained high load | > 10 min at high |

### Configuration

```go
type CPUConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 5 default
    Thresholds    *CPUThresholds   `json:"thresholds"`
    Sounds        map[string]string `json:"sounds"` // trigger -> sound
}

type CPUThresholds struct {
    Load1Min     float64 `json:"load_1min,omitempty"` // Load average 1 min
    Load5Min     float64 `json:"load_5min,omitempty"`
    UsagePercent float64 `json:"usage_percent,omitempty"` // 0-100
    CorePercent  float64 `json:"core_percent,omitempty"`
    SustainedSec int     `json:"sustained_seconds,omitempty"` // Sustained threshold time
}

type CPUState struct {
    Load1      float64
    Load5      float64
    Load15     float64
    UsagePercent float64
    CoreUsage  []float64
    Cores      int
    Temperature float64 // If available
}
```

### Commands

```bash
/ccbell:cpu status                  # Show current CPU status
/ccbell:cpu sound warning <sound>
/ccbell:cpu sound critical <sound>
/ccbell:cpu sound normal <sound>
/ccbell:cpu threshold load 8        # Set load threshold
/ccbell:cpu threshold usage 80      # Set usage threshold
/ccbell:cpu enable                  # Enable CPU monitoring
/ccbell:cpu disable                 # Disable CPU monitoring
/ccbell:cpu test                    # Test CPU sounds
```

### Output

```
$ ccbell:cpu status

=== Sound Event CPU Monitor ===

Status: Enabled
Check Interval: 5s

Current CPU:
  Load Average: 2.45, 3.12, 4.50
  Usage: 45%
  Cores: 8
  Temperature: 65°C

Thresholds:
  Load Warning: 8.0
  Usage Warning: 80%
  Sustained: 30s

Sounds:
  Warning: bundled:stop
  Critical: bundled:stop
  Normal: bundled:stop

Status: NORMAL
[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

CPU monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### CPU Monitor

```go
type CPUMonitor struct {
    config   *CPUConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastStatus string
    sustainedCount int
}

func (m *CPUMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *CPUMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkCPU()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CPUMonitor) checkCPU() {
    state, err := m.getCPUState()
    if err != nil {
        log.Debug("Failed to get CPU state: %v", err)
        return
    }

    status := m.calculateStatus(state)
    if status != m.lastStatus {
        m.playCPUEvent(status)
        m.sustainedCount = 0
    } else if status != "normal" {
        m.sustainedCount += m.config.CheckInterval
        if m.config.Thresholds.SustainedSec > 0 &&
           m.sustainedCount >= m.config.Thresholds.SustainedSec {
            m.playCPUEvent(status + "_sustained")
        }
    }

    m.lastStatus = status
}

func (m *CPUMonitor) getCPUState() (*CPUState, error) {
    // Read load average
    var loadavg [3]float64
    if _, err := fmt.Sscanf(readFile("/proc/loadavg"), "%f %f %f",
        &loadavg[0], &loadavg[1], &loadavg[2]); err != nil {
        return nil, err
    }

    // Get CPU count
    cores := runtime.NumCPU()

    // Get CPU usage from /proc/stat
    cpuLine := readFile("/proc/stat")
    parts := strings.Fields(cpuLine)
    if len(parts) < 8 {
        return nil, fmt.Errorf("invalid /proc/stat")
    }

    // Parse CPU times: user, nice, system, idle, iowait, irq, softirq, steal
    total := 0.0
    idle := 0.0
    for i := 1; i <= 7; i++ {
        val, _ := strconv.ParseFloat(parts[i], 64)
        total += val
        if i == 4 { // idle
            idle = val
        }
    }

    usage := ((total - idle) / total) * 100

    return &CPUState{
        Load1:      loadavg[0],
        Load5:      loadavg[1],
        Load15:     loadavg[2],
        UsagePercent: usage,
        Cores:      cores,
    }, nil
}

func (m *CPUMonitor) calculateStatus(state *CPUState) string {
    if m.config.Thresholds.Load1Min > 0 && state.Load1 > m.config.Thresholds.Load1Min {
        return "critical"
    }
    if m.config.Thresholds.UsagePercent > 0 && state.UsagePercent > m.config.Thresholds.UsagePercent {
        return "warning"
    }
    return "normal"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /proc/loadavg | Filesystem | Free | Load average |
| /proc/stat | Filesystem | Free | CPU statistics |
| sysctl | System Tool | Free | macOS CPU info |

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
| macOS | ✅ Supported | Uses sysctl |
| Linux | ✅ Supported | Uses /proc filesystem |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
