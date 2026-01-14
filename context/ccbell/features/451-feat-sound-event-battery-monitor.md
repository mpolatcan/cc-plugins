# Feature: Sound Event Battery Monitor

Play sounds for battery status changes, low battery warnings, and charging events.

## Summary

Monitor laptop battery status for charge level, charging state, and power source changes, playing sounds for battery events.

## Motivation

- Battery awareness
- Low battery alerts
- Charging notifications
- Power source awareness
- Prevent data loss

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Battery Events

| Event | Description | Example |
|-------|-------------|---------|
| Low Battery | Below warning threshold | < 20% |
| Critical Battery | Below critical threshold | < 10% |
| Charging Started | Plugged in charging | charging |
| Charging Complete | Fully charged | 100% |
| Power Unplugged | Running on battery | on battery |
| Power Plugged | Connected to AC | on AC |

### Configuration

```go
type BatteryMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WarningLevel       int               `json:"warning_level"` // 20 default
    CriticalLevel      int               `json:"critical_level"` // 10 default
    SoundOnWarning     bool              `json:"sound_on_warning"`
    SoundOnCritical    bool              `json:"sound_on_critical"`
    SoundOnCharging    bool              `json:"sound_on_charging"`
    SoundOnComplete    bool              `json:"sound_on_complete"`
    SoundOnUnplugged   bool              `json:"sound_on_unplugged"`
    SoundOnPlugged     bool              `json:"sound_on_plugged"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:battery status              # Show battery status
/ccbell:battery warning 20          # Set warning level
/ccbell:battery sound warning <sound>
/ccbell:battery test                # Test battery sounds
```

### Output

```
$ ccbell:battery status

=== Sound Event Battery Monitor ===

Status: Enabled
Warning: 20%
Critical: 10%

Battery Status:

[1] Battery
    Status: DISCHARGING
    Percentage: 18% *** LOW ***
    Time Remaining: 45 min
    Temperature: 35C
    Health: 95%
    Sound: bundled:battery-low

Power Source:
    Status: On Battery
    AC Connected: No

Recent Events:

[1] Battery: Low Warning (5 min ago)
       18% < 20% threshold
       Sound: bundled:battery-warning
  [2] Power: Unplugged (1 hour ago)
       Running on battery
       Sound: bundled:battery-unplugged
  [3] Battery: Charging Started (3 hours ago)
       Started charging at 15%
       Sound: bundled:battery-charging

Battery Statistics:
  Current Level: 18%
  Status: Discharging
  Time Remaining: 45 min
  Cycles: 145

Sound Settings:
  Warning: bundled:battery-warning
  Critical: bundled:battery-critical
  Charging: bundled:battery-charging
  Complete: bundled:battery-complete
  Unplugged: bundled:battery-unplugged
  Plugged: bundled:battery-plugged

[Configure] [Test All]
```

---

## Audio Player Compatibility

Battery monitoring doesn't play sounds directly:
- Monitoring feature using pmset, upower, /sys/class/power_supply
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Battery Monitor

```go
type BatteryMonitor struct {
    config        *BatteryMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    batteryState  *BatteryInfo
    lastEventTime map[string]time.Time
}

type BatteryInfo struct {
    Percentage    int
    Status        string // "charging", "discharging", "full", "unknown"
    TimeRemaining int // minutes
    Temperature   float64
    Health        int // percentage
    CycleCount    int
    PowerSource   string // "AC", "Battery"
}

func (m *BatteryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.batteryState = nil
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *BatteryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotBatteryState()

    for {
        select {
        case <-ticker.C:
            m.checkBatteryState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BatteryMonitor) snapshotBatteryState() {
    m.checkBatteryState()
}

func (m *BatteryMonitor) checkBatteryState() {
    info := m.getBatteryInfo()
    if info != nil {
        m.processBatteryStatus(info)
    }
}

func (m *BatteryMonitor) getBatteryInfo() *BatteryInfo {
    info := &BatteryInfo{}

    // Try macOS first
    if runtime.GOOS == "darwin" {
        return m.getMacOSBatteryInfo()
    }

    // Try Linux methods
    return m.getLinuxBatteryInfo()
}

func (m *BatteryMonitor) getMacOSBatteryInfo() *BatteryInfo {
    info := &BatteryInfo{}

    cmd := exec.Command("pmset", "-g", "batt")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Now drawing") {
            // Parse: "   -0: 18%; discharging; 45:00 remaining"
            parts := strings.Split(line, ";")
            if len(parts) >= 3 {
                // Get percentage
                pctRe := regexp.MustEach(`(\d+)%`)
                matches := pctRe.FindStringSubmatch(parts[0])
                if len(matches) >= 2 {
                    info.Percentage, _ = strconv.Atoi(matches[1])
                }

                // Get status
                statusStr := strings.TrimSpace(parts[1])
                if strings.Contains(statusStr, "charging") {
                    info.Status = "charging"
                } else if strings.Contains(statusStr, "discharging") {
                    info.Status = "discharging"
                } else if strings.Contains(statusStr, "finishing") {
                    info.Status = "charging"
                } else if strings.Contains(statusStr, "AC") {
                    info.Status = "full"
                }

                // Get time remaining
                timeRe := regexp.MustEach(`(\d+):(\d+)\s*remaining`)
                timeMatches := timeRe.FindStringSubmatch(parts[2])
                if len(timeMatches) >= 3 {
                    hours, _ := strconv.Atoi(timeMatches[1])
                    mins, _ := strconv.Atoi(timeMatches[2])
                    info.TimeRemaining = hours*60 + mins
                }
            }
        }

        if strings.Contains(line, "Power Source") {
            if strings.Contains(line, "AC Power") {
                info.PowerSource = "AC"
            } else {
                info.PowerSource = "Battery"
            }
        }
    }

    // Get cycle count
    cmd = exec.Command("ioreg", "-r", "-c", "AppleSmartBattery")
    ioregOutput, _ := cmd.Output()

    cycleRe := regexp.MustEach(`"CycleCount"=(\d+)`)
    cycleMatches := cycleRe.FindStringSubmatch(string(ioregOutput))
    if len(cycleMatches) >= 2 {
        info.CycleCount, _ = strconv.Atoi(cycleMatches[1])
    }

    return info
}

func (m *BatteryMonitor) getLinuxBatteryInfo() *BatteryInfo {
    info := &BatteryInfo{}

    // Try reading from /sys/class/power_supply/
    powerPath := "/sys/class/power_supply/"
    entries, _ := os.ReadDir(powerPath)

    for _, entry := range entries {
        batPath := filepath.Join(powerPath, entry.Name())

        // Check if this is a battery
        typeFile := filepath.Join(batPath, "type")
        data, err := os.ReadFile(typeFile)
        if err != nil || string(data) != "Battery\n" {
            continue
        }

        // Read capacity
        capacityFile := filepath.Join(batPath, "capacity")
        capacityData, _ := os.ReadFile(capacityFile)
        if capacityData != nil {
            info.Percentage, _ = strconv.Atoi(strings.TrimSpace(string(capacityData)))
        }

        // Read status
        statusFile := filepath.Join(batPath, "status")
        statusData, _ := os.ReadFile(statusFile)
        if statusData != nil {
            statusStr := strings.TrimSpace(string(statusData))
            info.Status = strings.ToLower(statusStr)
        }

        // Read cycle count
        cycleFile := filepath.Join(batPath, "cycle_count")
        cycleData, _ := os.ReadFile(cycleFile)
        if cycleData != nil {
            info.CycleCount, _ = strconv.Atoi(strings.TrimSpace(string(cycleData)))
        }

        // Try upower for more info
        cmd := exec.Command("upower", "-i", filepath.Join("/org/freedesktop/UPower/devices/battery_"+entry.Name()))
        upowerOutput, err := cmd.Output()
        if err == nil {
            // Parse upower output
            for _, line := range strings.Split(string(upowerOutput), "\n") {
                if strings.Contains(line, "percentage:") {
                    pct := strings.Split(line, ":")[1]
                    info.Percentage, _ = strconv.Atoi(strings.TrimSpace(pct))
                }
                if strings.Contains(line, "state:") {
                    info.Status = strings.Split(line, ":")[1]
                    info.Status = strings.TrimSpace(info.Status)
                }
            }
        }

        // Determine power source
        onlineFile := filepath.Join(batPath, "online")
        onlineData, _ := os.ReadFile(onlineFile)
        if onlineData != nil {
            if strings.TrimSpace(string(onlineData)) == "1" {
                info.PowerSource = "AC"
            } else {
                info.PowerSource = "Battery"
            }
        }

        break // Only process first battery
    }

    return info
}

func (m *BatteryMonitor) processBatteryStatus(info *BatteryInfo) {
    if m.batteryState == nil {
        m.batteryState = info
        return
    }

    lastInfo := m.batteryState

    // Check for percentage changes
    if info.Percentage != lastInfo.Percentage {
        // Low battery warning
        if info.Percentage <= m.config.WarningLevel && info.Percentage > m.config.CriticalLevel {
            if lastInfo.Percentage > m.config.WarningLevel {
                if m.config.SoundOnWarning && m.shouldAlert("warning", 5*time.Minute) {
                    m.onLowBattery(info)
                }
            }
        }

        // Critical battery
        if info.Percentage <= m.config.CriticalLevel {
            if lastInfo.Percentage > m.config.CriticalLevel {
                if m.config.SoundOnCritical && m.shouldAlert("critical", 2*time.Minute) {
                    m.onCriticalBattery(info)
                }
            }
        }

        // Fully charged
        if info.Percentage == 100 && lastInfo.Percentage < 100 {
            if m.config.SoundOnComplete {
                m.onChargingComplete(info)
            }
        }
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "charging":
            if lastInfo.Status == "discharging" {
                if m.config.SoundOnCharging {
                    m.onChargingStarted(info)
                }
            }
        case "discharging":
            if lastInfo.Status == "charging" || lastInfo.Status == "full" {
                if m.config.SoundOnUnplugged {
                    m.onPowerUnplugged(info)
                }
            }
        case "full":
            if m.config.SoundOnComplete {
                m.onChargingComplete(info)
            }
        }
    }

    m.batteryState = info
}

func (m *BatteryMonitor) onLowBattery(info *BatteryInfo) {
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *BatteryMonitor) onCriticalBattery(info *BatteryInfo) {
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *BatteryMonitor) onChargingStarted(info *BatteryInfo) {
    sound := m.config.Sounds["charging"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *BatteryMonitor) onChargingComplete(info *BatteryInfo) {
    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BatteryMonitor) onPowerUnplugged(info *BatteryInfo) {
    sound := m.config.Sounds["unplugged"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *BatteryMonitor) onPowerPlugged(info *BatteryInfo) {
    sound := m.config.Sounds["plugged"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *BatteryMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| upower | System Tool | Free | Linux power management |
| ioreg | System Tool | Free | macOS I/O registry |

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
| macOS | Supported | Uses pmset, ioreg |
| Linux | Supported | Uses upower, /sys/class/power_supply |
