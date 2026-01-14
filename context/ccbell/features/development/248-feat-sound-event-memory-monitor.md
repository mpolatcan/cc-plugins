# Feature: Sound Event Memory Monitor

Play sounds for memory usage thresholds and warnings.

## Summary

Monitor system memory usage, swap activity, and memory pressure, playing sounds when thresholds are exceeded.

## Motivation

- Memory warning alerts
- Swap activity detection
- OOM prevention
- Performance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Memory Events

| Event | Description | Example |
|-------|-------------|---------|
| High Usage | Memory > 80% | 85% used |
| Critical | Memory > 95% | 97% used |
| Swap Started | Swap usage began | Swap active |
| Swap High | Swap > 50% | 60% swap used |
| OOM Killer | Process killed | oom-killer |

### Configuration

```go
type MemoryMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WarningThreshold int             `json:"warning_threshold_percent"` // 80 default
    CriticalThreshold int            `json:"critical_threshold_percent"` // 95 default
    SwapWarning    bool              `json:"swap_warning"`
    SoundOnWarning bool              `json:"sound_on_warning"`
    SoundOnCritical bool             `json:"sound_on_critical"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 10 default
}

type MemoryEvent struct {
    UsedPercent   float64
    SwapPercent   float64
    AvailableMB   int64
    UsedMB        int64
    EventType     string // "warning", "critical", "swap_warning"
}
```

### Commands

```bash
/ccbell:memory status              # Show memory status
/ccbell:memory warning 80          # Set warning threshold
/ccbell:memory critical 95         # Set critical threshold
/ccbell:memory sound warning <sound>
/ccbell:memory sound critical <sound>
/ccbell:memory test                # Test memory sounds
```

### Output

```
$ ccbell:memory status

=== Sound Event Memory Monitor ===

Status: Enabled
Warning Threshold: 80%
Critical Threshold: 95%
Swap Warning: Yes

Current Memory:
  Used: 12.4 GB / 16.0 GB (78%)
  Available: 3.6 GB
  Swap: 2.1 GB / 8.0 GB (26%)

[========================================] 78%

Status: OK

Recent Events:
  [1] Warning (1 hour ago)
       Memory at 82%
  [2] Swap Active (2 days ago)
       Swap usage started

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Swap Warning: bundled:stop

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Memory monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Memory Monitor

```go
type MemoryMonitor struct {
    config           *MemoryMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    lastWarningTime  time.Time
    lastCriticalTime time.Time
}

func (m *MemoryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *MemoryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
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
    memInfo, err := m.getMemoryInfo()
    if err != nil {
        return
    }

    // Check warning threshold
    if memInfo.UsedPercent >= float64(m.config.WarningThreshold) &&
       memInfo.UsedPercent < float64(m.config.CriticalThreshold) {
        m.onWarning(memInfo)
    }

    // Check critical threshold
    if memInfo.UsedPercent >= float64(m.config.CriticalThreshold) {
        m.onCritical(memInfo)
    }

    // Check swap warning
    if m.config.SwapWarning && memInfo.SwapPercent >= 50 {
        m.onSwapWarning(memInfo)
    }
}

func (m *DockerMonitor) getMemoryInfo() (*MemoryInfo, error) {
    var memInfo MemoryInfo

    if runtime.GOOS == "darwin" {
        return m.getDarwinMemoryInfo()
    }
    return m.getLinuxMemoryInfo()
}

func (m *MemoryMonitor) getDarwinMemoryInfo() (*MemoryInfo, error) {
    cmd := exec.Command("vm_stat")
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    // Parse vm_stat output
    memInfo = &MemoryInfo{}

    // Also get total memory
    cmd = exec.Command("sysctl", "hw.memsize")
    totalOutput, err := cmd.Output()
    if err == nil {
        re := regexp.MustCompile(`hw.memsize:\s+(\d+)`)
        match := re.FindStringSubmatch(string(totalOutput))
        if len(match) >= 2 {
            if total, err := strconv.ParseUint(match[1], 10, 64); err == nil {
                memInfo.TotalBytes = total
            }
        }
    }

    return &memInfo, nil
}

func (m *MemoryMonitor) getLinuxMemoryInfo() (*MemoryInfo, error) {
    data, err := os.ReadFile("/proc/meminfo")
    if err != nil {
        return nil, err
    }

    memInfo := &MemoryInfo{}

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, ":", 2)
        if len(parts) < 2 {
            continue
        }

        key := strings.TrimSpace(parts[0])
        value := strings.TrimSpace(parts[1])

        value = strings.TrimSuffix(value, " kB")

        kb, err := strconv.ParseInt(value, 10, 64)
        if err != nil {
            continue
        }

        bytes := kb * 1024

        switch key {
        case "MemTotal":
            memInfo.TotalBytes = uint64(bytes)
        case "MemFree":
            memInfo.FreeBytes = uint64(bytes)
        case "MemAvailable":
            memInfo.AvailableBytes = uint64(bytes)
        case "Buffers":
            memInfo.BuffersBytes = uint64(bytes)
        case "Cached":
            memInfo.CachedBytes = uint64(bytes)
        case "SwapTotal":
            memInfo.SwapTotalBytes = uint64(bytes)
        case "SwapFree":
            memInfo.SwapFreeBytes = uint64(bytes)
        }
    }

    // Calculate used
    memInfo.UsedBytes = memInfo.TotalBytes - memInfo.FreeBytes - memInfo.BuffersBytes - memInfo.CachedBytes
    if memInfo.AvailableBytes == 0 {
        memInfo.AvailableBytes = memInfo.FreeBytes
    }

    // Calculate percentages
    if memInfo.TotalBytes > 0 {
        memInfo.UsedPercent = float64(memInfo.UsedBytes) / float64(memInfo.TotalBytes) * 100
    }

    if memInfo.SwapTotalBytes > 0 {
        swapUsed := memInfo.SwapTotalBytes - memInfo.SwapFreeBytes
        memInfo.SwapPercent = float64(swapUsed) / float64(memInfo.SwapTotalBytes) * 100
    }

    return memInfo, nil
}

func (m *MemoryMonitor) onWarning(memInfo *MemoryInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    // Debounce: don't repeat within 5 minutes
    if time.Since(m.lastWarningTime) < 5*time.Minute {
        return
    }

    m.lastWarningTime = time.Now()

    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *MemoryMonitor) onCritical(memInfo *MemoryInfo) {
    if !m.config.SoundOnCritical {
        return
    }

    // Debounce: don't repeat within 2 minutes
    if time.Since(m.lastCriticalTime) < 2*time.Minute {
        return
    }

    m.lastCriticalTime = time.Now()

    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}

func (m *MemoryMonitor) onSwapWarning(memInfo *MemoryInfo) {
    sound := m.config.Sounds["swap_warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /proc/meminfo | File | Free | Linux memory info |
| vm_stat | System Tool | Free | macOS memory info |
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
| macOS | Supported | Uses vm_stat and sysctl |
| Linux | Supported | Uses /proc/meminfo |
| Windows | Not Supported | ccbell only supports macOS/Linux |
