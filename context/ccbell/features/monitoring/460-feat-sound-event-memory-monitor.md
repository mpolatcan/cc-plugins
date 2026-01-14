# Feature: Sound Event Memory Monitor

Play sounds for memory usage thresholds, swap activity, and OOM events.

## Summary

Monitor system memory (RAM, swap, cache) for usage thresholds, swap activity, and memory pressure events, playing sounds for memory events.

## Motivation

- Memory awareness
- Performance monitoring
- OOM prevention
- Swap detection
- Cache pressure

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Memory Events

| Event | Description | Example |
|-------|-------------|---------|
| High Memory | > 80% used | 85% |
| Critical Memory | > 95% used | 97% |
| Swap Active | Swap being used | 2GB swap |
| High Swap | Swap > threshold | > 10% |
| OOM Killer | OOM invoked | killed |
| Low Memory | Available < threshold | < 100MB |

### Configuration

```go
type MemoryMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WarningPercent   int               `json:"warning_percent"` // 80 default
    CriticalPercent  int               `json:"critical_percent"` // 95 default
    SwapThresholdMB  int               `json:"swap_threshold_mb"` // 1000 default
    AvailableThresholdMB int           `json:"available_threshold_mb"` // 100 default
    SoundOnWarning   bool              `json:"sound_on_warning"`
    SoundOnCritical  bool              `json:"sound_on_critical"`
    SoundOnSwap      bool              `json:"sound_on_swap"`
    SoundOnOOM       bool              `json:"sound_on_oom"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:memory status               # Show memory status
/ccbell:memory warning 80           # Set warning threshold
/ccbell:memory sound warning <sound>
/ccbell:memory test                 # Test memory sounds
```

### Output

```
$ ccbell:memory status

=== Sound Event Memory Monitor ===

Status: Enabled
Warning: 80%
Critical: 95%
Swap Threshold: 1000 MB

Memory Status:

[1] System Memory
    Status: HEALTHY
    Total: 16 GB
    Used: 11 GB (68%)
    Available: 5 GB (32%)
    Cached: 6 GB
    Sound: bundled:memory-normal

[2] Swap
    Status: HEALTHY
    Total: 2 GB
    Used: 0 GB (0%)
    Free: 2 GB
    Sound: bundled:memory-swap

Recent Events:

[1] System Memory: High Usage (5 min ago)
       82% used > 80% threshold
       Sound: bundled:memory-warning
  [2] System Memory: Back to Normal (1 hour ago)
       68% used
       Sound: bundled:memory-normal
  [3] Swap: High Activity (2 hours ago)
       500 MB swap in use
       Sound: bundled:memory-swap

Memory Statistics:
  Total RAM: 16 GB
  Used RAM: 11 GB (68%)
  Swap Used: 0 GB (0%)
  Available: 5 GB

Sound Settings:
  Warning: bundled:memory-warning
  Critical: bundled:memory-critical
  Swap: bundled:memory-swap
  OOM: bundled:memory-oom

[Configure] [Test All]
```

---

## Audio Player Compatibility

Memory monitoring doesn't play sounds directly:
- Monitoring feature using vm_stat, free, sysctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Memory Monitor

```go
type MemoryMonitor struct {
    config        *MemoryMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    memoryState   *MemoryInfo
    lastEventTime map[string]time.Time
}

type MemoryInfo struct {
    TotalBytes     int64
    UsedBytes      int64
    AvailableBytes int64
    UsedPercent    float64
    CachedBytes    int64
    SwapTotalBytes int64
    SwapUsedBytes  int64
    SwapPercent    float64
    PageInBytes    int64
    PageOutBytes   int64
}

func (m *MemoryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.memoryState = nil
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *MemoryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotMemoryState()

    for {
        select {
        case <-ticker.C:
            m.checkMemoryState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MemoryMonitor) snapshotMemoryState() {
    m.checkMemoryState()
}

func (m *MemoryMonitor) checkMemoryState() {
    info := m.getMemoryInfo()
    if info != nil {
        m.processMemoryStatus(info)
    }
}

func (m *MemoryMonitor) getMemoryInfo() *MemoryInfo {
    if runtime.GOOS == "darwin" {
        return m.getMacOSMemoryInfo()
    }
    return m.getLinuxMemoryInfo()
}

func (m *MemoryMonitor) getMacOSMemoryInfo() *MemoryInfo {
    info := &MemoryInfo{}

    // Get memory stats using vm_stat
    cmd := exec.Command("vm_stat")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    pageSize := int64(4096) // Default page size on macOS

    for _, line := range lines {
        if strings.Contains(line, "Mach") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                pageSize, _ = strconv.ParseInt(parts[2], 10, 64)
            }
        }
    }

    // Get total memory using sysctl
    cmd = exec.Command("sysctl", "hw.memsize")
    sysctlOutput, _ := cmd.Output()
    memRe := regexp.MustEach(`memsize = (\d+)`)
    memMatches := memRe.FindStringSubmatch(string(sysctlOutput))
    if len(memMatches) >= 2 {
        info.TotalBytes, _ = strconv.ParseInt(memMatches[1], 10, 64)
    }

    // Parse vm_stat output
    for _, line := range lines {
        if strings.Contains(line, "Pages free:") {
            freeRe := regexp.MustEach(`:\s*(\d+)`)
            matches := freeRe.FindStringSubmatch(line)
            if len(matches) >= 2 {
                freePages, _ := strconv.ParseInt(matches[1], 10, 64)
                info.AvailableBytes = freePages * pageSize
            }
        }
        if strings.Contains(line, "Pages active:") {
            activeRe := regexp.MustEach(`:\s*(\d+)`)
            matches := activeRe.FindStringSubmatch(line)
            if len(matches) >= 2 {
                activePages, _ := strconv.ParseInt(matches[1], 10, 64)
                info.UsedBytes = (info.TotalBytes / pageSize - activePages*pageSize) / pageSize * pageSize
            }
        }
    }

    // Calculate used percentage
    info.UsedPercent = float64(info.UsedBytes) / float64(info.TotalBytes) * 100

    // Get swap info using sysctl
    cmd = exec.Command("sysctl", "vm.swapusage")
    swapOutput, _ := cmd.Output()
    swapRe := regexp.MustEach(`used = (\d+\.\d+)M,`)
    swapMatches := swapRe.FindStringSubmatch(string(swapOutput))
    if len(swapMatches) >= 2 {
        swapUsed, _ := strconv.ParseFloat(swapMatches[1], 64)
        info.SwapUsedBytes = int64(swapUsed * 1024 * 1024)
    }

    return info
}

func (m *MemoryMonitor) getLinuxMemoryInfo() *MemoryInfo {
    info := &MemoryInfo{}

    // Read /proc/meminfo
    data, err := os.ReadFile("/proc/meminfo")
    if err != nil {
        return nil
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, ":", 2)
        if len(parts) < 2 {
            continue
        }

        key := strings.TrimSpace(parts[0])
        valueStr := strings.TrimSpace(parts[1])
        valueStr = strings.TrimSuffix(valueStr, " kB")
        value, _ := strconv.ParseInt(valueStr, 10, 64)
        bytes := value * 1024

        switch key {
        case "MemTotal":
            info.TotalBytes = bytes
        case "MemAvailable":
            info.AvailableBytes = bytes
        case "MemFree":
            // Only use MemFree if MemAvailable is not available
            if info.AvailableBytes == 0 {
                info.AvailableBytes = bytes
            }
        case "Buffers":
            info.CachedBytes += bytes
        case "Cached":
            info.CachedBytes += bytes
        case "SwapTotal":
            info.SwapTotalBytes = bytes
        case "SwapFree":
            if info.SwapTotalBytes > 0 {
                info.SwapUsedBytes = info.SwapTotalBytes - bytes
            }
        case "SwapCached":
            info.SwapUsedBytes += bytes
        }
    }

    // Calculate used
    info.UsedBytes = info.TotalBytes - info.AvailableBytes
    info.UsedPercent = float64(info.UsedBytes) / float64(info.TotalBytes) * 100

    // Calculate swap percentage
    if info.SwapTotalBytes > 0 {
        info.SwapPercent = float64(info.SwapUsedBytes) / float64(info.SwapTotalBytes) * 100
    }

    return info
}

func (m *MemoryMonitor) processMemoryStatus(info *MemoryInfo) {
    if m.memoryState == nil {
        m.memoryState = info

        if info.UsedPercent >= float64(m.config.CriticalPercent) {
            if m.config.SoundOnCritical {
                m.onMemoryCritical(info)
            }
        } else if info.UsedPercent >= float64(m.config.WarningPercent) {
            if m.config.SoundOnWarning {
                m.onMemoryWarning(info)
            }
        }
        return
    }

    lastInfo := m.memoryState

    // Check for memory usage changes
    if info.UsedPercent >= float64(m.config.CriticalPercent) &&
       lastInfo.UsedPercent < float64(m.config.CriticalPercent) {
        if m.config.SoundOnCritical && m.shouldAlert("critical", 10*time.Minute) {
            m.onMemoryCritical(info)
        }
    } else if info.UsedPercent >= float64(m.config.WarningPercent) &&
            lastInfo.UsedPercent < float64(m.config.WarningPercent) {
        if m.config.SoundOnWarning && m.shouldAlert("warning", 30*time.Minute) {
            m.onMemoryWarning(info)
        }
    } else if info.UsedPercent < float64(m.config.WarningPercent) &&
            lastInfo.UsedPercent >= float64(m.config.WarningPercent) {
        m.onMemoryNormal(info)
    }

    // Check for swap usage
    swapThresholdBytes := int64(m.config.SwapThresholdMB) * 1024 * 1024
    if info.SwapUsedBytes > swapThresholdBytes &&
       lastInfo.SwapUsedBytes <= swapThresholdBytes {
        if m.config.SoundOnSwap && m.shouldAlert("swap", 15*time.Minute) {
            m.onSwapActive(info)
        }
    }

    m.memoryState = info
}

func (m *MemoryMonitor) onMemoryWarning(info *MemoryInfo) {
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *MemoryMonitor) onMemoryCritical(info *MemoryInfo) {
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *MemoryMonitor) onMemoryNormal(info *MemoryInfo) {
    sound := m.config.Sounds["normal"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *MemoryMonitor) onSwapActive(info *MemoryInfo) {
    sound := m.config.Sounds["swap"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *MemoryMonitor) onOOMEvent() {
    sound := m.config.Sounds["oom"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *MemoryMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| vm_stat | System Tool | Free | macOS memory stats |
| sysctl | System Tool | Free | System configuration |
| free | System Tool | Free | Linux memory stats |

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
| macOS | Supported | Uses vm_stat, sysctl |
| Linux | Supported | Uses free, /proc/meminfo |
