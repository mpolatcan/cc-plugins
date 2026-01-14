# Feature: Sound Event Fan Speed Monitor

Play sounds for fan speed changes, high RPM alerts, and fan failure events.

## Summary

Monitor system fans (CPU, GPU, chassis) for speed changes, high RPM, and failure detection, playing sounds for fan events.

## Motivation

- Thermal awareness
- Fan failure alerts
- Noise monitoring
- Hardware protection
- Performance tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Fan Speed Events

| Event | Description | Example |
|-------|-------------|---------|
| High RPM | Fan > threshold | 3000 RPM |
| Fan Failure | Fan stopped | 0 RPM |
| Speed Changed | RPM changed | changed |
| PWM Changed | Duty cycle changed | PWM changed |
| Fan Warning | Near critical | 90% max |
| Auto Mode | Fan control changed | auto mode |

### Configuration

```go
type FanSpeedMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchFans          []string          `json:"watch_fans"` // "cpu", "gpu", "chassis", "*"
    WarningRPM         int               `json:"warning_rpm"` // 3000 default
    CriticalRPM        int               `json:"critical_rpm"` // 4000 default
    FailureRPM         int               `json:"failure_rpm"` // 0 for stopped
    SoundOnWarning     bool              `json:"sound_on_warning"`
    SoundOnCritical    bool              `json:"sound_on_critical"`
    SoundOnFailure     bool              `json:"sound_on_failure"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:fan status                  # Show fan status
/ccbell:fan add cpu                 # Add fan to watch
/ccbell:fan warning 3000            # Set warning RPM
/ccbell:fan sound warning <sound>
/ccbell:fan test                    # Test fan sounds
```

### Output

```
$ ccbell:fan status

=== Sound Event Fan Speed Monitor ===

Status: Enabled
Warning: 3000 RPM
Critical: 4000 RPM
Failure: 0 RPM

Fan Status:

[1] CPU Fan (cpu_fan)
    Status: HEALTHY
    Speed: 1800 RPM
    Max: 3000 RPM (60%)
    Mode: PWM
    PWM: 60%
    Sound: bundled:fan-cpu

[2] GPU Fan (gpu_fan)
    Status: WARNING *** WARNING ***
    Speed: 3200 RPM *** HIGH ***
    Max: 4000 RPM (80%)
    Mode: Auto
    PWM: 80%
    Sound: bundled:fan-gpu *** WARNING ***

[3] Chassis Fan 1 (chassis_fan1)
    Status: HEALTHY
    Speed: 1200 RPM
    Max: 2000 RPM (60%)
    Mode: PWM
    PWM: 60%
    Sound: bundled:fan-chassis

[4] Chassis Fan 2 (chassis_fan2)
    Status: FAILED *** FAILED ***
    Speed: 0 RPM *** STOPPED ***
    Max: 2000 RPM (0%)
    Mode: PWM
    Sound: bundled:fan-chassis *** CRITICAL ***

Recent Events:

[1] GPU Fan: High Speed (5 min ago)
       3200 RPM > 3000 RPM threshold
       Sound: bundled:fan-warning
  [2] Chassis Fan 2: Fan Stopped (30 min ago)
       Fan speed dropped to 0 RPM
       Sound: bundled:fan-failure
  [3] CPU Fan: Speed Changed (1 hour ago)
       RPM increased from 1500 to 1800
       Sound: bundled:fan-change

Fan Statistics:
  Total Fans: 4
  Healthy: 2
  Warning: 1
  Failed: 1

Sound Settings:
  Warning: bundled:fan-warning
  Critical: bundled:fan-critical
  Failure: bundled:fan-failure
  Change: bundled:fan-change

[Configure] [Add Fan] [Test All]
```

---

## Audio Player Compatibility

Fan monitoring doesn't play sounds directly:
- Monitoring feature using sensors, ipmi-sensors, pwmconfig
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Fan Speed Monitor

```go
type FanSpeedMonitor struct {
    config        *FanSpeedMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    fanState      map[string]*FanInfo
    lastEventTime map[string]time.Time
}

type FanInfo struct {
    Name       string
    Label      string
    Speed      int // RPM
    MaxSpeed   int
    Percent    float64
    Mode       string // "PWM", "DC", "Auto"
    PWM        int // 0-100
    Status     string // "healthy", "warning", "critical", "failed"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| sensors | System Tool | Free | Hardware sensors (lm-sensors) |
| ipmi-sensors | System Tool | Free | IPMI fan sensors |
| pwmconfig | System Tool | Free | PWM configuration |

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
| macOS | Limited | Limited fan access |
| Linux | Supported | Uses sensors, ipmi-tools |
