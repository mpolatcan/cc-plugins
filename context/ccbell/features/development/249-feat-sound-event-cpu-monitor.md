# Feature: Sound Event CPU Monitor

Play sounds for CPU usage thresholds and high load events.

## Summary

Monitor CPU usage, load averages, and processor activity, playing sounds when CPU thresholds are exceeded.

## Motivation

- High load alerts
- Performance degradation
- Process CPU warnings
- Multi-core utilization

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### CPU Events

| Event | Description | Example |
|-------|-------------|---------|
| High Usage | CPU > 80% | 85% usage |
| Critical | CPU > 95% | 99% usage |
| High Load | Load > CPU count | Load average 8/4 |
| Sustained Load | High load 5min | Average elevated |

### Configuration

```go
type CPUMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    UsageWarningThreshold int            `json:"usage_warning_percent"` // 80 default
    UsageCriticalThreshold int          `json:"usage_critical_percent"` // 95 default
    LoadWarningThreshold float64        `json:"load_warning_multiplier"` // 1.0 (100% of CPU count)
    SoundOnHighUsage   bool              `json:"sound_on_high_usage"`
    SoundOnCritical    bool              `json:"sound_on_critical"`
    SoundOnHighLoad    bool              `json:"sound_on_high_load"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type CPUEvent struct {
    UsagePercent   float64
    Load1Min       float64
    Load5Min       float64
    Load15Min      float64
    CoreCount      int
    EventType      string // "high_usage", "critical", "high_load"
}
```

### Commands

```bash
/ccbell:cpu status               # Show CPU status
/ccbell:cpu warning 80           # Set usage warning threshold
/ccbell:cpu critical 95          # Set critical threshold
/ccbell:cpu sound high <sound>
/ccbell:cpu sound critical <sound>
/ccbell:cpu test                 # Test CPU sounds
```

### Output

```
$ ccbell:cpu status

=== Sound Event CPU Monitor ===

Status: Enabled
Usage Warning: 80%
Usage Critical: 95%
Load Warning: 1.0x CPU cores

Current CPU:
  Usage: 65%
  Load Average (1m): 4.2
  Cores: 8

  [==========........] 65%

Status: OK

Recent Events:
  [1] High Load (30 min ago)
       Load average: 6.8 (0.85x cores)
  [2] High Usage (1 hour ago)
       CPU at 82%
  [3] Critical (2 hours ago)
       CPU at 97%

Sound Settings:
  High Usage: bundled:stop
  Critical: bundled:stop
  High Load: bundled:stop

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

CPU monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### CPU Monitor

```go
type CPUMonitor struct {
    config            *CPUMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    lastWarningTime   time.Time
    lastCriticalTime  time.Time
    lastHighLoadTime  time.Time
}

func (m *CPUMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *CPUMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
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
    cpuInfo, err := m.getCPUInfo()
    if err != nil {
        return
    }

    // Check usage thresholds
    if cpuInfo.UsagePercent >= float64(m.config.UsageCriticalThreshold) {
        m.onCritical(cpuInfo)
    } else if cpuInfo.UsagePercent >= float64(m.config.UsageWarningThreshold) {
        m.onHighUsage(cpuInfo)
    }

    // Check load average
    coreCount := float64(cpuInfo.CoreCount)
    loadThreshold := coreCount * m.config.LoadWarningThreshold

    if cpuInfo.Load1Min >= loadThreshold {
        m.onHighLoad(cpuInfo, "1m")
    } else if cpuInfo.Load5Min >= loadThreshold {
        m.onHighLoad(cpuInfo, "5m")
    }
}

func (m *CPUMonitor) getCPUInfo() (*CPUInfo, error) {
    if runtime.GOOS == "darwin" {
        return m.getDarwinCPUInfo()
    }
    return m.getLinuxCPUInfo()
}

func (m *CPUMonitor) getDarwinCPUInfo() (*CPUInfo, error) {
    cpuInfo := &CPUInfo{}

    // Get CPU usage
    cmd := exec.Command("ps", "-axo", "pcpu=")
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    var totalUsage float64
    count := 0

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || line == "0.0" {
            continue
        }

        if usage, err := strconv.ParseFloat(line, 64); err == nil {
            totalUsage += usage
            count++
        }
    }

    if count > 0 {
        cpuInfo.UsagePercent = totalUsage
    }

    // Get load average
    cmd = exec.Command("sysctl", "-n", "vm.loadavg")
    loadOutput, err := cmd.Output()
    if err == nil {
        re := regexp.MustCompile(`\{\s*([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s*\}`)
        match := re.FindStringSubmatch(string(loadOutput))
        if len(match) >= 4 {
            cpuInfo.Load1Min, _ = strconv.ParseFloat(match[1], 64)
            cpuInfo.Load5Min, _ = strconv.ParseFloat(match[2], 64)
            cpuInfo.Load15Min, _ = strconv.ParseFloat(match[3], 64)
        }
    }

    // Get core count
    cmd = exec.Command("sysctl", "-n", "hw.ncpu")
    coreOutput, err := cmd.Output()
    if err == nil {
        if cores, err := strconv.Atoi(strings.TrimSpace(string(coreOutput))); err == nil {
            cpuInfo.CoreCount = cores
        }
    }

    return cpuInfo, nil
}

func (m *CPUMonitor) getLinuxCPUInfo() (*CPUInfo, error) {
    // Read /proc/stat for CPU usage
    data, err := os.ReadFile("/proc/stat")
    if err != nil {
        return nil, err
    }

    cpuInfo := &CPUInfo{}

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if !strings.HasPrefix(line, "cpu ") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 8 {
            continue
        }

        user, _ := strconv.ParseInt(parts[1], 10, 64)
        nice, _ := strconv.ParseInt(parts[2], 10, 64)
        system, _ := strconv.ParseInt(parts[3], 10, 64)
        idle, _ := strconv.ParseInt(parts[4], 10, 64)
        iowait, _ := strconv.ParseInt(parts[5], 10, 64)
        irq, _ := strconv.ParseInt(parts[6], 10, 64)
        softirq, _ := strconv.ParseInt(parts[7], 10, 64)

        total := user + nice + system + idle + iowait + irq + softirq
        active := total - idle - iowait

        cpuInfo.UsagePercent = float64(active) / float64(total) * 100
        break
    }

    // Read load average
    loadData, err := os.ReadFile("/proc/loadavg")
    if err == nil {
        parts := strings.Fields(string(loadData))
        if len(parts) >= 3 {
            cpuInfo.Load1Min, _ = strconv.ParseFloat(parts[0], 64)
            cpuInfo.Load5Min, _ = strconv.ParseFloat(parts[1], 64)
            cpuInfo.Load15Min, _ = strconv.ParseFloat(parts[2], 64)
        }
    }

    // Get core count
    cpuData, err := os.ReadFile("/proc/cpuinfo")
    if err == nil {
        count := strings.Count(string(cpuData), "processor")
        if count > 0 {
            cpuInfo.CoreCount = count
        }
    }

    return cpuInfo, nil
}

func (m *CPUMonitor) onHighUsage(cpuInfo *CPUInfo) {
    if !m.config.SoundOnHighUsage {
        return
    }

    if time.Since(m.lastWarningTime) < 5*time.Minute {
        return
    }

    m.lastWarningTime = time.Now()

    sound := m.config.Sounds["high_usage"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CPUMonitor) onCritical(cpuInfo *CPUInfo) {
    if !m.config.SoundOnCritical {
        return
    }

    if time.Since(m.lastCriticalTime) < 2*time.Minute {
        return
    }

    m.lastCriticalTime = time.Now()

    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}

func (m *CPUMonitor) onHighLoad(cpuInfo *CPUInfo, period string) {
    if !m.config.SoundOnHighLoad {
        return
    }

    if time.Since(m.lastHighLoadTime) < 5*time.Minute {
        return
    }

    m.lastHighLoadTime = time.Now()

    sound := m.config.Sounds["high_load"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /proc/stat | File | Free | Linux CPU statistics |
| /proc/loadavg | File | Free | Linux load average |
| /proc/cpuinfo | File | Free | Linux CPU info |
| ps | System Tool | Free | macOS process info |
| sysctl | System Tool | Free | macOS system info |

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
| macOS | Supported | Uses ps and sysctl |
| Linux | Supported | Uses /proc filesystem |
| Windows | Not Supported | ccbell only supports macOS/Linux |
