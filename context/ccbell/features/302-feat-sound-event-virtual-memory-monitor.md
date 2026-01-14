# Feature: Sound Event Virtual Memory Monitor

Play sounds for swap usage and memory pressure events.

## Summary

Monitor virtual memory usage, swap activity, and memory pressure, playing sounds for memory events.

## Motivation

- Memory pressure alerts
- Swap activity awareness
- OOM prevention
- Performance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Virtual Memory Events

| Event | Description | Example |
|-------|-------------|---------|
| Swap High | High swap usage | > 50% |
| Swap Critical | Critical swap usage | > 80% |
| Memory Pressure | Low available memory | < 10% |
| Swap In/Out | Active swapping | page in/out |

### Configuration

```go
type VirtualMemoryMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    SwapWarningPct     int               `json:"swap_warning_pct"` // 50 default
    SwapCriticalPct    int               `json:"swap_critical_pct"` // 80 default
    MemoryWarningPct   int               `json:"memory_warning_pct"` // 90 default
    SoundOnSwapWarning bool              `json:"sound_on_swap_warning"]
    SoundOnSwapCritical bool             `json:"sound_on_swap_critical"]
    SoundOnPressure    bool              `json:"sound_on_pressure"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type VirtualMemoryEvent struct {
    TotalSwap     int64
    UsedSwap      int64
    SwapPercent   float64
    TotalMemory   int64
    UsedMemory    int64
    AvailableMemory int64
    MemoryPercent float64
    EventType     string // "swap_warning", "swap_critical", "pressure"
}
```

### Commands

```bash
/ccbell:vm status                      # Show VM status
/ccbell:vm swap warning 50             # Set swap warning threshold
/ccbell:vm sound swap <sound>
/ccbell:vm sound pressure <sound>
/ccbell:vm test                        # Test VM sounds
```

### Output

```
$ ccbell:vm status

=== Sound Event Virtual Memory Monitor ===

Status: Enabled
Swap Warning: 50%
Swap Critical: 80%
Memory Warning: 90%

Memory: 16 GB
  Used: 14.4 GB (90%)
  Available: 1.6 GB
  Status: WARNING

Swap: 4 GB
  Used: 2.4 GB (60%)
  Status: WARNING

Recent Events:
  [1] Memory Pressure (5 min ago)
       Available memory at 1.6 GB (10%)
  [2] Swap Warning (10 min ago)
       Swap usage at 50%
  [3] Swap Critical (2 hours ago)
       Swap usage at 85%

Memory Statistics:
  Swap in: 100 MB/s
  Swap out: 50 MB/s

Sound Settings:
  Swap Warning: bundled:vm-warning
  Swap Critical: bundled:vm-critical
  Pressure: bundled:vm-pressure

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Virtual memory monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Virtual Memory Monitor

```go
type VirtualMemoryMonitor struct {
    config               *VirtualMemoryMonitorConfig
    player               *audio.Player
    running              bool
    stopCh               chan struct{}
    lastSwapPercent      float64
    lastMemoryPercent    float64
    lastSwapInRate       int64
    lastSwapOutRate      int64
}

func (m *VirtualMemoryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *VirtualMemoryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotVirtualMemory()

    for {
        select {
        case <-ticker.C:
            m.checkVirtualMemory()
        case <-m.stopCh:
            return
        }
    }
}

func (m *VirtualMemoryMonitor) snapshotVirtualMemory() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinVirtualMemory()
    } else {
        m.checkLinuxVirtualMemory()
    }
}

func (m *VirtualMemoryMonitor) checkVirtualMemory() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinVirtualMemory()
    } else {
        m.checkLinuxVirtualMemory()
    }
}

func (m *VirtualMemoryMonitor) checkDarwinVirtualMemory() {
    cmd := exec.Command("vm_stat")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Also get swap info
    swapCmd := exec.Command("sysctl", "vm.swapusage")
    swapOutput, _ := swapCmd.Output()

    m.parseDarwinVMStat(string(output), string(swapOutput))
}

func (m *VirtualMemoryMonitor) parseDarwinVMStat(vmStat string, swapInfo string) {
    // Parse vm_stat output
    lines := strings.Split(vmStat, "\n")
    pageSize := int64(4096) // Default page size

    var freePages, activePages, inactivePages, speculativePages int64

    for _, line := range lines {
        if strings.Contains(line, "Pages free:") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                freePages, _ = strconv.ParseInt(parts[2], 10, 64)
            }
        } else if strings.Contains(line, "Pages active:") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                activePages, _ = strconv.ParseInt(parts[2], 10, 64)
            }
        } else if strings.Contains(line, "Pages inactive:") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                inactivePages, _ = strconv.ParseInt(parts[2], 10, 64)
            }
        } else if strings.Contains(line, "Pages speculative:") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                speculativePages, _ = strconv.ParseInt(parts[2], 10, 64)
            }
        }
    }

    totalMemory := (freePages + activePages + inactivePages + speculativePages) * pageSize
    usedMemory := (activePages + inactivePages) * pageSize
    availableMemory := (freePages + speculativePages) * pageSize
    memoryPercent := float64(usedMemory) / float64(totalMemory) * 100

    // Parse swap info
    swapPercent := m.parseDarwinSwapInfo(swapInfo)

    m.evaluateVirtualMemory(usedMemory, totalMemory, availableMemory, memoryPercent, swapPercent)
}

func (m *VirtualMemoryMonitor) parseDarwinSwapInfo(swapInfo string) float64 {
    // Format: "total = 4096.00M  used = 2048.00M  free = 2048.00M  (encrypted)"
    re := regexp.MustCompile(`used = (\d+\.?\d*)M.*free = (\d+\.?\d*)M`)
    match := re.FindStringSubmatch(swapInfo)
    if match != nil {
        used, _ := strconv.ParseFloat(match[1], 64)
        free, _ := strconv.ParseFloat(match[2], 64)
        total := used + free
        if total > 0 {
            return (used / total) * 100
        }
    }
    return 0
}

func (m *VirtualMemoryMonitor) checkLinuxVirtualMemory() {
    // Read /proc/meminfo
    data, err := os.ReadFile("/proc/meminfo")
    if err != nil {
        return
    }

    m.parseMeminfo(string(data))
}

func (m *VirtualMemoryMonitor) parseMeminfo(meminfo string) {
    lines := strings.Split(meminfo, "\n")
    var memTotal, memFree, memAvailable, swapTotal, swapFree int64

    for _, line := range lines {
        if strings.HasPrefix(line, "MemTotal:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                memTotal, _ = strconv.ParseInt(parts[1], 10, 64)
            }
        } else if strings.HasPrefix(line, "MemFree:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                memFree, _ = strconv.ParseInt(parts[1], 10, 64)
            }
        } else if strings.HasPrefix(line, "MemAvailable:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                memAvailable, _ = strconv.ParseInt(parts[1], 10, 64)
            }
        } else if strings.HasPrefix(line, "SwapTotal:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                swapTotal, _ = strconv.ParseInt(parts[1], 10, 64)
            }
        } else if strings.HasPrefix(line, "SwapFree:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                swapFree, _ = strconv.ParseInt(parts[1], 10, 64)
            }
        }
    }

    usedMemory := memTotal - memFree - memAvailable
    memoryPercent := float64(usedMemory) / float64(memTotal) * 100

    usedSwap := swapTotal - swapFree
    var swapPercent float64
    if swapTotal > 0 {
        swapPercent = float64(usedSwap) / float64(swapTotal) * 100
    }

    m.evaluateVirtualMemory(usedMemory*1024, memTotal*1024, memAvailable*1024, memoryPercent, swapPercent)
}

func (m *VirtualMemoryMonitor) evaluateVirtualMemory(usedMemory, totalMemory, availableMemory int64, memoryPercent, swapPercent float64) {
    // Check memory pressure
    availablePercent := float64(availableMemory) / float64(totalMemory) * 100
    if availablePercent < 10 && m.lastMemoryPercent < 90 {
        m.onMemoryPressure()
    }

    // Check swap thresholds
    if swapPercent >= float64(m.config.SwapCriticalPct) {
        if m.lastSwapPercent < float64(m.config.SwapCriticalPct) {
            m.onSwapCritical(swapPercent)
        }
    } else if swapPercent >= float64(m.config.SwapWarningPct) {
        if m.lastSwapPercent < float64(m.config.SwapWarningPct) {
            m.onSwapWarning(swapPercent)
        }
    }

    m.lastSwapPercent = swapPercent
    m.lastMemoryPercent = memoryPercent
}

func (m *VirtualMemoryMonitor) onSwapWarning(percent float64) {
    if !m.config.SoundOnSwapWarning {
        return
    }

    sound := m.config.Sounds["swap_warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *VirtualMemoryMonitor) onSwapCritical(percent float64) {
    if !m.config.SoundOnSwapCritical {
        return
    }

    sound := m.config.Sounds["swap_critical"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *VirtualMemoryMonitor) onMemoryPressure() {
    if !m.config.SoundOnPressure {
        return
    }

    sound := m.config.Sounds["pressure"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| vm_stat | System Tool | Free | macOS VM stats |
| sysctl | System Tool | Free | macOS system info |
| /proc/meminfo | File | Free | Linux memory info |

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
| Linux | Supported | Uses /proc/meminfo |
| Windows | Not Supported | ccbell only supports macOS/Linux |
