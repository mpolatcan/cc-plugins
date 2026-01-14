# Feature: Sound Event System Load Monitor

Play sounds for CPU load thresholds, memory pressure, and system resource alerts.

## Summary

Monitor system load averages, memory usage, and CPU utilization, playing sounds for resource threshold events.

## Motivation

- Performance awareness
- Resource exhaustion prevention
- Load spike detection
- Memory pressure alerts
- System health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### System Load Events

| Event | Description | Example |
|-------|-------------|---------|
| High CPU Load | Load > threshold | load > 8 |
| Memory Pressure | Memory > 90% | OOM risk |
| Low Memory | Available < 100MB | Critical |
| Swap Usage | Swap > threshold | swap > 80% |
| IO Wait | IO wait high | disk bottleneck |
| Load Spike | Load doubled | sudden increase |

### Configuration

```go
type SystemLoadMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    CPUThreshold      float64           `json:"cpu_threshold"` // 80.0 default
    MemoryThreshold   float64           `json:"memory_threshold"` // 90.0 default
    LoadThreshold     float64           `json:"load_threshold"` // 8.0 default
    SwapThreshold     float64           `json:"swap_threshold"` // 80.0 default
    SoundOnHighCPU    bool              `json:"sound_on_high_cpu"`
    SoundOnMemory     bool              `json:"sound_on_memory"`
    SoundOnLoad       bool              `json:"sound_on_load"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:load status                    # Show system load
/ccbell:load cpu 80                    # Set CPU threshold
/ccbell:load memory 90                 # Set memory threshold
/ccbell:load sound high <sound>
/ccbell:load test                      # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event System Load Monitor ===

Status: Enabled
CPU Threshold: 80%
Memory Threshold: 90%
Load Threshold: 8.0

Current Statistics:
  CPU Usage: 45%
  Load Average (1m): 2.5
  Load Average (5m): 3.2
  Load Average (15m): 4.1
  Memory Used: 12.5 GB / 32 GB (39%)
  Swap Used: 2.1 GB / 16 GB (13%)
  IO Wait: 2%

System Health: OK

Recent Events:
  [1] High CPU Load (1 hour ago)
       CPU: 85% > 80% threshold
  [2] Memory Pressure (2 hours ago)
       Memory: 92% used
  [3] Load Spike (1 day ago)
       Load: 8.5 > threshold (4.0)

Load Statistics:
  High CPU Alerts: 5
  Memory Alerts: 3
  Load Alerts: 2

Sound Settings:
  High CPU: bundled:load-cpu
  Memory: bundled:load-memory
  Load: bundled:load-high

[Configure] [Test All]
```

---

## Audio Player Compatibility

Load monitoring doesn't play sounds directly:
- Monitoring feature using uptime/top/free/vmstat
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Load Monitor

```go
type SystemLoadMonitor struct {
    config          *SystemLoadMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    lastLoad        float64
    lastMemory      float64
    lastCPU         float64
    lastEventTime   map[string]time.Time
}

func (m *SystemLoadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemLoadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSystemLoad()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemLoadMonitor) checkSystemLoad() {
    // Get load average
    load1, load5, load15 := m.getLoadAverage()
    currentLoad := load1

    // Get CPU usage
    cpuUsage := m.getCPUUsage()

    // Get memory usage
    memoryUsage := m.getMemoryUsage()

    // Get swap usage
    swapUsage := m.getSwapUsage()

    // Check thresholds
    m.checkLoadThreshold(currentLoad)
    m.checkCPUThreshold(cpuUsage)
    m.checkMemoryThreshold(memoryUsage)
    m.checkSwapThreshold(swapUsage)

    m.lastLoad = currentLoad
    m.lastCPU = cpuUsage
    m.lastMemory = memoryUsage
}

func (m *SystemLoadMonitor) getLoadAverage() (float64, float64, float64) {
    cmd := exec.Command("uptime")
    output, err := cmd.Output()
    if err != nil {
        return 0, 0, 0
    }

    re := regexp.MustCompile(`load average: ([\d.]+), ([\d.]+), ([\d.]+)`)
    match := re.FindStringSubmatch(string(output))
    if match != nil {
        load1, _ := strconv.ParseFloat(match[1], 64)
        load5, _ := strconv.ParseFloat(match[2], 64)
        load15, _ := strconv.ParseFloat(match[3], 64)
        return load1, load5, load15
    }

    return 0, 0, 0
}

func (m *SystemLoadMonitor) getCPUUsage() float64 {
    // Use top or mpstat for CPU usage
    cmd := exec.Command("top", "-b", "-n", "1")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "CPU:") {
            re := regexp.MustCompile(`CPU:\s*(\d+)%`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                cpu, _ := strconv.ParseFloat(match[1], 64)
                return cpu
            }
        }
    }

    return 0
}

func (m *SystemLoadMonitor) getMemoryUsage() float64 {
    cmd := exec.Command("free", "-m")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Mem:") {
            parts := strings.Fields(line)
            if len(parts) >= 7 {
                total, _ := strconv.ParseFloat(parts[1], 64)
                used, _ := strconv.ParseFloat(parts[2], 64)
                if total > 0 {
                    return (used / total) * 100
                }
            }
        }
    }

    return 0
}

func (m *SystemLoadMonitor) getSwapUsage() float64 {
    cmd := exec.Command("free", "-m")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Swap:") {
            parts := strings.Fields(line)
            if len(parts) >= 7 {
                total, _ := strconv.ParseFloat(parts[1], 64)
                used, _ := strconv.ParseFloat(parts[2], 64)
                if total > 0 {
                    return (used / total) * 100
                }
            }
        }
    }

    return 0
}

func (m *SystemLoadMonitor) checkLoadThreshold(load float64) {
    if load >= m.config.LoadThreshold && (m.lastLoad < m.config.LoadThreshold || m.lastLoad == 0) {
        if m.config.SoundOnLoad {
            key := "load:high"
            if m.shouldAlert(key, 10*time.Minute) {
                sound := m.config.Sounds["load"]
                if sound != "" {
                    m.player.Play(sound, 0.5)
                }
            }
        }
    }
}

func (m *SystemLoadMonitor) checkCPUThreshold(cpu float64) {
    if cpu >= m.config.CPUThreshold && (m.lastCPU < m.config.CPUThreshold || m.lastCPU == 0) {
        if m.config.SoundOnHighCPU {
            key := "cpu:high"
            if m.shouldAlert(key, 5*time.Minute) {
                sound := m.config.Sounds["high_cpu"]
                if sound != "" {
                    m.player.Play(sound, 0.5)
                }
            }
        }
    }
}

func (m *SystemLoadMonitor) checkMemoryThreshold(memory float64) {
    if memory >= m.config.MemoryThreshold && (m.lastMemory < m.config.MemoryThreshold || m.lastMemory == 0) {
        if m.config.SoundOnMemory {
            key := "memory:high"
            if m.shouldAlert(key, 10*time.Minute) {
                sound := m.config.Sounds["memory"]
                if sound != "" {
                    m.player.Play(sound, 0.6)
                }
            }
        }
    }
}

func (m *SystemLoadMonitor) checkSwapThreshold(swap float64) {
    if swap >= m.config.SwapThreshold {
        key := "swap:high"
        if m.shouldAlert(key, 15*time.Minute) {
            sound := m.config.Sounds["swap"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    }
}

func (m *SystemLoadMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| uptime | System Tool | Free | Load average |
| top | System Tool | Free | CPU usage |
| free | System Tool | Free | Memory/swap |
| mpstat | System Tool | Free | CPU stats (sysstat) |

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
| macOS | Supported | Uses top, uptime, vm_stat |
| Linux | Supported | Uses top, free, uptime |
