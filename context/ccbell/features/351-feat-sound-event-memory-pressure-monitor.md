# Feature: Sound Event Memory Pressure Monitor

Play sounds for memory pressure events and swap usage warnings.

## Summary

Monitor system memory usage, swap activity, and memory pressure levels, playing sounds for memory events.

## Motivation

- Memory awareness
- Swap usage alerts
- OOM prevention
- Memory pressure detection
- Performance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Memory Pressure Events

| Event | Description | Example |
|-------|-------------|---------|
| Memory Warning | Memory above threshold | 85% used |
| Memory Critical | Memory critically high | 95% used |
| Swap Usage High | Swap usage above limit | 50% swap used |
| Swap In/Out | Heavy swap activity | High paging |
| OOM Killer | OOM killer invoked | Process killed |

### Configuration

```go
type MemoryPressureMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WarningThreshold  int               `json:"warning_threshold"` // 85 default
    CriticalThreshold int               `json:"critical_threshold"` // 95 default
    SwapThreshold     int               `json:"swap_threshold"` // 50 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnSwap       bool              `json:"sound_on_swap"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type MemoryPressureEvent struct {
    MemoryUsed    int64 // percentage
    MemoryTotal   int64
    SwapUsed      int64 // percentage
    SwapTotal     int64
    AvailableMB   int64
    EventType     string // "warning", "critical", "swap", "oom"
}
```

### Commands

```bash
/ccbell:memory status                 # Show memory status
/ccbell:memory warning 85             # Set warning threshold
/ccbell:memory critical 95            # Set critical threshold
/ccbell:memory sound warning <sound>
/ccbell:memory sound critical <sound>
/ccbell:memory test                   # Test memory sounds
```

### Output

```
$ ccbell:memory status

=== Sound Event Memory Pressure Monitor ===

Status: Enabled
Warning: 85%
Critical: 95%
Swap Threshold: 50%
Warning Sounds: Yes
Critical Sounds: Yes

Memory Status:
  Used: 14.2 GB / 16 GB (89%)
  Available: 1.8 GB
  Status: WARNING
  Sound: bundled:memory-warning

Swap Status:
  Used: 2.5 GB / 8 GB (31%)
  Status: OK

Memory Details:
  Active: 8.5 GB
  Inactive: 4.2 GB
  Buffers: 1.1 GB
  Cached: 6.8 GB

Recent Events:
  [1] Memory: Warning (5 min ago)
       Memory usage: 89% > 85% threshold
  [2] Memory: High Swap Activity (10 min ago)
       Swap in/out increased
  [3] Memory: Critical (1 day ago)
       Memory usage: 96%

Memory Statistics:
  Avg Usage: 72%
  Max Usage: 96%
  OOM Events: 0

Sound Settings:
  Warning: bundled:memory-warning
  Critical: bundled:memory-critical
  Swap: bundled:memory-swap

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Memory pressure monitoring doesn't play sounds directly:
- Monitoring feature using /proc/meminfo
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Memory Pressure Monitor

```go
type MemoryPressureMonitor struct {
    config          *MemoryPressureMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    memState        *MemInfo
    lastEventTime   map[string]time.Time
}

type MemInfo struct {
    TotalMem     int64
    AvailableMem int64
    UsedMem      int64
    UsedPercent  float64
    TotalSwap    int64
    UsedSwap     int64
    UsedSwapPercent float64
    LastUpdate   time.Time
}

func (m *MemoryPressureMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.memState = &MemInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *MemoryPressureMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotMemState()

    for {
        select {
        case <-ticker.C:
            m.checkMemState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MemoryPressureMonitor) snapshotMemState() {
    m.checkMemState()
}

func (m *MemoryPressureMonitor) checkMemState() {
    data, err := os.ReadFile("/proc/meminfo")
    if err != nil {
        return
    }

    newState := &MemInfo{LastUpdate: time.Now()}

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, ":", 2)
        if len(parts) != 2 {
            continue
        }

        key := strings.TrimSpace(parts[0])
        valueStr := strings.TrimSpace(parts[1])
        value, _ := strconv.ParseInt(strings.Fields(valueStr)[0], 10, 64)

        switch key {
        case "MemTotal":
            newState.TotalMem = value * 1024
        case "MemAvailable":
            newState.AvailableMem = value * 1024
        case "MemFree":
            // Used for calculation
        case "SwapTotal":
            newState.TotalSwap = value * 1024
        case "SwapFree":
            // Used for calculation
        case "Buffers":
            // Add to available
            newState.AvailableMem += value * 1024
        case "Cached":
            // Add to available
            newState.AvailableMem += value * 1024
        }
    }

    if newState.TotalMem > 0 {
        newState.UsedMem = newState.TotalMem - newState.AvailableMem
        newState.UsedPercent = float64(newState.UsedMem) / float64(newState.TotalMem) * 100
    }

    if newState.TotalSwap > 0 {
        newState.UsedSwap = newState.TotalSwap - newState.UsedSwap
        newState.UsedSwapPercent = float64(newState.UsedSwap) / float64(newState.TotalSwap) * 100
    }

    if m.memState.TotalMem > 0 {
        m.evaluateMemEvents(newState, m.memState)
    }

    m.memState = newState
}

func (m *MemoryPressureMonitor) evaluateMemEvents(newState *MemInfo, lastState *MemInfo) {
    // Check warning threshold
    if newState.UsedPercent >= float64(m.config.WarningThreshold) &&
        lastState.UsedPercent < float64(m.config.WarningThreshold) {
        if newState.UsedPercent >= float64(m.config.CriticalThreshold) {
            m.onMemoryCritical(newState)
        } else {
            m.onMemoryWarning(newState)
        }
    }

    // Check critical threshold
    if newState.UsedPercent >= float64(m.config.CriticalThreshold) &&
        lastState.UsedPercent < float64(m.config.CriticalThreshold) &&
        newState.UsedPercent < float64(m.config.WarningThreshold) {
        m.onMemoryCritical(newState)
    }

    // Check swap threshold
    if newState.UsedSwapPercent >= float64(m.config.SwapThreshold) &&
        lastState.UsedSwapPercent < float64(m.config.SwapThreshold) {
        m.onHighSwapUsage(newState)
    }

    // Check return to normal
    if newState.UsedPercent < float64(m.config.WarningThreshold)*0.8 &&
        lastState.UsedPercent >= float64(m.config.WarningThreshold) {
        m.onMemoryNormal(newState)
    }
}

func (m *MemoryPressureMonitor) onMemoryWarning(state *MemInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    key := "warning"
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *MemoryPressureMonitor) onMemoryCritical(state *MemInfo) {
    if !m.config.SoundOnCritical {
        return
    }

    key := "critical"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *MemoryPressureMonitor) onHighSwapUsage(state *MemInfo) {
    if !m.config.SoundOnSwap {
        return
    }

    key := "swap"
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["swap"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *MemoryPressureMonitor) onMemoryNormal(state *MemInfo) {
    // Optional: sound when memory returns to normal
}

func (m *MemoryPressureMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/meminfo | File | Free | Memory information |
| vm_stat | System Tool | Free | macOS memory stats |

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
| macOS | Supported | Uses vm_stat |
| Linux | Supported | Uses /proc/meminfo |
