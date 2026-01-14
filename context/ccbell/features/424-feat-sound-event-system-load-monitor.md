# Feature: Sound Event System Load Monitor

Play sounds for high CPU load, load spikes, and system overload conditions.

## Summary

Monitor system load averages for high utilization, load spikes, and sustained high load conditions, playing sounds for load events.

## Motivation

- Performance awareness
- Load spike alerts
- Resource exhaustion prevention
- Performance degradation detection
- System health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### System Load Events

| Event | Description | Example |
|-------|-------------|---------|
| Load High | Load > threshold | > CPU count |
| Load Critical | Very high load | > 2x CPU |
| Load Spike | Sudden increase | > 50% jump |
| Load Normal | Back to normal | < threshold |
| High I/O Wait | I/O bottleneck | > 20% |
| Process Queue | Run queue long | > 10 |

### Configuration

```go
type SystemLoadMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WarningLoad       float64           `json:"warning_load"` // CPU count default
    CriticalLoad      float64           `json:"critical_load"` // 2x CPU count
    LoadWindow        int               `json:"load_window_minutes"` // 5 default
    SoundOnHigh       bool              `json:"sound_on_high"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnSpike      bool              `json:"sound_on_spike"`
    SoundOnNormal     bool              `json:"sound_on_normal"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:load status                  # Show load status
/ccbell:load warning 4.0             # Set warning threshold
/ccbell:load critical 8.0            # Set critical threshold
/ccbell:load sound high <sound>
/ccbell:load sound critical <sound>
/ccbell:load test                    # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event System Load Monitor ===

Status: Enabled
Warning Threshold: 4.0 (1.0 per core)
Critical Threshold: 8.0 (2.0 per core)

Current Load:

  1min:    5.2 *** WARNING ***
  5min:    4.1
  15min:   3.5
  CPUs:    4
  Load:    1.3 per CPU

Top Processes:

  1. chrome (CPU: 45%, MEM: 2.1 GB)
  2. code (CPU: 30%, MEM: 1.2 GB)
  3. dockerd (CPU: 25%, MEM: 800 MB)
  4. postgres (CPU: 15%, MEM: 4.5 GB)
  5. slack (CPU: 10%, MEM: 350 MB)

Load History:

  08:00: 2.5 (Normal)
  09:00: 3.8 (Normal)
  10:00: 5.2 (Warning) *** SOUND ***
  10:15: 4.8 (Warning)
  10:30: 3.2 (Normal)

Recent Load Events:
  [1] Load High (30 min ago)
       1min load: 5.2 (threshold: 4.0)
  [2] Load Spike (2 hours ago)
       1min load jumped 50%
  [3] Load Normal (3 hours ago)
       Load dropped below threshold

Load Statistics:
  High Alerts Today: 3
  Critical Alerts: 0
  Avg 1min Load: 3.5
  Peak Load: 6.2

Sound Settings:
  High: bundled:load-high
  Critical: bundled:load-critical
  Spike: bundled:load-spike
  Normal: bundled:load-normal

[Configure] [Test All]
```

---

## Audio Player Compatibility

Load monitoring doesn't play sounds directly:
- Monitoring feature using uptime
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
    loadHistory     []LoadSample
    lastEventTime   map[string]time.Time
    lastStatus      string
    cpuCount        int
}

type LoadSample struct {
    Time     time.Time
    Load1    float64
    Load5    float64
    Load15   float64
}

func (m *SystemLoadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.loadHistory = make([]LoadSample, 0)
    m.lastEventTime = make(map[string]time.Time)
    m.lastStatus = "unknown"
    m.cpuCount = m.getCPUCount()

    // Set defaults based on CPU count
    if m.config.WarningLoad == 0 {
        m.config.WarningLoad = float64(m.cpuCount)
    }
    if m.config.CriticalLoad == 0 {
        m.config.CriticalLoad = float64(m.cpuCount) * 2
    }

    go m.monitor()
}

func (m *SystemLoadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLoadStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemLoadMonitor) checkLoadStatus() {
    sample := m.getLoadSample()
    if sample == nil {
        return
    }

    m.loadHistory = append(m.loadHistory, *sample)
    if len(m.loadHistory) > 100 {
        m.loadHistory = m.loadHistory[1:]
    }

    status := m.calculateStatus(sample)

    if status != m.lastStatus {
        m.onStatusChanged(status, sample)
        m.lastStatus = status
    }
}

func (m *SystemLoadMonitor) getLoadSample() *LoadSample {
    cmd := exec.Command("uptime")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    // Parse uptime output
    // Format:  10:30  up  2:30, 3 users, load averages: 1.23 1.45 1.67
    outputStr := string(output)

    re := regexp.MustEach(`load averages?:?\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)`)
    matches := re.FindStringSubmatch(outputStr)

    if len(matches) < 4 {
        return nil
    }

    load1, _ := strconv.ParseFloat(matches[1], 64)
    load5, _ := strconv.ParseFloat(matches[2], 64)
    load15, _ := strconv.ParseFloat(matches[3], 64)

    return &LoadSample{
        Time:  time.Now(),
        Load1: load1,
        Load5: load5,
        Load15: load15,
    }
}

func (m *SystemLoadMonitor) getCPUCount() int {
    cmd := exec.Command("sysctl", "-n", "hw.ncpu")
    if runtime.GOOS == "darwin" {
        output, err := cmd.Output()
        if err == nil {
            if n, err := strconv.Atoi(strings.TrimSpace(string(output))); err == nil {
                return n
            }
        }
    }

    // Linux
    cmd = exec.Command("nproc")
    output, err := cmd.Output()
    if err == nil {
        if n, err := strconv.Atoi(strings.TrimSpace(string(output))); err == nil {
            return n
        }
    }

    return 4 // Default
}

func (m *SystemLoadMonitor) calculateStatus(sample *LoadSample) string {
    // Check 1min load
    if sample.Load1 >= m.config.CriticalLoad {
        return "critical"
    }
    if sample.Load1 >= m.config.WarningLoad {
        return "high"
    }
    return "normal"
}

func (m *SystemLoadMonitor) checkForSpike(sample *LoadSample) bool {
    if len(m.loadHistory) < 2 {
        return false
    }

    lastSample := m.loadHistory[len(m.loadHistory)-2]
    loadDiff := sample.Load1 - lastSample.Load1

    // Check if load increased by more than 50%
    if lastSample.Load1 > 0 {
        percentIncrease := loadDiff / lastSample.Load1 * 100
        if percentIncrease > 50 {
            return true
        }
    }

    return false
}

func (m *SystemLoadMonitor) onStatusChanged(status string, sample *LoadSample) {
    switch status {
    case "critical":
        if m.config.SoundOnCritical {
            m.onLoadCritical(sample)
        }
    case "high":
        if m.config.SoundOnHigh {
            // Check for spike
            if m.checkForSpike(sample) && m.config.SoundOnSpike {
                m.onLoadSpike(sample)
            } else {
                m.onLoadHigh(sample)
            }
        }
    case "normal":
        if m.lastStatus == "high" || m.lastStatus == "critical" {
            if m.config.SoundOnNormal {
                m.onLoadNormal(sample)
            }
        }
    }
}

func (m *SystemLoadMonitor) onLoadHigh(sample *LoadSample) {
    key := "load:high"
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemLoadMonitor) onLoadCritical(sample *LoadSample) {
    key := "load:critical"
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemLoadMonitor) onLoadSpike(sample *LoadSample) {
    key := "load:spike"
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["spike"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemLoadMonitor) onLoadNormal(sample *LoadSample) {
    key := "load:normal"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["normal"]
        if sound != "" {
            m.player.Play(sound, 0.3)
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
| uptime | System Tool | Free | System load average |
| nproc | System Tool | Free | CPU count (Linux) |
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
| Linux | Supported | Uses uptime, nproc |
