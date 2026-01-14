# Feature: Sound Event CPU Frequency Monitor

Play sounds for CPU frequency changes, turbo boost events, and power saving mode.

## Summary

Monitor CPU frequency scaling, turbo boost activation, and governor changes, playing sounds for frequency events.

## Motivation

- Performance awareness
- Frequency tracking
- Turbo boost detection
- Power saving awareness
- Performance tuning

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
| Frequency Changed | Clock changed | 2.4GHz -> 3.0GHz |
| Turbo Boost | Boost active | 4.5GHz |
| Turbo Disabled | Boost off | disabled |
| Governor Changed | Scaling governor | powersave->performance |
| Min Frequency | Hit min freq | 800MHz |
| Max Frequency | Hit max freq | 4.5GHz |

### Configuration

```go
type CPUFrequencyMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchCPU          int               `json:"watch_cpu"` // -1 for all
    SoundOnBoost      bool              `json:"sound_on_boost"]
    SoundOnChange     bool              `json:"sound_on_change"`
    SoundOnGovernor   bool              `json:"sound_on_governor"]
    FrequencyThresholdMHz int           `json:"frequency_threshold_mhz"] // 0 for disabled
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:cpufreq status              # Show CPU frequency status
/ccbell:cpufreq add 0               # Add CPU to watch
/ccbell:cpufreq sound boost <sound>
/ccbell:cpufreq test                # Test CPU frequency sounds
```

### Output

```
$ ccbell:cpufreq status

=== Sound Event CPU Frequency Monitor ===

Status: Enabled
Watch CPUs: all

CPU Frequency Status:

[1] CPU 0
    Status: TURBO BOOST *** BOOST ***
    Current: 4.5 GHz
    Base: 3.0 GHz
    Min: 800 MHz
    Max: 4.5 GHz
    Governor: performance
    Sound: bundled:cpufreq-cpu0 *** ACTIVE ***

[2] CPU 1
    Status: NORMAL
    Current: 2.4 GHz
    Base: 3.0 GHz
    Min: 800 MHz
    Max: 4.5 GHz
    Governor: powersave
    Sound: bundled:cpufreq-cpu1

[3] CPU 2
    Status: POWER SAVE
    Current: 800 MHz
    Base: 3.0 GHz
    Min: 800 MHz
    Max: 4.5 GHz
    Governor: powersave
    Sound: bundled:cpufreq-cpu2

[4] CPU 3
    Status: NORMAL
    Current: 3.2 GHz
    Base: 3.0 GHz
    Min: 800 MHz
    Max: 4.5 GHz
    Governor: ondemand
    Sound: bundled:cpufreq-cpu3

Recent Events:

[1] CPU 0: Turbo Boost Active (5 min ago)
       Boosted to 4.5 GHz
       Sound: bundled:cpufreq-boost
  [2] CPU 2: Frequency Changed (10 min ago)
       2.4 GHz -> 800 MHz
       Sound: bundled:cpufreq-change
  [3] CPU 1: Governor Changed (30 min ago)
       performance -> powersave
       Sound: bundled:cpufreq-governor

CPU Frequency Statistics:
  CPUs: 4
  Avg Frequency: 2.7 GHz
  Turbo Active: 1
  Power Save: 1

Sound Settings:
  Boost: bundled:cpufreq-boost
  Change: bundled:cpufreq-change
  Governor: bundled:cpufreq-governor
  Max: bundled:cpufreq-max

[Configure] [Add CPU] [Test All]
```

---

## Audio Player Compatibility

CPU frequency monitoring doesn't play sounds directly:
- Monitoring feature using cpufreq-info, sysctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### CPU Frequency Monitor

```go
type CPUFrequencyMonitor struct {
    config        *CPUFrequencyMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    cpuState      map[int]*CPUFreqInfo
    lastEventTime map[string]time.Time
}

type CPUFreqInfo struct {
    CPU           int
    Status        string // "normal", "turbo", "powersave", "max", "min"
    CurrentMHz    float64
    BaseMHz       float64
    MinMHz        float64
    MaxMHz        float64
    Governor      string
    IsTurbo       bool
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| cpufreq-info | System Tool | Free | CPU frequency info |
| sysctl | System Tool | Free | System configuration |
| lscpu | System Tool | Free | CPU information |

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
| Linux | Supported | Uses cpufreq-info, /sys/devices |
