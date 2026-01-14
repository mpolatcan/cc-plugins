# Feature: Sound Event Load Average Monitor

Play sounds for system load average thresholds.

## Summary

Monitor system load averages (1m, 5m, 15m) and play sounds when load exceeds thresholds.

## Motivation

- High load alerts
- Performance degradation warnings
- System responsiveness feedback
- Load spike detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Load Average Events

| Event | Description | Example |
|-------|-------------|---------|
| High Load | Load > CPU count | 8/4 cores |
| Critical Load | Load > 2x CPU | 16/4 cores |
| Load Spike | Sudden increase | 2.0 -> 8.0 |
| Load Normalized | Load decreased | Back to normal |

### Configuration

```go
type LoadAverageMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WarningMultiplier   float64           `json:"warning_multiplier"` // 1.0 (100% of CPU count)
    CriticalMultiplier  float64           `json:"critical_multiplier"` // 2.0
    SoundOnWarning      bool              `json:"sound_on_warning"]
    SoundOnCritical     bool              `json:"sound_on_critical"]
    SoundOnSpike        bool              `json:"sound_on_spike"]
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 10 default
}

type LoadAverageEvent struct {
    Load1Min     float64
    Load5Min     float64
    Load15Min    float64
    CPUCount     int
    EventType    string // "warning", "critical", "spike", "normal"
}
```

### Commands

```bash
/ccbell:load status                  # Show load status
/ccbell:load warning 1.0             # Set warning multiplier
/ccbell:load critical 2.0            # Set critical multiplier
/ccbell:load sound warning <sound>
/ccbell:load sound critical <sound>
/ccbell:load test                    # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event Load Average Monitor ===

Status: Enabled
Warning: 1.0x CPU cores
Critical: 2.0x CPU cores

Current Load:
  1 min: 6.5
  5 min: 4.2
  15 min: 3.1
  CPU Cores: 8

  [========.........] 81%

Status: WARNING

Recent Events:
  [1] High Load (5 min ago)
       1 min: 7.2 (0.9x cores)
  [2] Load Spike (10 min ago)
       1 min: 8.5 (1.0x cores)
  [3] Normalized (1 hour ago)
       Load dropped below threshold

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Spike: bundled:stop

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Load average monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Load Average Monitor

```go
type LoadAverageMonitor struct {
    config             *LoadAverageMonitorConfig
    player             *audio.Player
    running            bool
    stopCh             chan struct{}
    lastLoad1Min       float64
    lastWarningTime    time.Time
    lastCriticalTime   time.Time
}

func (m *LoadAverageMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *LoadAverageMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLoadAverage()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LoadAverageMonitor) checkLoadAverage() {
    loadAvg, err := m.getLoadAverage()
    if err != nil {
        return
    }

    cpuCount, _ := m.getCPUCount()

    warningThreshold := float64(cpuCount) * m.config.WarningMultiplier
    criticalThreshold := float64(cpuCount) * m.config.CriticalMultiplier

    // Check for load spike (sudden increase)
    if loadAvg.Load1Min > m.lastLoad1Min*1.5 && m.lastLoad1Min > warningThreshold {
        m.onLoadSpike(loadAvg)
    }
    m.lastLoad1Min = loadAvg.Load1Min

    if loadAvg.Load1Min >= criticalThreshold {
        m.onCriticalLoad(loadAvg)
    } else if loadAvg.Load1Min >= warningThreshold {
        m.onHighLoad(loadAvg)
    }
}

func (m *LoadAverageMonitor) getLoadAverage() (*LoadAverageEvent, error) {
    event := &LoadAverageEvent{}

    if runtime.GOOS == "darwin" {
        cmd := exec.Command("sysctl", "-n", "vm.loadavg")
        output, err := cmd.Output()
        if err != nil {
            return nil, err
        }

        re := regexp.MustCompile(`\{\s*([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s*\}`)
        match := re.FindStringSubmatch(string(output))
        if len(match) >= 4 {
            event.Load1Min, _ = strconv.ParseFloat(match[1], 64)
            event.Load5Min, _ = strconv.ParseFloat(match[2], 64)
            event.Load15Min, _ = strconv.ParseFloat(match[3], 64)
        }
    } else {
        data, err := os.ReadFile("/proc/loadavg")
        if err != nil {
            return nil, err
        }

        parts := strings.Fields(string(data))
        if len(parts) >= 3 {
            event.Load1Min, _ = strconv.ParseFloat(parts[0], 64)
            event.Load5Min, _ = strconv.ParseFloat(parts[1], 64)
            event.Load15Min, _ = strconv.ParseFloat(parts[2], 64)
        }
    }

    return event, nil
}

func (m *LoadAverageMonitor) getCPUCount() (int, error) {
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("sysctl", "-n", "hw.ncpu")
        output, err := cmd.Output()
        if err != nil {
            return 1, err
        }
        return strconv.Atoi(strings.TrimSpace(string(output)))
    }

    data, err := os.ReadFile("/proc/cpuinfo")
    if err != nil {
        return 1, err
    }
    count := strings.Count(string(data), "processor")
    if count == 0 {
        return 1, nil
    }
    return count, nil
}

func (m *LoadAverageMonitor) onHighLoad(event *LoadAverageEvent) {
    if !m.config.SoundOnWarning {
        return
    }

    if time.Since(m.lastWarningTime) < 5*time.Minute {
        return
    }

    m.lastWarningTime = time.Now()

    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *LoadAverageMonitor) onCriticalLoad(event *LoadAverageEvent) {
    if !m.config.SoundOnCritical {
        return
    }

    if time.Since(m.lastCriticalTime) < 2*time.Minute {
        return
    }

    m.lastCriticalTime = time.Now()

    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *LoadAverageMonitor) onLoadSpike(event *LoadAverageEvent) {
    if !m.config.SoundOnSpike {
        return
    }

    sound := m.config.Sounds["spike"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| sysctl | System Tool | Free | macOS system info |
| /proc/loadavg | File | Free | Linux load average |
| /proc/cpuinfo | File | Free | Linux CPU count |

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
| macOS | Supported | Uses sysctl |
| Linux | Supported | Uses /proc/loadavg |
| Windows | Not Supported | ccbell only supports macOS/Linux |
