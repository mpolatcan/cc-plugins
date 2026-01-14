# Feature: Sound Event Power State Monitor

Play sounds for power state changes, battery levels, and charging events.

## Summary

Monitor system power states, battery levels, and charging status, playing sounds for power events.

## Motivation

- Battery awareness
- Power state feedback
- Charging alerts
- Critical battery warnings
- Performance switching

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Power State Events

| Event | Description | Example |
|-------|-------------|---------|
| Battery Low | Below threshold | < 20% |
| Battery Critical | Very low | < 10% |
| Charging Started | AC connected | plugged in |
| Charging Complete | Fully charged | 100% |
| On Battery | On battery power | unplugged |
| On AC | AC power connected | plugged in |
| Sleep Mode | System sleeping | suspend |
| Wake Up | System woke up | resume |

### Configuration

```go
type PowerStateMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    LowThreshold      int               `json:"low_threshold"` // 20 default
    CriticalThreshold int               `json:"critical_threshold"` // 10 default
    SoundOnLow        bool              `json:"sound_on_low"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnCharging   bool              `json:"sound_on_charging"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnSleep      bool              `json:"sound_on_sleep"`
    SoundOnWake       bool              `json:"sound_on_wake"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:power status                   # Show power status
/ccbell:power low 20                   # Set low threshold
/ccbell:power critical 10              # Set critical threshold
/ccbell:power sound low <sound>
/ccbell:power sound critical <sound>
/ccbell:power test                     # Test power sounds
```

### Output

```
$ ccbell:power status

=== Sound Event Power State Monitor ===

Status: Enabled
Low Threshold: 20%
Critical Threshold: 10%
Charging Sounds: Yes
Critical Sounds: Yes

Current Status:

Power Source: On Battery
Battery Level: 35%
Time Remaining: 2h 15m
Cycle Count: 245
Health: 92%

Charging: No
Charging Rate: 0 mA
Time to Full: N/A

AC State: Disconnected

Recent Events:
  [1] Battery Level: Low (5 min ago)
       20% < threshold
  [2] Power Source: On Battery (1 hour ago)
       Unplugged from AC
  [3] System: Wake Up (2 hours ago)
       Returned from sleep

Power Statistics:
  Low Battery Alerts: 8
  Critical Alerts: 2
  Sleep/Wake Events: 15

Sound Settings:
  Low: bundled:power-low
  Critical: bundled:power-critical
  Charging: bundled:power-charging
  Complete: bundled:power-complete
  Sleep: bundled:power-sleep
  Wake: bundled:power-wake

[Configure] [Test All]
```

---

## Audio Player Compatibility

Power monitoring doesn't play sounds directly:
- Monitoring feature using pmset/power_supply
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Power State Monitor

```go
type PowerStateMonitor struct {
    config          *PowerStateMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    lastState       *PowerStateInfo
    lastEventTime   map[string]time.Time
}

type PowerStateInfo struct {
    PowerSource   string // "AC", "Battery"
    BatteryLevel  int    // percentage
    Charging      bool
    ChargingRate  int    // mA
    TimeRemaining int    // minutes
    ACConnected   bool
    IsSleeping    bool
}

func (m *PowerStateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEventTime = make(map[string]time.Time)
    m.lastState = m.getPowerState()
    go m.monitor()
}

func (m *PowerStateMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkPowerState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PowerStateMonitor) checkPowerState() {
    currentState := m.getPowerState()

    if m.lastState == nil {
        m.lastState = currentState
        return
    }

    // Check power source change
    if m.lastState.PowerSource != currentState.PowerSource {
        if currentState.PowerSource == "Battery" {
            m.onOnBattery()
        } else {
            m.onOnAC()
        }
    }

    // Check charging state
    if !m.lastState.Charging && currentState.Charging {
        m.onChargingStarted()
    } else if m.lastState.Charging && !currentState.Charging {
        m.onChargingStopped()
    }

    // Check battery level
    if m.lastState.BatteryLevel > currentState.BatteryLevel {
        if currentState.BatteryLevel <= m.config.CriticalThreshold {
            if m.config.SoundOnCritical {
                m.onCriticalBattery(currentState)
            }
        } else if currentState.BatteryLevel <= m.config.LowThreshold {
            if m.config.SoundOnLow {
                m.onLowBattery(currentState)
            }
        }
    }

    // Check full charge
    if currentState.Charging && currentState.BatteryLevel >= 100 {
        if m.lastState.BatteryLevel < 100 {
            if m.config.SoundOnComplete {
                m.onChargingComplete()
            }
        }
    }

    // Check sleep/wake
    if !m.lastState.IsSleeping && currentState.IsSleeping {
        m.onSleep()
    } else if m.lastState.IsSleeping && !currentState.IsSleeping {
        m.onWake()
    }

    m.lastState = currentState
}

func (m *PowerStateMonitor) getPowerState() *PowerStateInfo {
    info := &PowerStateInfo{}

    if m.isMacOS() {
        m.getMacOSPowerState(info)
    } else {
        m.getLinuxPowerState(info)
    }

    return info
}

func (m *PowerStateMonitor) isMacOS() bool {
    return runtime.GOOS == "darwin"
}

func (m *PowerStateMonitor) getMacOSPowerState(info *PowerStateInfo) {
    cmd := exec.Command("pmset", "-g", "batt")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse: "Now drawing from 'Battery Power'"
    // "35%; discharging; 2:15 remaining"
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "'Battery Power'") || strings.Contains(line, "'AC Power'") {
            if strings.Contains(line, "AC Power") {
                info.PowerSource = "AC"
                info.ACConnected = true
            } else {
                info.PowerSource = "Battery"
                info.ACConnected = false
            }
        }

        if strings.HasPrefix(line, "\t") {
            // Parse battery info
            re := regexp.MustCompile(`(\d+)%; (discharging|charging|finishing);?.*`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                level, _ := strconv.Atoi(match[1])
                info.BatteryLevel = level

                status := match[2]
                info.Charging = status == "charging" || status == "finishing"

                if status == "discharging" {
                    // Parse time remaining
                    re = regexp.MustEach(`(\d+):(\d+)`)
                    // Extract time
                }
            }
        }
    }

    // Check if system is sleeping
    cmd = exec.Command("pmset", "-g", " assertions")
    output, _ = cmd.Output()
    if strings.Contains(string(output), "PreventUserIdleSystemSleep") {
        info.IsSleeping = false // Active
    }
}

func (m *PowerStateMonitor) getLinuxPowerState(info *PowerStateInfo) {
    // Read from /sys/class/power_supply/
    supplyPath := "/sys/class/power_supply/"

    entries, err := os.ReadDir(supplyPath)
    if err != nil {
        return
    }

    for _, entry := range entries {
        name := entry.Name()

        // Check for BAT0 or battery
        if !strings.Contains(strings.ToLower(name), "bat") &&
           !strings.Contains(strings.ToLower(name), "battery") {
            continue
        }

        // Read status
        statusPath := filepath.Join(supplyPath, name, "status")
        status, _ := os.ReadFile(statusPath)
        statusStr := strings.TrimSpace(string(status))

        if statusStr == "Charging" || statusStr == "Full" {
            info.Charging = true
            info.ACConnected = true
            info.PowerSource = "AC"
        } else if statusStr == "Discharging" {
            info.Charging = false
            info.ACConnected = false
            info.PowerSource = "Battery"
        }

        // Read capacity
        capacityPath := filepath.Join(supplyPath, name, "capacity")
        capacity, _ := os.ReadFile(capacityPath)
        if cap, err := strconv.Atoi(strings.TrimSpace(string(capacity))); err == nil {
            info.BatteryLevel = cap
        }

        break // Only check first battery
    }

    // Check AC status
    acPath := filepath.Join(supplyPath, "AC", "online")
    if online, err := os.ReadFile(acPath); err == nil {
        info.ACConnected = strings.TrimSpace(string(online)) == "1"
        if info.ACConnected && !info.Charging {
            info.PowerSource = "AC"
        }
    }
}

func (m *PowerStateMonitor) onLowBattery(info *PowerStateInfo) {
    key := "battery:low"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["low"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *PowerStateMonitor) onCriticalBattery(info *PowerStateInfo) {
    key := "battery:critical"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *PowerStateMonitor) onChargingStarted() {
    if !m.config.SoundOnCharging {
        return
    }

    key := "power:charging"
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["charging"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PowerStateMonitor) onChargingStopped() {
    // Optional: sound when charging stops before full
}

func (m *PowerStateMonitor) onChargingComplete() {
    if !m.config.SoundOnComplete {
        return
    }

    key := "power:complete"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PowerStateMonitor) onOnBattery() {
    key := "power:battery"
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["battery"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *PowerStateMonitor) onOnAC() {
    key := "power:ac"
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["ac"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *PowerStateMonitor) onSleep() {
    if !m.config.SoundOnSleep {
        return
    }

    key := "power:sleep"
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["sleep"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *PowerStateMonitor) onWake() {
    if !m.config.SoundOnWake {
        return
    }

    key := "power:wake"
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["wake"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *PowerStateMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /sys/class/power_supply | Linux Path | Free | Linux power info |

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
| Linux | Supported | Uses /sys/class/power_supply |
