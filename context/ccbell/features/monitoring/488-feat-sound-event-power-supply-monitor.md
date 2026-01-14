# Feature: Sound Event Power Supply Monitor

Play sounds for power supply status, capacity, and failure events.

## Summary

Monitor power supply units (PSU) for status changes, capacity warnings, and failure detection, playing sounds for power events.

## Motivation

- Power awareness
- UPS monitoring
- Capacity alerts
- Failure detection
- Redundancy tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Power Supply Events

| Event | Description | Example |
|-------|-------------|---------|
| Power Lost | Input lost | lost |
| Power Restored | Input restored | restored |
| Capacity Low | Load > 80% | 85% load |
| UPS Mode | On battery | battery |
| Battery Low | Battery < 20% | 15% left |
| Overload | Load > 100% | overloaded |

### Configuration

```go
type PowerSupplyMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchPSU         string            `json:"watch_psu"` // "/org/freedesktop/UPower/devices/line_power_*"
    CapacityWarning  int               `json:"capacity_warning"` // 80
    BatteryWarning   int               `json:"battery_warning"` // 20
    SoundOnLost      bool              `json:"sound_on_lost"`
    SoundOnRestored  bool              `json:"sound_on_restored"`
    SoundOnLow       bool              `json:"sound_on_low"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:powersupply status          # Show power supply status
/ccbell:powersupply add ups         # Add PSU to watch
/ccbell:powersupply sound lost <sound>
/ccbell:powersupply test            # Test power sounds
```

### Output

```
$ ccbell:powersupply status

=== Sound Event Power Supply Monitor ===

Status: Enabled
Capacity Warning: 80%
Battery Warning: 20%

Power Supply Status:

[1] AC Adapter (AC)
    Status: ONLINE
    Online: Yes
    Type: AC
    Current: 65W
    Sound: bundled:powersupply-ac

[2] UPS (UPS)
    Status: ONLINE *** ON BATTERY ***
    Type: UPS
    Charge: 45%
    Time Remaining: 15 min
    Load: 65% *** NEAR CAPACITY ***
    Temperature: 35C
    Sound: bundled:powersupply-ups *** WARNING ***

[3] Battery (BAT0)
    Status: CHARGING
    Type: Battery
    Charge: 78%
    Current: -15W (discharging)
    Time Remaining: 2 hours
    Health: 95%
    Sound: bundled:powersupply-battery

Recent Events:

[1] UPS: On Battery (5 min ago)
       AC power lost, running on battery
       Sound: bundled:powersupply-lost
  [2] UPS: Low Battery (10 min ago)
       45% < 50% threshold
       Sound: bundled:powersupply-low
  [3] AC Adapter: Power Restored (30 min ago)
       AC power restored
       Sound: bundled:powersupply-restored

Power Supply Statistics:
  Total Devices: 3
  Online: 2
  On Battery: 1
  Low Battery: 0

Sound Settings:
  Lost: bundled:powersupply-lost
  Restored: bundled:powersupply-restored
  Low: bundled:powersupply-low
  Overload: bundled:powersupply-overload

[Configure] [Add PSU] [Test All]
```

---

## Audio Player Compatibility

Power supply monitoring doesn't play sounds directly:
- Monitoring feature using upower, pmset
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Power Supply Monitor

```go
type PowerSupplyMonitor struct {
    config        *PowerSupplyMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    psuState      map[string]*PSUInfo
    lastEventTime map[string]time.Time
}

type PSUInfo struct {
    Name           string
    Type           string // "AC", "UPS", "Battery"
    Status         string // "online", "offline", "charging", "discharging"
    ChargePercent  float64
    CurrentWatts   float64
    LoadPercent    float64
    TimeRemaining  int // minutes
    Temperature    float64
    Health         float64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| upower | System Tool | Free | Power management |
| pmset | System Tool | Free | macOS power settings |
| apcaccess | System Tool | Free | APC UPS monitoring |

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
| macOS | Supported | Uses pmset, upower |
| Linux | Supported | Uses upower, apcaccess |
