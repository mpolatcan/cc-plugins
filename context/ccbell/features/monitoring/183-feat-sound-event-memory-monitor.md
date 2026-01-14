# Feature: Sound Event Memory Monitor

Play sounds based on memory usage.

## Summary

Play different sounds when memory usage crosses thresholds.

## Motivation

- Memory awareness
- Leak detection
- Resource warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Memory Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Used Percent | Memory used | > 80% used |
| Available | Low available | < 1GB free |
| Swap | Swap usage | Swap > 50% |
| Page Faults | High page faults | Rate spike |

### Configuration

```go
type MemoryConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 10 default
    Thresholds    *MemoryThresholds `json:"thresholds"`
    Sounds        map[string]string `json:"sounds"`
}

type MemoryThresholds struct {
    UsedPercent  float64 `json:"used_percent,omitempty"` // 0-100
    AvailableMB  int     `json:"available_mb,omitempty"`
    SwapPercent  float64 `json:"swap_percent,omitempty"` // 0-100
    PageFaultRate int    `json:"page_fault_rate,omitempty"` // per second
}

type MemoryState struct {
    TotalMB       int
    UsedMB        int
    AvailableMB   int
    UsedPercent   float64
    SwapTotalMB   int
    SwapUsedMB    int
    SwapPercent   float64
    PageFaults    int64
    PageFaultRate float64
}
```

### Commands

```bash
/ccbell:memory status               # Show current memory status
/ccbell:memory sound warning <sound>
/ccbell:memory sound critical <sound>
/ccbell:memory sound normal <sound>
/ccbell:memory threshold used 80    # Set usage threshold
/ccbell:memory threshold available 1024  # MB free threshold
/ccbell:memory enable               # Enable memory monitoring
/ccbell:memory disable              # Disable memory monitoring
/ccbell:memory test                 # Test memory sounds
```

### Output

```
$ ccbell:memory status

=== Sound Event Memory Monitor ===

Status: Enabled
Check Interval: 10s

Current Memory:
  Total: 16GB
  Used: 12.8GB (80%)
  Available: 3.2GB
  Swap: 4GB / 6GB (67%)

Thresholds:
  Warning: 80% used
  Critical: 90% used
  Available: 1GB

Sounds:
  Warning: bundled:stop
  Critical: bundled:stop
  Normal: bundled:stop

Status: WARNING
[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Memory monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Memory Monitor

```go
type MemoryMonitor struct {
    config   *MemoryConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastPageFaults int64
    lastCheckTime time.Time
    lastStatus    string
}

func (m *MemoryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastCheckTime = time.Now()
    go m.monitor()
}

func (m *MemoryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkMemory()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MemoryMonitor) checkMemory() {
    state, err := m.getMemoryState()
    if err != nil {
        log.Debug("Failed to get memory state: %v", err)
        return
    }

    status := m.calculateStatus(state)
    if status != m.lastStatus {
        m.playMemoryEvent(status)
    }

    m.lastStatus = status
    m.lastPageFaults = state.PageFaults
    m.lastCheckTime = time.Now()
}

func (m *MemoryMonitor) getMemoryState() (*MemoryState, error) {
    // Read from /proc/meminfo (Linux)
    data := readFile("/proc/meminfo")

    state := &MemoryState{}

    // Parse meminfo
    lines := strings.Split(data, "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 2 {
            continue
        }

        value, _ := strconv.ParseInt(parts[1], 10, 64)
        kb := value / 1024 // Convert to MB

        switch parts[0] {
        case "MemTotal:":
            state.TotalMB = int(kb)
        case "MemAvailable:", "MemFree:":
            state.AvailableMB += int(kb)
        case "MemAvailable:":
            state.AvailableMB = int(kb)
        case "SwapTotal:":
            state.SwapTotalMB = int(kb)
        case "SwapFree:":
            state.SwapUsedMB = state.SwapTotalMB - int(kb)
        }
    }

    state.UsedMB = state.TotalMB - state.AvailableMB
    state.UsedPercent = float64(state.UsedMB) / float64(state.TotalMB) * 100

    if state.SwapTotalMB > 0 {
        state.SwapPercent = float64(state.SwapUsedMB) / float64(state.SwapTotalMB) * 100
    }

    // Page faults (from /proc/vmstat)
    vmstat := readFile("/proc/vmstat")
    for _, line := range strings.Split(vmstat, "\n") {
        if strings.HasPrefix(line, "pgfault ") {
            parts := strings.Fields(line)
            faults, _ := strconv.ParseInt(parts[1], 10, 64)
            state.PageFaults = faults

            // Calculate rate
            elapsed := time.Since(m.lastCheckTime).Seconds()
            if elapsed > 0 {
                state.PageFaultRate = float64(faults-m.lastPageFaults) / elapsed
            }
            break
        }
    }

    return state, nil
}

func (m *MemoryMonitor) calculateStatus(state *MemoryState) string {
    if m.config.Thresholds.UsedPercent > 0 &&
       state.UsedPercent > m.config.Thresholds.UsedPercent {
        return "critical"
    }
    if m.config.Thresholds.AvailableMB > 0 &&
       state.AvailableMB < m.config.Thresholds.AvailableMB {
        return "warning"
    }
    return "normal"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /proc/meminfo | Filesystem | Free | Memory info |
| /proc/vmstat | Filesystem | Free | VM statistics |
| sysctl | System Tool | Free | macOS memory info |

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
