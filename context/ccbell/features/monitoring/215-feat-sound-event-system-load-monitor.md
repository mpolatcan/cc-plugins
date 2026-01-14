# Feature: Sound Event System Load Monitor

Play sounds for system load and resource usage events.

## Summary

Monitor CPU load and system load averages, memory usage,, playing sounds when thresholds are exceeded.

## Motivation

- High load awareness
- Memory pressure alerts
- Performance monitoring
- Resource exhaustion prevention

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### System Load Events

| Event | Description | Example |
|-------|-------------|---------|
| High CPU Load | CPU above threshold | Load > 80% |
| High Memory | Memory above threshold | RAM > 90% |
| High Load Average | System overloaded | Load > CPU count |
| Low Memory | Memory critically low | RAM < 5% |
| Swap Used | Heavy swap usage | Swap > 50% |

### Configuration

```go
type SystemLoadMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    CPUThreshold     float64           `json:"cpu_threshold"` // 80 default
    MemoryThreshold  float64           `json:"memory_threshold"` // 90 default
    LoadThreshold    float64           `json:"load_threshold"` // 2.0 default
    SwapThreshold    float64           `json:"swap_threshold"` // 50 default
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
    Sounds           map[string]string `json:"sounds"`
    NotifyOnce       bool              `json:"notify_once"` // Don't repeat
}

type SystemLoadStatus struct {
    CPUUsage    float64
    MemoryUsage float64
    MemoryTotal uint64
    MemoryUsed  uint64
    SwapUsage   float64
    LoadAverage float64
    Procs       int
}
```

### Commands

```bash
/ccbell:load status               # Show system load
/ccbell:load cpu <percent>        # Set CPU threshold
/ccbell:load memory <percent>     # Set memory threshold
/ccbell:load load <value>         # Set load threshold
/ccbell:load sound high <sound>
/ccbell:load sound critical <sound>
/ccbell:load test                 # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event System Load Monitor ===

Status: Enabled
CPU Threshold: 80%
Memory Threshold: 90%
Load Threshold: 2.0
Poll Interval: 10s

Current System Load:

  CPU Usage: 72% (Normal)
  Memory: 14.2 GB / 16.0 GB (89%)
    - Used: 14.2 GB
    - Available: 1.8 GB
    - Percentage: 89%
  Swap: 2.1 GB / 4.0 GB (52%)
  Load Average: 1.85 (Normal)

  Processes: 342

Status: WARNING
  Memory approaching threshold (89%)

Sound Settings:
  High CPU: bundled:stop
  High Memory: bundled:stop
  Critical: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

System load monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Load Monitor

```go
type SystemLoadMonitor struct {
    config       *SystemLoadMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastStatus   *SystemLoadStatus
    notifiedHigh bool
}

func (m *SystemLoadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.notifiedHigh = false
    go m.monitor()
}

func (m *SystemLoadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLoad()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemLoadMonitor) checkLoad() {
    status := m.getSystemLoad()
    if status != nil {
        m.evaluateStatus(status)
    }
}

func (m *SystemLoadMonitor) getSystemLoad() *SystemLoadStatus {
    status := &SystemLoadStatus{}

    if runtime.GOOS == "darwin" {
        return m.getMacOSLoad(status)
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxLoad(status)
    }

    return status
}

func (m *SystemLoadMonitor) getMacOSLoad(status *SystemLoadStatus) *SystemLoadStatus {
    // macOS: top and sysctl
    cmd := exec.Command("top", "-l", "1", "-s", "0")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        // Parse CPU usage
        if strings.Contains(line, "CPU usage:") {
            cpuMatch := regexp.MustCompile(`(\d+\.\d+)%`).FindStringSubmatch(line)
            if cpuMatch != nil {
                cpu, _ := strconv.ParseFloat(cpuMatch[1], 64)
                status.CPUUsage = cpu
            }
        }

        // Parse memory
        if strings.Contains(line, "PhysMem:") {
            memParts := strings.Fields(line)
            for i, part := range memParts {
                if part == "used," && i > 0 {
                    status.MemoryUsed = m.parseMemory(memParts[i-1])
                }
            }
        }
    }

    // Get load average
    load, procs, err := getloadavg()
    if err == nil {
        status.LoadAverage = load
        status.Procs = procs
    }

    // Get total memory
    var total uint64
    if err := sysctl.Get("hw.memsize", &total); err == nil {
        status.MemoryTotal = total
        status.MemoryUsage = float64(status.MemoryUsed) / float64(total) * 100
    }

    return status
}

func (m *SystemLoadMonitor) getLinuxLoad(status *SystemLoadStatus) *SystemLoadStatus {
    // Linux: /proc/loadavg and /proc/meminfo
    loadData, _ := os.ReadFile("/proc/loadavg")
    memData, _ := os.ReadFile("/proc/meminfo")

    // Parse load average
    loadParts := strings.Fields(string(loadData))
    if len(loadParts) >= 3 {
        load, _ := strconv.ParseFloat(loadParts[0], 64)
        status.LoadAverage = load
        status.Procs, _ = strconv.Atoi(loadParts[3])
    }

    // Parse memory
    memLines := strings.Split(string(memData), "\n")
    var memTotal, memAvailable, swapTotal, swapFree uint64

    for _, line := range memLines {
        if strings.HasPrefix(line, "MemTotal:") {
            memTotal = m.parseMeminfoLine(line)
        } else if strings.HasPrefix(line, "MemAvailable:") {
            memAvailable = m.parseMeminfoLine(line)
        } else if strings.HasPrefix(line, "SwapTotal:") {
            swapTotal = m.parseMeminfoLine(line)
        } else if strings.HasPrefix(line, "SwapFree:") {
            swapFree = m.parseMeminfoLine(line)
        }
    }

    status.MemoryTotal = memTotal
    status.MemoryUsed = memTotal - memAvailable
    status.MemoryUsage = float64(status.MemoryUsed) / float64(memTotal) * 100

    if swapTotal > 0 {
        status.SwapUsage = float64(swapTotal-swapFree) / float64(swapTotal) * 100
    }

    // Get CPU usage from /proc/stat
    cpuData, _ := os.ReadFile("/proc/stat")
    status.CPUUsage = m.parseCPUUsage(string(cpuData))

    return status
}

func (m *SystemLoadMonitor) parseMeminfoLine(line string) uint64 {
    parts := strings.Fields(line)
    if len(parts) >= 2 {
        val, _ := strconv.ParseUint(parts[1], 10, 64)
        // Convert KB to bytes
        return val * 1024
    }
    return 0
}

func (m *SystemLoadMonitor) parseMemory(str string) uint64 {
    // Parse memory strings like "14.22G" or "4K"
    str = strings.TrimSpace(str)

    multiplier := uint64(1)
    switch strings.ToLower(str)[len(str)-1] {
    case 'k':
        multiplier = 1024
    case 'm':
        multiplier = 1024 * 1024
    case 'g':
        multiplier = 1024 * 1024 * 1024
    }

    numStr := str[:len(str)-1]
    val, _ := strconv.ParseFloat(numStr, 64)

    return uint64(val * float64(multiplier))
}

func (m *SystemLoadMonitor) parseCPUUsage(data string) float64 {
    // Parse /proc/stat for CPU usage
    // Format: cpu 123456 7890 123456 1234567 0 0 0 0 0 0
    lines := strings.Split(data, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "cpu ") {
            parts := strings.Fields(line)
            if len(parts) >= 5 {
                user, _ := strconv.ParseUint(parts[1], 10, 64)
                nice, _ := strconv.ParseUint(parts[2], 10, 64)
                system, _ := strconv.ParseUint(parts[3], 10, 64)
                idle, _ := strconv.ParseUint(parts[4], 10, 64)

                total := user + nice + system + idle
                if total > 0 {
                    return float64(user+nice+system) / float64(total) * 100
                }
            }
        }
    }
    return 0
}

func (m *SystemLoadMonitor) evaluateStatus(status *SystemLoadStatus) {
    if m.lastStatus == nil {
        m.lastStatus = status
        return
    }

    // Check high CPU
    if status.CPUUsage >= m.config.CPUThreshold {
        if m.lastStatus.CPUUsage < m.config.CPUThreshold {
            m.playSound("high_cpu")
            m.notifiedHigh = true
        }
    } else if status.CPUUsage < m.config.CPUThreshold-10 {
        m.notifiedHigh = false
    }

    // Check high memory
    if status.MemoryUsage >= m.config.MemoryThreshold {
        if m.lastStatus.MemoryUsage < m.config.MemoryThreshold {
            m.playSound("high_memory")
        }
    }

    // Check critical memory (very low available)
    if status.MemoryUsage >= m.config.MemoryThreshold-5 {
        if m.lastStatus.MemoryUsage < m.config.MemoryThreshold-5 {
            m.playSound("critical")
        }
    }

    // Check high swap
    if status.SwapUsage >= m.config.SwapThreshold {
        if m.lastStatus.SwapUsage < m.config.SwapThreshold {
            m.playSound("high_swap")
        }
    }

    // Check load average
    cpus := runtime.NumCPU()
    threshold := float64(cpus) * m.config.LoadThreshold

    if status.LoadAverage >= threshold {
        if m.lastStatus.LoadAverage < threshold {
            m.playSound("high_load")
        }
    }

    m.lastStatus = status
}

func (m *SystemLoadMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

// getloadavg is a wrapper for syscall getloadavg
func getloadavg() (float64, int, error) {
    var loadavg [3]float64
    err := syscall.Getloadavg(&loadavg, 3)
    if err != nil {
        return 0, 0, err
    }

    // Calculate average load
    avg := (loadavg[0] + loadavg[1] + loadavg[2]) / 3

    return avg, 0, nil
}

// sysctl wrapper for macOS
type sysctl struct{}

func (sysctl) Get(name string, data interface{}) error {
    return nil // Implementation would use syscall.syscall
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| top | System Tool | Free | macOS system stats |
| /proc/loadavg | File | Free | Linux load average |
| /proc/meminfo | File | Free | Linux memory info |
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
| macOS | Supported | Uses top command |
| Linux | Supported | Uses /proc filesystem |
| Windows | Not Supported | ccbell only supports macOS/Linux |
