# Feature: Sound Event Load Average Monitor

Play sounds for system load average thresholds and CPU saturation alerts.

## Summary

Monitor system load average (1, 5, 15 minute averages) for capacity thresholds and performance degradation, playing sounds for load events.

## Motivation

- Load awareness
- Performance monitoring
- Capacity planning
- CPU saturation alerts
- System responsiveness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Load Average Events

| Event | Description | Example |
|-------|-------------|---------|
| High Load | Load > CPU count | load 8/4 |
| Critical Load | Load > 2x CPU | load 12/4 |
| Load Normalized | Load normalized | back to normal |
| Load Spike | Sudden increase | load doubled |
| Sustained High | High for 5 min | sustained |
| Per-Core High | Per-core load | > 1.0 per core |

### Configuration

```go
type LoadAverageMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WarningLoad       float64           `json:"warning_load"` // CPU count default
    CriticalLoad      float64           `json:"critical_load"` // 2 * CPU count default
    CheckInterval     int               `json:"check_interval_sec"` // 60 default
    SustainedCount    int               `json:"sustained_count"` // 5 samples
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnNormal     bool              `json:"sound_on_normal"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:load status                 # Show load status
/ccbell:load warning 4.0            # Set warning threshold
/ccbell:load sound warning <sound>
/ccbell:load test                   # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event Load Average Monitor ===

Status: Enabled
Warning: 4.0 (1x CPU)
Critical: 8.0 (2x CPU)

Load Status:

[1] System Load
    Status: WARNING *** WARNING ***
    1-min: 5.2 *** HIGH ***
    5-min: 4.8
    15-min: 3.5
    CPUs: 4
    Load per CPU: 1.3
    Sound: bundled:load-warning

Recent Events:

[1] System: High Load (5 min ago)
       1-min load 5.2 > 4.0 threshold
       Sound: bundled:load-warning
  [2] System: Back to Normal (1 hour ago)
       Load normalized to 2.5
       Sound: bundled:load-normal
  [3] System: Load Spike (2 hours ago)
       1-min load doubled from 2.0 to 4.0
       Sound: bundled:load-spike

Load Statistics:
  Current: 5.2
  5-min Avg: 4.8
  15-min Avg: 3.5
  CPUs: 4

Sound Settings:
  Warning: bundled:load-warning
  Critical: bundled:load-critical
  Normal: bundled:load-normal
  Spike: bundled:load-spike

[Configure] [Test All]
```

---

## Audio Player Compatibility

Load monitoring doesn't play sounds directly:
- Monitoring feature using uptime, sysctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Load Average Monitor

```go
type LoadAverageMonitor struct {
    config        *LoadAverageMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    loadState     *LoadInfo
    lastEventTime map[string]time.Time
    highLoadCount int
}

type LoadInfo struct {
    Load1Min   float64
    Load5Min   float64
    Load15Min  float64
    CPUCount   int
    Status     string // "normal", "warning", "critical"
}

func (m *LoadAverageMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.loadState = nil
    m.lastEventTime = make(map[string]time.Time)
    m.highLoadCount = 0
    go m.monitor()
}

func (m *LoadAverageMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotLoadState()

    for {
        select {
        case <-ticker.C:
            m.checkLoadState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LoadAverageMonitor) snapshotLoadState() {
    m.checkLoadState()
}

func (m *LoadAverageMonitor) checkLoadState() {
    info := m.getLoadInfo()
    if info != nil {
        m.processLoadStatus(info)
    }
}

func (m *LoadAverageMonitor) getLoadInfo() *LoadInfo {
    info := &LoadInfo{}

    // Get load average
    cmd := exec.Command("uptime")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    outputStr := string(output)

    // Parse load average from uptime output
    // Format: " 10:30  up 1:23, 4 users, load averages: 1.23 2.45 3.67"
    loadRe := regexp.MustEach(`load averages?:\s*([\d.]+)\s*([\d.]+)\s*([\d.]+)`)
    matches := loadRe.FindStringSubmatch(outputStr)

    if len(matches) >= 4 {
        info.Load1Min, _ = strconv.ParseFloat(matches[1], 64)
        info.Load5Min, _ = strconv.ParseFloat(matches[2], 64)
        info.Load15Min, _ = strconv.ParseFloat(matches[3], 64)
    }

    // Get CPU count
    info.CPUCount = m.getCPUCount()

    // Calculate thresholds if not set
    if m.config.WarningLoad == 0 {
        m.config.WarningLoad = float64(info.CPUCount)
    }
    if m.config.CriticalLoad == 0 {
        m.config.CriticalLoad = float64(info.CPUCount) * 2
    }

    // Determine status based on 1-minute load
    info.Status = m.calculateStatus(info.Load1Min)

    return info
}

func (m *LoadAverageMonitor) getCPUCount() int {
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("sysctl", "-n", "hw.ncpu")
        output, _ := cmd.Output()
        count, _ := strconv.Atoi(strings.TrimSpace(string(output)))
        return count
    }

    // Linux: read /proc/cpuinfo
    data, err := os.ReadFile("/proc/cpuinfo")
    if err != nil {
        return 1
    }
    return strings.Count(string(data), "processor")
}

func (m *LoadAverageMonitor) calculateStatus(load float64) string {
    if load >= m.config.CriticalLoad {
        return "critical"
    }
    if load >= m.config.WarningLoad {
        return "warning"
    }
    return "normal"
}

func (m *LoadAverageMonitor) processLoadStatus(info *LoadInfo) {
    if m.loadState == nil {
        m.loadState = info

        if info.Status == "critical" && m.config.SoundOnCritical {
            m.onLoadCritical(info)
        } else if info.Status == "warning" && m.config.SoundOnWarning {
            m.onLoadWarning(info)
        }
        return
    }

    lastInfo := m.loadState

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "critical":
            if m.config.SoundOnCritical && m.shouldAlert("critical", 10*time.Minute) {
                m.onLoadCritical(info)
            }
        case "warning":
            if lastInfo.Status == "normal" && m.config.SoundOnWarning {
                if m.shouldAlert("warning", 30*time.Minute) {
                    m.onLoadWarning(info)
                }
            }
        case "normal":
            if lastInfo.Status != "normal" && m.config.SoundOnNormal {
                m.onLoadNormal(info)
            }
        }
    }

    // Check for load spike (doubled in short time)
    if info.Load1Min >= lastInfo.Load1Min*2 && lastInfo.Load1Min > 1.0 {
        if m.shouldAlert("spike", 5*time.Minute) {
            m.onLoadSpike(info, lastInfo.Load1Min)
        }
    }

    // Check for sustained high load
    if info.Status == "warning" || info.Status == "critical" {
        m.highLoadCount++
        if m.highLoadCount >= m.config.SustainedCount && m.shouldAlert("sustained", 10*time.Minute) {
            m.onSustainedHighLoad(info)
        }
    } else {
        m.highLoadCount = 0
    }

    m.loadState = info
}

func (m *LoadAverageMonitor) onLoadWarning(info *LoadInfo) {
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *LoadAverageMonitor) onLoadCritical(info *LoadInfo) {
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *LoadAverageMonitor) onLoadNormal(info *LoadInfo) {
    sound := m.config.Sounds["normal"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *LoadAverageMonitor) onLoadSpike(info *LoadInfo, oldLoad float64) {
    sound := m.config.Sounds["spike"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *LoadAverageMonitor) onSustainedHighLoad(info *LoadInfo) {
    sound := m.config.Sounds["sustained"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *LoadAverageMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| uptime | System Tool | Free | System uptime and load |
| sysctl | System Tool | Free | CPU count (macOS) |

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
| macOS | Supported | Uses uptime, sysctl |
| Linux | Supported | Uses uptime, /proc/cpuinfo |
