# Feature: Sound Event CPU Thermal Throttling Monitor

Play sounds for CPU thermal throttling events and temperature thresholds.

## Summary

Monitor CPU core temperatures for thermal throttling events, warning thresholds, and critical temperatures, playing sounds for thermal events.

## Motivation

- Thermal awareness
- Performance protection
- Throttling detection
- Hardware safety
- Cooling system alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### CPU Thermal Events

| Event | Description | Example |
|-------|-------------|---------|
| Thermal Warning | > 70C | 75C warning |
| Thermal Critical | > 85C | 90C critical |
| Throttling Active | Clock reduced | throttled |
| Throttling Stopped | Back to normal | normal |
| Clock Reduced | Below base clock | reduced |
| Emergency Shutdown | Near max temp | 105C |

### Configuration

```go
type CPUThermalMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchCores       []int             `json:"watch_cores"` // empty for all
    WarningTemp      int               `json:"warning_temp_c"` // 70 default
    CriticalTemp     int               `json:"critical_temp_c"` // 85 default
    EmergencyTemp    int               `json:"emergency_temp_c"` // 100 default
    SoundOnWarning   bool              `json:"sound_on_warning"`
    SoundOnCritical  bool              `json:"sound_on_critical"]
    SoundOnThrottle  bool              `json:"sound_on_throttle"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 15 default
}
```

### Commands

```bash
/ccbell:thermal status              # Show thermal status
/ccbell:thermal warning 70          # Set warning threshold
/ccbell:thermal sound warning <sound>
/ccbell:thermal test                # Test thermal sounds
```

### Output

```
$ ccbell:thermal status

=== Sound Event CPU Thermal Monitor ===

Status: Enabled
Warning: 70C
Critical: 85C
Emergency: 100C

CPU Thermal Status:

[1] Core 0
    Temperature: 65C
    Status: HEALTHY
    Throttling: No
    Clock: 3.0 GHz
    Sound: bundled:thermal-core0

[2] Core 1
    Temperature: 68C
    Status: HEALTHY
    Throttling: No
    Clock: 3.0 GHz
    Sound: bundled:thermal-core1

[3] Core 2
    Temperature: 78C *** WARNING ***
    Status: WARNING
    Throttling: No
    Clock: 3.0 GHz
    Sound: bundled:thermal-core2 *** WARNING ***

[4] Core 3
    Temperature: 88C *** CRITICAL ***
    Status: CRITICAL
    Throttling: Yes *** THROTTLING ***
    Clock: 2.2 GHz (reduced)
    Sound: bundled:thermal-core3 *** FAILED ***

Recent Events:

[1] Core 3: Thermal Critical (5 min ago)
       88C > 85C threshold
       Sound: bundled:thermal-critical
  [2] Core 3: Throttling Active (6 min ago)
       Clock reduced from 3.0 GHz to 2.2 GHz
       Sound: bundled:thermal-throttle
  [3] Core 2: Thermal Warning (10 min ago)
       78C > 70C threshold
       Sound: bundled:thermal-warning

CPU Thermal Statistics:
  Cores: 4
  Healthy: 2
  Warning: 1
  Critical: 1
  Throttling: 1

Sound Settings:
  Warning: bundled:thermal-warning
  Critical: bundled:thermal-critical
  Throttle: bundled:thermal-throttle
  Normal: bundled:thermal-normal

[Configure] [Test All]
```

---

## Audio Player Compatibility

Thermal monitoring doesn't play sounds directly:
- Monitoring feature using sensors, powermetrics, /sys/class/thermal
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### CPU Thermal Monitor

```go
type CPUThermalMonitor struct {
    config        *CPUThermalMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    thermalState  map[int]*ThermalInfo
    lastEventTime map[string]time.Time
}

type ThermalInfo struct {
    Core         int
    Temperature  float64
    Status       string // "healthy", "warning", "critical", "emergency"
    Throttling   bool
    ClockMHz     float64
    BaseClockMHz float64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| sensors | System Tool | Free | Hardware sensors |
| powermetrics | System Tool | Free | macOS thermal metrics |
| /sys/class/thermal | Path | Free | Linux thermal zones |

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
| macOS | Supported | Uses powermetrics |
| Linux | Supported | Uses sensors, /sys/class/thermal |
