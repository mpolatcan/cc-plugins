# Feature: Sound Event CPU Frequency Monitor

Play sounds for CPU frequency changes and scaling events.

## Summary

Monitor CPU frequency scaling, governor changes, and performance state transitions, playing sounds for CPU frequency events.

## Motivation

- Performance awareness
- Power saving detection
- Thermal throttling alerts
- Frequency boost detection
- CPU optimization feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### CPU Frequency Events

| Event | Description | Example |
|-------|-------------|---------|
| Frequency Changed | CPU frequency changed | 2.4GHz -> 3.0GHz |
| Governor Changed | Scaling governor changed | powersave -> performance |
| Thermal Throttle | Thermal throttling active | CPU throttled |
| Turbo Boost | Turbo boost engaged | 4.5GHz boost |
| Min Frequency | Min frequency reached | CPU at lowest state |
| Max Frequency | Max frequency reached | CPU at highest state |

### Configuration

```go
type CPUFreqMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    SoundOnFrequency   bool              `json:"sound_on_frequency"`
    SoundOnGovernor    bool              `json:"sound_on_governor"`
    SoundOnThrottle    bool              `json:"sound_on_throttle"`
    SoundOnTurbo       bool              `json:"sound_on_turbo"`
    FrequencyThreshold int               `json:"frequency_threshold_mhz"` // 0 = all
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type CPUFreqEvent struct {
    CPU         int
    OldFreq     int64 // MHz
    NewFreq     int64 // MHz
    OldGovernor string
    NewGovernor string
    Throttled   bool
    Turbo       bool
    EventType   string // "frequency", "governor", "throttle", "turbo"
}
```

### Commands

```bash
/ccbell:cpufreq status                # Show CPU frequency status
/ccbell:cpufreq threshold 2000        # Set frequency change threshold
/ccbell:cpufreq sound frequency <sound>
/ccbell:cpufreq sound throttle <sound>
/ccbell:cpufreq test                  # Test CPU frequency sounds
```

### Output

```
$ ccbell:cpufreq status

=== Sound Event CPU Frequency Monitor ===

Status: Enabled
Frequency Sounds: Yes
Throttle Sounds: Yes
Governor Sounds: Yes

CPU Information:
  Cores: 8
  Min Frequency: 800 MHz
  Max Frequency: 4500 MHz
  Current Governor: performance

Core Status:
  [1] Core 0: 4200 MHz (TURBO) - performance
  [2] Core 1: 4100 MHz (TURBO) - performance
  [3] Core 2: 2400 MHz - ondemand
  [4] Core 3: 800 MHz (MIN) - powersave

Recent Events:
  [1] Core 0: Turbo Boost (5 min ago)
       4200 MHz engaged
  [2] Core 2: Thermal Throttling (10 min ago)
       Frequency reduced to 1.2 GHz
  [3] Core 0: Governor Changed (1 hour ago)
       ondemand -> performance

CPU Frequency Statistics:
  Avg Frequency: 2800 MHz
  Time at Turbo: 15%
  Time Throttled: 2%

Sound Settings:
  Frequency: bundled:cpufreq-change
  Throttle: bundled:cpufreq-throttle
  Turbo: bundled:cpufreq-turbo
  Governor: bundled:cpufreq-governor

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

CPU frequency monitoring doesn't play sounds directly:
- Monitoring feature using sysfs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### CPU Frequency Monitor

```go
type CPUFreqMonitor struct {
    config          *CPUFreqMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    coreState       map[int]*CoreInfo
    lastEventTime   map[string]time.Time
}

type CoreInfo struct {
    Core           int
    MinFreq        int64
    MaxFreq        int64
    CurrentFreq    int64
    Governor       string
    Throttled      bool
    Turbo          bool
}

func (m *CPUFreqMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.coreState = make(map[int]*CoreInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CPUFreqMonitor) monitor() {
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

func (m *CPUFreqMonitor) snapshotCoreState() {
    numCPU := runtime.NumCPU()
    m.coreState = make(map[int]*CoreInfo)

    for i := 0; i < numCPU; i++ {
        info := m.getCoreInfo(i)
        if info != nil {
            m.coreState[i] = info
        }
    }
}

func (m *CPUFreqMonitor) checkCoreState() {
    numCPU := runtime.NumCPU()

    for i := 0; i < numCPU; i++ {
        info := m.getCoreInfo(i)
        if info == nil {
            continue
        }

        lastInfo := m.coreState[i]
        if lastInfo == nil {
            m.coreState[i] = info
            continue
        }

        // Check frequency change
        if info.CurrentFreq != lastInfo.CurrentFreq {
            if m.shouldAlertFrequency(info.CurrentFreq, lastInfo.CurrentFreq) {
                m.onFrequencyChanged(i, info, lastInfo)
            }
        }

        // Check governor change
        if info.Governor != lastInfo.Governor {
            m.onGovernorChanged(i, info, lastInfo)
        }

        // Check throttle state
        if info.Throttled != lastInfo.Throttled && info.Throttled {
            m.onThermalThrottle(i, info)
        }

        // Check turbo state
        if info.Turbo != lastInfo.Turbo && info.Turbo {
            m.onTurboBoost(i, info)
        }

        m.coreState[i] = info
    }
}

func (m *CPUFreqMonitor) getCoreInfo(core int) *CoreInfo {
    basePath := fmt.Sprintf("/sys/devices/system/cpu/cpu%d/cpufreq", core)

    // Get current frequency
    freqPath := filepath.Join(basePath, "scaling_cur_freq")
    freqData, err := os.ReadFile(freqPath)
    if err != nil {
        return nil
    }
    currentFreq, _ := strconv.ParseInt(strings.TrimSpace(string(freqData)), 10, 64)

    // Get min frequency
    minPath := filepath.Join(basePath, "cpuinfo_min_freq")
    minData, err := os.ReadFile(minPath)
    minFreq, _ := strconv.ParseInt(strings.TrimSpace(string(minData)), 10, 64)

    // Get max frequency
    maxPath := filepath.Join(basePath, "cpuinfo_max_freq")
    maxData, err := os.ReadFile(maxPath)
    maxFreq, _ := strconv.ParseInt(strings.TrimSpace(string(maxData)), 10, 64)

    // Get governor
    govPath := filepath.Join(basePath, "scaling_governor")
    govData, err := os.ReadFile(govPath)
    governor := strings.TrimSpace(string(govData))

    // Check turbo status (intel_pstate or acpi-cpufreq)
    turboPath := "/sys/devices/system/cpu/intel_pstate/turbo_enabled"
    turboData, _ := os.ReadFile(turboPath)
    turbo := strings.TrimSpace(string(turboData)) == "1"

    // Check throttle status
    throttlePath := fmt.Sprintf("/sys/devices/system/cpu/cpu%d/throttle", core)
    throttleData, _ := os.ReadFile(throttlePath)
    throttled := strings.Contains(string(throttleData), "throttled")

    return &CoreInfo{
        Core:        core,
        MinFreq:     minFreq,
        MaxFreq:     maxFreq,
        CurrentFreq: currentFreq,
        Governor:    governor,
        Throttled:   throttled,
        Turbo:       turbo && currentFreq > maxFreq*9/10,
    }
}

func (m *CPUFreqMonitor) shouldAlertFrequency(newFreq int64, oldFreq int64) bool {
    if m.config.FrequencyThreshold == 0 {
        return true
    }

    diff := newFreq - oldFreq
    if diff < 0 {
        diff = -diff
    }

    return diff >= int64(m.config.FrequencyThreshold)
}

func (m *CPUFreqMonitor) onFrequencyChanged(core int, info *CoreInfo, last *CoreInfo) {
    if !m.config.SoundOnFrequency {
        return
    }

    key := fmt.Sprintf("freq:%d:%d->%d", core, last.CurrentFreq, info.CurrentFreq)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["frequency"]
        if sound != "" {
            volume := 0.3
            if info.CurrentFreq > last.CurrentFreq {
                volume = 0.4 // Frequency up is more important
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *CPUFreqMonitor) onGovernorChanged(core int, info *CoreInfo, last *CoreInfo) {
    if !m.config.SoundOnGovernor {
        return
    }

    key := fmt.Sprintf("gov:%d:%s->%s", core, last.Governor, info.Governor)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["governor"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *CPUFreqMonitor) onThermalThrottle(core int, info *CoreInfo) {
    if !m.config.SoundOnThrottle {
        return
    }

    key := fmt.Sprintf("throttle:%d", core)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["throttle"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CPUFreqMonitor) onTurboBoost(core int, info *CoreInfo) {
    if !m.config.SoundOnTurbo {
        return
    }

    key := fmt.Sprintf("turbo:%d", core)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["turbo"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CPUFreqMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /sys/devices/system/cpu/cpu*/cpufreq/* | Filesystem | Free | CPU frequency info |
| /proc/cpuinfo | File | Free | CPU information |

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
| macOS | Limited | No cpufreq, use powermetrics |
| Linux | Supported | Uses sysfs cpufreq |
