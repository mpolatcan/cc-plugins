# Feature: Sound Event Memory Usage Monitor

Play sounds for high memory usage, swap activity, and memory pressure events.

## Summary

Monitor system memory usage for high utilization, swap activity, and OOM events, playing sounds for memory events.

## Motivation

- Memory pressure awareness
- Swap activity detection
- OOM prevention
- Performance monitoring
- Resource alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Memory Usage Events

| Event | Description | Example |
|-------|-------------|---------|
| High Memory | Usage > threshold | > 80% |
| Critical Memory | Usage > critical | > 95% |
| Swap Active | Swap usage detected | > 0 |
| High Swap | Swap > threshold | > 50% |
| OOM Killer | Process killed | killed |
| Memory Normal | Back to normal | < 60% |

### Configuration

```go
type MemoryUsageMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WarningPercent    int               `json:"warning_percent"` // 80 default
    CriticalPercent   int               `json:"critical_percent"` // 95 default
    SwapWarning       int               `json:"swap_warning_percent"` // 50 default
    SoundOnHigh       bool              `json:"sound_on_high"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnSwap       bool              `json:"sound_on_swap"`
    SoundOnNormal     bool              `json:"sound_on_normal"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:memory status                # Show memory status
/ccbell:memory warning 80            # Set warning threshold
/ccbell:memory critical 95           # Set critical threshold
/ccbell:memory sound high <sound>
/ccbell:memory sound critical <sound>
/ccbell:memory test                  # Test memory sounds
```

### Output

```
$ ccbell:memory status

=== Sound Event Memory Usage Monitor ===

Status: Enabled
Warning Threshold: 80%
Critical Threshold: 95%
Swap Warning: 50%

Current Memory Status:

Memory:
  Used: 12.5 GB / 16.0 GB
  Usage: 78%
  Status: NORMAL

Swap:
  Used: 2.1 GB / 4.0 GB
  Usage: 52% *** WARNING ***
  Status: HIGH

Top Processes:

  1. chrome (1.2 GB)
  2. docker (0.8 GB)
  3. code (0.6 GB)
  4. postgres (0.5 GB)
  5. slack (0.4 GB)

Memory History:

  08:00: 72% (Normal)
  08:30: 75% (Normal)
  09:00: 82% (Warning) *** SOUND ***
  09:30: 85% (Warning)
  10:00: 78% (Normal)

Recent Events:
  [1] Memory High (1 hour ago)
       82% usage detected
  [2] Swap Active (2 hours ago)
       1.5 GB swap in use
  [3] Memory Normal (3 hours ago)
       Usage dropped to 65%

Memory Statistics:
  High Alerts Today: 5
  Critical Alerts: 0
  Avg Usage: 75%

Sound Settings:
  High: bundled:memory-high
  Critical: bundled:memory-critical
  Swap: bundled:memory-swap
  Normal: bundled:memory-normal

[Configure] [Test All]
```

---

## Audio Player Compatibility

Memory monitoring doesn't play sounds directly:
- Monitoring feature using vm_stat/free
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Memory Usage Monitor

```go
type MemoryUsageMonitor struct {
    config          *MemoryUsageMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    lastEventTime   map[string]time.Time
    lastStatus      string
}

type MemoryInfo struct {
    Total     uint64
    Used      uint64
    Available uint64
    UsedPercent float64
    SwapTotal uint64
    SwapUsed  uint64
    SwapPercent float64
}

func (m *MemoryUsageMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEventTime = make(map[string]time.Time)
    m.lastStatus = "unknown"
    go m.monitor()
}

func (m *MemoryUsageMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkMemoryStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MemoryUsageMonitor) checkMemoryStatus() {
    info := m.getMemoryInfo()

    status := m.calculateStatus(info)

    if status != m.lastStatus {
        m.onStatusChanged(status, info)
        m.lastStatus = status
    }
}

func (m *MemoryUsageMonitor) getMemoryInfo() *MemoryInfo {
    info := &MemoryInfo{}

    if runtime.GOOS == "darwin" {
        return m.getDarwinMemoryInfo(info)
    }
    return m.getLinuxMemoryInfo(info)
}

func (m *MemoryUsageMonitor) getLinuxMemoryInfo(info *MemoryInfo) *MemoryInfo {
    // Read /proc/meminfo
    data, err := os.ReadFile("/proc/meminfo")
    if err != nil {
        return info
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 2 {
            continue
        }

        key := parts[0]
        value, _ := strconv.ParseUint(parts[1], 10, 64)

        switch key {
        case "MemTotal:":
            info.Total = value * 1024
        case "MemAvailable:", "MemFree:":
            // Use MemAvailable if available, otherwise estimate
            if key == "MemAvailable:" {
                info.Available = value * 1024
            } else {
                info.Available = value * 1024
            }
        case "SwapTotal:":
            info.SwapTotal = value * 1024
        case "SwapFree:":
            info.SwapUsed = (info.SwapTotal - value*1024)
        }
    }

    info.Used = info.Total - info.Available
    if info.Total > 0 {
        info.UsedPercent = float64(info.Used) / float64(info.Total) * 100
    }
    if info.SwapTotal > 0 {
        info.SwapPercent = float64(info.SwapUsed) / float64(info.SwapTotal) * 100
    }

    return info
}

func (m *MemoryUsageMonitor) getDarwinMemoryInfo(info *MemoryInfo) *MemoryInfo {
    // Use vm_stat on macOS
    cmd := exec.Command("vm_stat")
    output, err := cmd.Output()
    if err != nil {
        return info
    }

    // Parse pages
    var pageSize uint64 = 4096 // Default, will be corrected

    // Get page size
    cmd = exec.Command("pagesize")
    psOutput, _ := cmd.Output()
    if len(psOutput) > 0 {
        pageSize, _ = strconv.ParseUint(strings.TrimSpace(string(psOutput)), 10, 64)
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 2 {
            continue
        }

        key := parts[0]
        value, _ := strconv.ParseUint(parts[1], 10, 64)

        switch key {
        case "MemTotal:":
            // Not directly available on macOS
        case "pages free:":
            info.Available = value * pageSize
        case "pages active:":
        case "pages inactive:":
        case "pages speculative:":
        case "pages wired down:":
            info.Used += value * pageSize
        }
    }

    // Get swap info
    cmd = exec.Command("sysctl", "-n", "vm.swapusage")
    swapOutput, _ := cmd.Output()
    // Parse: "total = 2048.00M  used = 512.00M  free = 1536.00M  (encrypted)"
    re := regexp.MustEach(`used = ([\d.]+)M`)
    matches := re.FindStringSubmatch(string(swapOutput))
    if len(matches) >= 2 {
        usedMB, _ := strconv.ParseFloat(matches[1], 64)
        info.SwapUsed = uint64(usedMB * 1024 * 1024)
    }

    return info
}

func (m *MemoryUsageMonitor) calculateStatus(info *MemoryInfo) string {
    if info.UsedPercent >= float64(m.config.CriticalPercent) {
        return "critical"
    }
    if info.UsedPercent >= float64(m.config.WarningPercent) {
        return "high"
    }
    if info.SwapPercent >= float64(m.config.SwapWarning) {
        return "swap_high"
    }
    return "normal"
}

func (m *MemoryUsageMonitor) onStatusChanged(status string, info *MemoryInfo) {
    switch status {
    case "critical":
        if m.config.SoundOnCritical {
            m.onMemoryCritical(info)
        }
    case "high":
        if m.config.SoundOnHigh {
            m.onMemoryHigh(info)
        }
    case "swap_high":
        if m.config.SoundOnSwap {
            m.onSwapHigh(info)
        }
    case "normal":
        if m.lastStatus == "high" || m.lastStatus == "critical" {
            if m.config.SoundOnNormal {
                m.onMemoryNormal(info)
            }
        }
    }
}

func (m *MemoryUsageMonitor) onMemoryHigh(info *MemoryInfo) {
    key := "memory:high"
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *MemoryUsageMonitor) onMemoryCritical(info *MemoryInfo) {
    key := "memory:critical"
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *MemoryUsageMonitor) onSwapHigh(info *MemoryInfo) {
    key := "memory:swap"
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["swap"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *MemoryUsageMonitor) onMemoryNormal(info *MemoryInfo) {
    key := "memory:normal"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["normal"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *MemoryUsageMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/meminfo | Linux Path | Free | Memory information |
| vm_stat | System Tool | Free | Memory stats (macOS) |
| sysctl | System Tool | Free | System info (macOS) |

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
