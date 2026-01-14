# Feature: Sound Event Battery Monitor

Play sounds for battery level changes, charging status, and power events.

## Summary

Monitor laptop battery status for level changes, charging events, and power source changes, playing sounds for battery events.

## Motivation

- Battery awareness
- Charging completion alerts
- Low battery warnings
- Power source changes
- Battery health tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Battery Events

| Event | Description | Example |
|-------|-------------|---------|
| Battery Low | Below threshold | < 20% |
| Battery Critical | Very low | < 10% |
| Battery Full | Fully charged | 100% |
| Charging Started | AC connected | charging |
| Charging Stopped | AC disconnected | on battery |
| Power Source | Switched power | on battery |

### Configuration

```go
type BatteryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WarningPercent    int               `json:"warning_percent"` // 20 default
    CriticalPercent   int               `json:"critical_percent"` // 10 default
    SoundOnLow        bool              `json:"sound_on_low"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnFull       bool              `json:"sound_on_full"`
    SoundOnCharging   bool              `json:"sound_on_charging"`
    SoundOnDischarging bool             `json:"sound_on_discharging"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:battery status               # Show battery status
/ccbell:battery warning 20           # Set warning threshold
/ccbell:battery critical 10          # Set critical threshold
/ccbell:battery sound low <sound>
/ccbell:battery sound critical <sound>
/ccbell:battery test                 # Test battery sounds
```

### Output

```
$ ccbell:battery status

=== Sound Event Battery Monitor ===

Status: Enabled
Warning Threshold: 20%
Critical Threshold: 10%

Battery Status:

[1] BAT0 (Main Battery)
    Status: DISCHARGING
    Level: 45%
    Time Remaining: 2 hours 30 min
    Temperature: 35C
    Health: 92%
    Sound: bundled:battery-main

[2] BAT1 (Secondary Battery)
    Status: CHARGING
    Level: 78%
    Time to Full: 45 min
    Temperature: 32C
    Health: 95%
    Sound: bundled:battery-secondary

Power Status:
  Source: BATTERY
  AC Connected: No
  System Power Draw: 45W

Battery History:

  08:00: 100% (Full)
  10:00: 85% (Discharging)
  12:00: 65% (Discharging)
  14:00: 45% (Discharging)

Recent Events:
  [1] BAT0: Charging Stopped (2 hours ago)
       Unplugged from AC
  [2] BAT1: Charging Started (3 hours ago)
       Connected to AC
  [3] BAT0: Battery Low (5 hours ago)
       20% threshold crossed

Battery Statistics:
  Avg Discharge Rate: 15%/hour
  Last Full Charge: Jan 14, 2026 08:00
  Total Charge Cycles: 145

Sound Settings:
  Low: bundled:battery-low
  Critical: bundled:battery-critical
  Full: bundled:battery-full
  Charging: bundled:battery-charging
  Discharging: bundled:battery-discharging

[Configure] [Test All]
```

---

## Audio Player Compatibility

Battery monitoring doesn't play sounds directly:
- Monitoring feature using pmset/power_supply
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Battery Monitor

```go
type BatteryMonitor struct {
    config          *BatteryMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    batteryState    map[string]*BatteryInfo
    lastEventTime   map[string]time.Time
    lastStatus      string
}

type BatteryInfo struct {
    Name           string
    Status         string // "charging", "discharging", "full", "unknown"
    Level          int    // 0-100
    Temperature    float64
    Health         int    // 0-100
    TimeRemaining  time.Duration
    CurrentNow     int    // mA
    Voltage        int    // mV
}

func (m *BatteryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.batteryState = make(map[string]*BatteryInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastStatus = "unknown"
    go m.monitor()
}

func (m *BatteryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBatteryStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BatteryMonitor) checkBatteryStatus() {
    batteries := m.listBatteries()

    for _, battery := range batteries {
        m.processBatteryStatus(battery)
    }
}

func (m *BatteryMonitor) listBatteries() []*BatteryInfo {
    if runtime.GOOS == "darwin" {
        return m.listDarwinBatteries()
    }
    return m.listLinuxBatteries()
}

func (m *BatteryMonitor) listLinuxBatteries() []*BatteryInfo {
    var batteries []*BatteryInfo

    // Read from /sys/class/power_supply
    powerDir := "/sys/class/power_supply"

    entries, err := os.ReadDir(powerDir)
    if err != nil {
        return batteries
    }

    for _, entry := range entries {
        batDir := filepath.Join(powerDir, entry.Name())

        // Check if it's a battery
        typeFile := filepath.Join(batDir, "type")
        typeData, err := os.ReadFile(typeFile)
        if err != nil {
            continue
        }

        if strings.TrimSpace(string(typeData)) != "Battery" {
            continue
        }

        battery := &BatteryInfo{
            Name: entry.Name(),
        }

        // Read status
        statusFile := filepath.Join(batDir, "status")
        statusData, _ := os.ReadFile(statusFile)
        battery.Status = strings.TrimSpace(string(statusData))

        // Read capacity
        capFile := filepath.Join(batDir, "capacity")
        capData, _ := os.ReadFile(capFile)
        battery.Level, _ = strconv.Atoi(strings.TrimSpace(string(capData)))

        // Read energy_full for health calculation
        energyFull, _ := os.ReadFile(filepath.Join(batDir, "energy_full"))
        energyNow, _ := os.ReadFile(filepath.Join(batDir, "energy_now"))
        if len(energyFull) > 0 && len(energyNow) > 0 {
            full, _ := strconv.ParseFloat(strings.TrimSpace(string(energyFull)), 64)
            now, _ := strconv.ParseFloat(strings.TrimSpace(string(energyNow)), 64)
            if full > 0 {
                battery.Health = int((now / full) * 100)
            }
        }

        // Read current and voltage
        currentNow, _ := os.ReadFile(filepath.Join(batDir, "current_now"))
        if len(currentNow) > 0 {
            battery.CurrentNow, _ = strconv.Atoi(strings.TrimSpace(string(currentNow)))
        }

        voltageNow, _ := os.ReadFile(filepath.Join(batDir, "voltage_now"))
        if len(voltageNow) > 0 {
            battery.Voltage, _ = strconv.Atoi(strings.TrimSpace(string(voltageNow)))
        }

        batteries = append(batteries, battery)
    }

    return batteries
}

func (m *BatteryMonitor) listDarwinBatteries() []*BatteryInfo {
    var batteries []*BatteryInfo

    cmd := exec.Command("pmset", "-g", "battery")
    output, err := cmd.Output()
    if err != nil {
        return batteries
    }

    outputStr := string(output)

    // Parse pmset output
    battery := &BatteryInfo{
        Name: "BAT0",
    }

    // Extract status
    statusRe := regexp.MustEach(`Now drawing from '(AC|Battery)'`)
    matches := statusRe.FindStringSubmatch(outputStr)
    if len(matches) >= 2 {
        if matches[1] == "AC" {
            battery.Status = "charging"
        } else {
            battery.Status = "discharging"
        }
    }

    // Extract percentage
    percentRe := regexp.MustEach(`(\d+)%`)
    matches = percentRe.FindStringSubmatch(outputStr)
    if len(matches) >= 2 {
        battery.Level, _ = strconv.Atoi(matches[1])
    }

    // Extract time remaining
    timeRe := regexp.MustEach(`(\d+:\d+)`)
    matches = timeRe.FindStringSubmatch(outputStr)
    if len(matches) >= 2 {
        parts := strings.Split(matches[1], ":")
        if len(parts) == 2 {
            hours, _ := strconv.Atoi(parts[0])
            mins, _ := strconv.Atoi(parts[1])
            battery.TimeRemaining = time.Duration(hours)*time.Hour + time.Duration(mins)*time.Minute
        }
    }

    batteries = append(batteries, battery)

    return batteries
}

func (m *BatteryMonitor) processBatteryStatus(battery *BatteryInfo) {
    lastInfo := m.batteryState[battery.Name]
    lastStatus := m.lastStatus

    if lastInfo == nil {
        m.batteryState[battery.Name] = battery
        m.lastStatus = battery.Status
        return
    }

    // Check for status changes
    if battery.Status != lastStatus {
        m.onBatteryStatusChanged(battery)
        m.lastStatus = battery.Status
    }

    // Check for level changes when discharging
    if battery.Status == "discharging" && lastInfo.Status == "discharging" {
        if battery.Level <= m.config.WarningPercent && lastInfo.Level > m.config.WarningPercent {
            m.onBatteryLow(battery)
        }
        if battery.Level <= m.config.CriticalPercent && lastInfo.Level > m.config.CriticalPercent {
            m.onBatteryCritical(battery)
        }
    }

    // Check for full charge
    if battery.Level == 100 && lastInfo.Level < 100 {
        if m.config.SoundOnFull {
            m.onBatteryFull(battery)
        }
    }

    m.batteryState[battery.Name] = battery
}

func (m *BatteryMonitor) onBatteryStatusChanged(battery *BatteryInfo) {
    switch battery.Status {
    case "charging":
        if m.config.SoundOnCharging {
            m.onChargingStarted(battery)
        }
    case "discharging":
        if m.config.SoundOnDischarging {
            m.onDischargingStarted(battery)
        }
    case "full":
        if m.config.SoundOnFull {
            m.onBatteryFull(battery)
        }
    }
}

func (m *BatteryMonitor) onBatteryLow(battery *BatteryInfo) {
    key := fmt.Sprintf("low:%s", battery.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["low"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BatteryMonitor) onBatteryCritical(battery *BatteryInfo) {
    key := fmt.Sprintf("critical:%s", battery.Name)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *BatteryMonitor) onBatteryFull(battery *BatteryInfo) {
    key := fmt.Sprintf("full:%s", battery.Name)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["full"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *BatteryMonitor) onChargingStarted(battery *BatteryInfo) {
    key := fmt.Sprintf("charging:%s", battery.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["charging"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *BatteryMonitor) onDischargingStarted(battery *BatteryInfo) {
    key := fmt.Sprintf("discharging:%s", battery.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["discharging"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
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
| /sys/class/power_supply | Linux Path | Free | Battery info |
| pmset | System Tool | Free | Power management (macOS) |

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
