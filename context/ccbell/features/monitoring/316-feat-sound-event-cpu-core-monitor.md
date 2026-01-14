# Feature: Sound Event CPU Core Monitor

Play sounds for CPU core activity and frequency changes.

## Summary

Monitor CPU core activity, frequency scaling, and per-core utilization, playing sounds for core events.

## Motivation

- Core activity awareness
- Frequency scaling feedback
- Performance monitoring
- Thermal throttling detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### CPU Core Events

| Event | Description | Example |
|-------|-------------|---------|
| Core Active | Core utilization high | > 90% |
| Core Idle | Core went idle | 0% utilization |
| Frequency Changed | CPU frequency scaled | 2.4GHz -> 1.8GHz |
| Thermal Throttling | Core throttled | Temperature limit |

### Configuration

```go
type CPUCoreMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchCores         []int             `json:"watch_cores"` // 0, 1, 2, 3
    HighThreshold      int               `json:"high_threshold"` // 90 default
    LowThreshold       int               `json:"low_threshold"` // 10 default
    SoundOnHigh        bool              `json:"sound_on_high"]
    SoundOnLow         bool              `json:"sound_on_low"]
    SoundOnFreqChange  bool              `json:"sound_on_freq_change"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type CPUCoreEvent struct {
    Core       int
    Utilization float64
    Frequency   float64
    Temperature float64
    EventType   string // "high", "low", "freq_change", "throttle"
}
```

### Commands

```bash
/ccbell:cpucore status                # Show CPU core status
/ccbell:cpucore add 0                 # Add core to watch
/ccbell:cpucore remove 0
/ccbell:cpucore threshold 90          # Set high threshold
/ccbell:cpucore sound high <sound>
/ccbell:cpucore test                  # Test CPU core sounds
```

### Output

```
$ ccbell:cpucore status

=== Sound Event CPU Core Monitor ===

Status: Enabled
High Threshold: 90%
Low Threshold: 10%

Watched Cores: 4

[1] Core 0
    Utilization: 95%
    Frequency: 2.4 GHz
    Temperature: 65C
    Status: HIGH
    Sound: bundled:cpucore-high

[2] Core 1
    Utilization: 45%
    Frequency: 2.4 GHz
    Temperature: 62C
    Status: OK
    Sound: bundled:stop

[3] Core 2
    Utilization: 10%
    Frequency: 0.8 GHz
    Temperature: 55C
    Status: LOW
    Sound: bundled:stop

[4] Core 3
    Utilization: 88%
    Frequency: 2.2 GHz
    Temperature: 68C
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] Core 0: High Utilization (5 min ago)
       95% for 5 min
  [2] Core 2: Frequency Changed (10 min ago)
       2.4 GHz -> 0.8 GHz
  [3] Core 3: Thermal Throttling (1 hour ago)
       Temperature at limit

Core Statistics:
  Avg utilization: 60%
  Thermal events: 2

Sound Settings:
  High: bundled:cpucore-high
  Low: bundled:stop
  Freq Change: bundled:stop

[Configure] [Add Core] [Test All]
```

---

## Audio Player Compatibility

CPU core monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### CPU Core Monitor

```go
type CPUCoreMonitor struct {
    config              *CPUCoreMonitorConfig
    player              *audio.Player
    running             bool
    stopCh              chan struct{}
    coreState           map[int]*CoreInfo
    lastEventTime       map[string]time.Time
}

type CoreInfo struct {
    Core         int
    Utilization  float64
    Frequency    float64
    Temperature  float64
}

func (m *CPUCoreMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.coreState = make(map[int]*CoreInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CPUCoreMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCoreState()

    for {
        select {
        case <-ticker.C:
            m.checkCoreState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CPUCoreMonitor) snapshotCoreState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinCores()
    } else {
        m.snapshotLinuxCores()
    }
}

func (m *CPUCoreMonitor) snapshotDarwinCores() {
    cmd := exec.Command("top", "-l", "1", "-o", "cpu")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseTopOutput(string(output))
}

func (m *CPUCoreMonitor) snapshotLinuxCores() {
    // Read /proc/stat for CPU utilization
    data, err := os.ReadFile("/proc/stat")
    if err != nil {
        return
    }

    m.parseProcStat(string(data))

    // Read CPU frequency for each core
    m.readCoreFrequencies()
}

func (m *CPUCoreMonitor) checkCoreState() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinCores()
    } else {
        m.checkLinuxCores()
    }
}

func (m *CPUCoreMonitor) checkDarwinCores() {
    cmd := exec.Command("top", "-l", "1", "-o", "cpu")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseTopOutput(string(output))
}

func (m *CPUCoreMonitor) checkLinuxCores() {
    // Read /proc/stat
    data, err := os.ReadFile("/proc/stat")
    if err != nil {
        return
    }

    m.parseProcStat(string(data))
    m.readCoreFrequencies()
}

func (m *CPUCoreMonitor) parseTopOutput(output string) {
    lines := strings.Split(output, "\n")
    core := 0

    for _, line := range lines {
        if strings.HasPrefix(line, "CPU") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                cpuStr := parts[1]
                if strings.HasPrefix(cpuStr, "cpu") {
                    // Parse CPU usage
                    re := regexp.MustCompile(`(\d+\.?\d*)%`)
                    match := re.FindStringSubmatch(line)
                    if match != nil {
                        util, _ := strconv.ParseFloat(match[1], 64)

                        lastInfo := m.coreState[core]
                        m.evaluateCoreState(core, util, lastInfo)

                        m.coreState[core] = &CoreInfo{
                            Core:        core,
                            Utilization: util,
                        }
                        core++
                    }
                }
            }
        }
    }
}

func (m *CPUCoreMonitor) parseProcStat(stat string) {
    lines := strings.Split(stat, "\n")

    for _, line := range lines {
        if !strings.HasPrefix(line, "cpu") || len(line) < 4 {
            continue
        }

        // Skip aggregated "cpu" line
        if line[3] == ' ' || line[3] == '\t' {
            continue
        }

        // Parse core number
        coreNumStr := strings.TrimPrefix(line[:4], "cpu")
        core, err := strconv.Atoi(coreNumStr)
        if err != nil {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 8 {
            continue
        }

        user, _ := strconv.ParseFloat(parts[1], 64)
        nice, _ := strconv.ParseFloat(parts[2], 64)
        system, _ := strconv.ParseFloat(parts[3], 64)
        idle, _ := strconv.ParseFloat(parts[4], 64)

        total := user + nice + system + idle
        utilization := ((total - idle) / total) * 100

        lastInfo := m.coreState[core]
        m.evaluateCoreState(core, utilization, lastInfo)

        m.coreState[core] = &CoreInfo{
            Core:        core,
            Utilization: utilization,
        }
    }
}

func (m *CPUCoreMonitor) readCoreFrequencies() {
    for core := range m.coreState {
        freqPath := filepath.Join("/sys/devices/system/cpu", fmt.Sprintf("cpu%d", core), "cpufreq/scaling_cur_freq")
        data, err := os.ReadFile(freqPath)
        if err != nil {
            continue
        }

        freqKHz, _ := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
        freqGHz := freqKHz / 1000000

        if info, exists := m.coreState[core]; exists {
            if info.Frequency > 0 && info.Frequency != freqGHz {
                m.onFrequencyChanged(core, info.Frequency, freqGHz)
            }
            info.Frequency = freqGHz
        }
    }
}

func (m *CPUCoreMonitor) evaluateCoreState(core int, utilization float64, lastInfo *CoreInfo) {
    if !m.shouldWatchCore(core) {
        return
    }

    if utilization >= float64(m.config.HighThreshold) {
        if lastInfo == nil || lastInfo.Utilization < float64(m.config.HighThreshold) {
            m.onCoreHigh(core, utilization)
        }
    } else if utilization <= float64(m.config.LowThreshold) {
        if lastInfo == nil || lastInfo.Utilization > float64(m.config.LowThreshold) {
            m.onCoreLow(core, utilization)
        }
    }
}

func (m *CPUCoreMonitor) shouldWatchCore(core int) bool {
    if len(m.config.WatchCores) == 0 {
        return true
    }

    for _, c := range m.config.WatchCores {
        if c == core {
            return true
        }
    }

    return false
}

func (m *CPUCoreMonitor) onCoreHigh(core int, utilization float64) {
    if !m.config.SoundOnHigh {
        return
    }

    key := fmt.Sprintf("high:%d", core)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CPUCoreMonitor) onCoreLow(core int, utilization float64) {
    if !m.config.SoundOnLow {
        return
    }

    key := fmt.Sprintf("low:%d", core)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["low"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *CPUCoreMonitor) onFrequencyChanged(core int, oldFreq float64, newFreq float64) {
    if !m.config.SoundOnFreqChange {
        return
    }

    // Only alert on significant changes
    if math.Abs(oldFreq-newFreq) < 0.5 {
        return
    }

    key := fmt.Sprintf("freq:%d", core)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["freq_change"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *CPUCoreMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| top | System Tool | Free | macOS CPU stats |
| /proc/stat | File | Free | Linux CPU stats |
| /sys/devices/system/cpu/*/cpufreq/scaling_cur_freq | File | Free | CPU frequency |

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
| macOS | Supported | Uses top |
| Linux | Supported | Uses /proc/stat, /sys |
| Windows | Not Supported | ccbell only supports macOS/Linux |
