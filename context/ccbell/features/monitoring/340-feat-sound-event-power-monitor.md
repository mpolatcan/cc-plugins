# Feature: Sound Event Power Monitor

Play sounds for power state changes and battery events.

## Summary

Monitor AC power status, battery level, charging state, and power source changes, playing sounds for power events.

## Motivation

- Power awareness
- Battery alerts
- Charging notifications
- Power source changes
- Low battery warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Power Events

| Event | Description | Example |
|-------|-------------|---------|
| Power Source Changed | AC connected/disconnected | On Battery -> On AC |
| Battery Low | Battery below threshold | 20% remaining |
| Battery Critical | Battery critically low | 5% remaining |
| Battery Full | Battery fully charged | 100% charged |
| Charging Started | Charging began | AC connected |
| Charging Stopped | Charging ended | AC disconnected |
| Time Remaining Changed | Estimate changed | 2h -> 1h 30m |

### Configuration

```go
type PowerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    LowThreshold      int               `json:"low_threshold"` // 20 default
    CriticalThreshold int               `json:"critical_threshold"` // 10 default
    SoundOnPowerChange bool             `json:"sound_on_power_change"`
    SoundOnLow        bool              `json:"sound_on_low"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnFull       bool              `json:"sound_on_full"`
    SoundOnCharging   bool              `json:"sound_on_charging"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type PowerEvent struct {
    Source         string // "ac", "battery"
    BatteryLevel   int // percentage
    Charging       bool
    TimeRemaining  int // minutes
    EventType      string // "power_change", "low", "critical", "full", "charging"
}
```

### Commands

```bash
/ccbell:power status                  # Show power status
/ccbell:power low 20                  # Set low battery threshold
/ccbell:power critical 10             # Set critical threshold
/ccbell:power sound low <sound>
/ccbell:power sound critical <sound>
/ccbell:power test                    # Test power sounds
```

### Output

```
$ ccbell:power status

=== Sound Event Power Monitor ===

Status: Enabled
Low Battery: 20%
Critical: 10%
Power Change Sounds: Yes
Low Battery Sounds: Yes

Power Source: On AC (Charging)

Battery Status:
  Level: 85%
  Status: Charging
  Time Remaining: 25 minutes
  Health: 95%
  Sound: bundled:power-charging

Recent Events:
  [1] Power Source Changed (5 min ago)
       On Battery -> On AC
  [2] Charging Started (5 min ago)
       Battery charging at 85%
  [3] Battery Full (2 hours ago)
       Charging complete

Power Statistics:
  Avg Battery Level: 75%
  Power Cycles Today: 3
  Time on Battery: 2 hours

Sound Settings:
  Power Change: bundled:power-change
  Low: bundled:power-low
  Critical: bundled:power-critical
  Full: bundled:power-full

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Power monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Power Monitor

```go
type PowerMonitor struct {
    config          *PowerMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    powerState      *PowerInfo
    lastEventTime   map[string]time.Time
}

type PowerInfo struct {
    Source        string // "ac", "battery"
    BatteryLevel  int
    Charging      bool
    TimeRemaining int
    CycleCount    int
    DesignCapacity int
    CurrentCapacity int
}

func (m *PowerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.powerState = &PowerInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *PowerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotPowerState()

    for {
        select {
        case <-ticker.C:
            m.checkPowerState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PowerMonitor) snapshotPowerState() {
    if runtime.GOOS == "darwin" {
        m.readDarwinPowerState()
    } else {
        m.readLinuxPowerState()
    }
}

func (m *PowerMonitor) checkPowerState() {
    newState := &PowerInfo{}

    if runtime.GOOS == "darwin" {
        m.readDarwinPowerState()
    } else {
        m.readLinuxPowerState()
    }
}

func (m *PowerMonitor) readDarwinPowerState() {
    cmd := exec.Command("pmset", "-g", "batt")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Now drawing") {
            // Parse: "Now drawing from 'Battery Power'"
            if strings.Contains(line, "Battery") {
                m.powerState.Source = "battery"
            } else {
                m.powerState.Source = "ac"
            }
        }

        if strings.HasPrefix(line, "\t") && strings.Contains(line, "%") {
            // Parse: "	85%; charging; 25:00 remaining"
            re := regexp.MustCompile(`(\d+)%; ([^;]+); (?:(\d+:\d+) remaining)?`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                level, _ := strconv.Atoi(match[1])
                m.powerState.BatteryLevel = level

                charging := strings.Contains(match[2], "charging")
                m.powerState.Charging = charging

                if match[3] != "" {
                    parts := strings.Split(match[3], ":")
                    if len(parts) == 2 {
                        hours, _ := strconv.Atoi(parts[0])
                        mins, _ := strconv.Atoi(parts[1])
                        m.powerState.TimeRemaining = hours*60 + mins
                    }
                }
            }
        }
    }
}

func (m *PowerMonitor) readLinuxPowerState() {
    // Read /sys/class/power_supply/*/uevent
    powerDir := "/sys/class/power_supply"

    entries, err := os.ReadDir(powerDir)
    if err != nil {
        return
    }

    for _, entry := range entries {
        typePath := filepath.Join(powerDir, entry.Name(), "type")
        typeData, err := os.ReadFile(typePath)
        if err != nil {
            continue
        }

        ptype := strings.TrimSpace(string(typeData))

        if ptype == "Battery" || ptype == "UPS" {
            m.readBatteryState(entry.Name())
        } else if ptype == "Mains" {
            m.readACState(entry.Name())
        }
    }
}

func (m *PowerMonitor) readBatteryState(name string) {
    basePath := filepath.Join("/sys/class/power_supply", name)

    // Read capacity
    capPath := filepath.Join(basePath, "capacity")
    capData, err := os.ReadFile(capPath)
    if err == nil {
        level, _ := strconv.Atoi(strings.TrimSpace(string(capData)))
        m.powerState.BatteryLevel = level
    }

    // Read status
    statusPath := filepath.Join(basePath, "status")
    statusData, err := os.ReadFile(statusPath)
    if err == nil {
        status := strings.TrimSpace(string(statusData))
        m.powerState.Charging = status == "Charging"
        if status == "Discharging" {
            m.powerState.Source = "battery"
        }
    }

    // Read time to empty/full
    timePath := filepath.Join(basePath, "time_to_empty_now")
    timeData, err := os.ReadFile(timePath)
    if err == nil && strings.TrimSpace(string(timeData)) != "0" {
        seconds, _ := strconv.Atoi(strings.TrimSpace(string(timeData)))
        m.powerState.TimeRemaining = seconds / 60
    }
}

func (m *PowerMonitor) readACState(name string) {
    onlinePath := filepath.Join("/sys/class/power_supply", name, "online")
    onlineData, err := os.ReadFile(onlinePath)
    if err == nil {
        online := strings.TrimSpace(string(onlineData)) == "1"
        if online {
            m.powerState.Source = "ac"
        } else if m.powerState.Source != "battery" {
            m.powerState.Source = "battery"
        }
    }
}

func (m *PowerMonitor) evaluatePowerEvents() {
    if m.powerState.Source != "" {
        // Check for power source change
    }

    // Check battery levels
    if m.powerState.BatteryLevel <= m.config.CriticalThreshold {
        m.onBatteryCritical()
    } else if m.powerState.BatteryLevel <= m.config.LowThreshold {
        m.onBatteryLow()
    } else if m.powerState.BatteryLevel >= 99 && !m.powerState.Charging {
        m.onBatteryFull()
    }
}

func (m *PowerMonitor) onBatteryLow() {
    if !m.config.SoundOnLow {
        return
    }

    if m.shouldAlert("low", 10*time.Minute) {
        sound := m.config.Sounds["low"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *PowerMonitor) onBatteryCritical() {
    if !m.config.SoundOnCritical {
        return
    }

    if m.shouldAlert("critical", 5*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *PowerMonitor) onBatteryFull() {
    if !m.config.SoundOnFull {
        return
    }

    if m.shouldAlert("full", 30*time.Minute) {
        sound := m.config.Sounds["full"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PowerMonitor) onPowerSourceChanged() {
    if !m.config.SoundOnPowerChange {
        return
    }

    key := "power_change"
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["power_change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PowerMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| pmset | System Tool | Free | macOS power management |
| /sys/class/power_supply/* | Filesystem | Free | Linux power info |

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
| macOS | Supported | Uses pmset |
| Linux | Supported | Uses sysfs power_supply |
