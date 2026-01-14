# Feature: Sound Event Battery Health Monitor

Play sounds for battery health status and charging events.

## Summary

Monitor battery health, charging status, and battery degradation, playing sounds for battery events.

## Motivation

- Charging completion alerts
- Battery degradation warnings
- Health status updates
- Power adapter detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Battery Health Events

| Event | Description | Example |
|-------|-------------|---------|
| Charging Complete | Fully charged | 100% |
| Low Battery | Below 20% | 18% remaining |
| Critical Battery | Below 10% | 8% remaining |
| Health Degraded | Capacity dropped | 80% of original |
| Adapter Connected | Charger plugged | AC attached |
| Adapter Disconnected | Charger unplugged | AC detached |

### Configuration

```go
type BatteryHealthMonitorConfig struct {
    Enabled              bool              `json:"enabled"`
    LowThreshold         int               `json:"low_threshold_percent"` // 20 default
    CriticalThreshold    int               `json:"critical_threshold_percent"` // 10 default
    HealthThreshold      int               `json:"health_threshold_percent"` // 80 default
    SoundOnLow           bool              `json:"sound_on_low"`
    SoundOnCritical      bool              `json:"sound_on_critical"`
    SoundOnCharged       bool              `json:"sound_on_charged"`
    SoundOnHealthDegraded bool             `json:"sound_on_health_degraded"`
    Sounds               map[string]string `json:"sounds"`
    PollInterval         int               `json:"poll_interval_sec"` // 30 default
}

type BatteryHealthEvent struct {
    Percentage      int
    HealthPercent   int
    IsCharging      bool
    IsACConnected   bool
    Temperature     float64
    EventType       string // "low", "critical", "charged", "health_degraded"
}
```

### Commands

```bash
/ccbell:battery-health status              # Show battery health status
/ccbell:battery-health low 20              # Set low threshold
/ccbell:battery-health sound low <sound>
/ccbell:battery-health sound critical <sound>
/ccbell:battery-health test                # Test battery sounds
```

### Output

```
$ ccbell:battery-health status

=== Sound Event Battery Health Monitor ===

Status: Enabled
Low Threshold: 20%
Critical Threshold: 10%
Health Threshold: 80%

Battery Information:
  Current: 45%
  Health: 92% (Good)
  Temperature: 32C
  Cycles: 245
  Design Capacity: 5100 mAh
  Current Capacity: 4692 mAh

  [=======.............] 45%

Status: Discharging

Recent Events:
  [1] Low Battery (2 hours ago)
       18% remaining
  [2] Adapter Connected (5 hours ago)
  [3] Fully Charged (1 day ago)

Health Trends:
  - 1 month ago: 94%
  - 3 months ago: 96%
  - 6 months ago: 98%

Sound Settings:
  Low: bundled:stop
  Critical: bundled:stop
  Charged: bundled:stop
  Health Degraded: bundled:stop

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Battery health monitoring doesn't play sounds directly:
- Monitoring feature using battery information tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Battery Health Monitor

```go
type BatteryHealthMonitor struct {
    config            *BatteryHealthMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    lastPercentage    int
    lastHealthPercent int
    lastChargingState bool
    lastLowTime       time.Time
    lastCriticalTime  time.Time
}
```

```go
func (m *BatteryHealthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *BatteryHealthMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBattery()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BatteryHealthMonitor) checkBattery() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinBattery()
    } else {
        m.checkLinuxBattery()
    }
}

func (m *BatteryHealthMonitor) checkDarwinBattery() {
    // Use pmset to get battery info
    cmd := exec.Command("pmset", "-g", "battery")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    info := m.parseDarwinBatteryOutput(string(output))

    m.evaluateBattery(info)
}

func (m *BatteryHealthMonitor) parseDarwinBatteryOutput(output string) *BatteryHealthEvent {
    info := &BatteryHealthEvent{}

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, "\t", 2)
        if len(parts) < 2 {
            continue
        }

        key := strings.TrimSpace(parts[0])
        value := strings.TrimSpace(parts[1])

        switch key {
        case "CurrentCapacity":
            if val, err := strconv.Atoi(value); err == nil {
                info.Percentage = val
            }
        case "DesignCapacity":
            if val, err := strconv.Atoi(value); err == nil {
                current, _ := strconv.Atoi(parts[1])
                if val > 0 {
                    info.HealthPercent = current * 100 / val
                }
            }
        case "IsCharging":
            info.IsCharging = (value == "Yes")
        case "AC Power":
            info.IsACConnected = (value == "Yes")
        case "Temperature":
            if val, err := strconv.ParseFloat(value, 64); err == nil {
                info.Temperature = val
            }
        }
    }

    // Calculate percentage from current/max
    if info.Percentage == 0 {
        // Try alternative parsing
        for _, line := range lines {
            if strings.Contains(line, "%") {
                re := regexp.MustCompile(`(\d+)%`)
                match := re.FindStringSubmatch(line)
                if len(match) >= 2 {
                    info.Percentage, _ = strconv.Atoi(match[1])
                }
            }
        }
    }

    return info
}

func (m *BatteryHealthMonitor) checkLinuxBattery() {
    // Read from /sys/class/power_supply
    batteryPath := "/sys/class/power_supply/BAT0"

    if _, err := os.Stat(batteryPath); os.IsNotExist(err) {
        batteryPath = "/sys/class/power_supply/BAT1"
    }

    info := &BatteryHealthEvent{}

    // Read current charge
    if data, err := os.ReadFile(filepath.Join(batteryPath, "charge_now")); err == nil {
        if val, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil {
            info.Percentage = val
        }
    }

    // Read charge full
    if data, err := os.ReadFile(filepath.Join(batteryPath, "charge_full")); err == nil {
        if full, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil {
            if val, err := os.ReadFile(filepath.Join(batteryPath, "charge_now")); err == nil {
                if current, err := strconv.Atoi(strings.TrimSpace(string(val))); err == nil && full > 0 {
                    info.Percentage = current * 100 / full
                }
            }
        }
    }

    // Read health
    if data, err := os.ReadFile(filepath.Join(batteryPath, "health")); err == nil {
        health := strings.TrimSpace(string(data))
        if health != "Good" && health != "Normal" {
            info.HealthPercent = 80 // Assume degraded
        }
    }

    // Read status
    if data, err := os.ReadFile(filepath.Join(batteryPath, "status")); err == nil {
        status := strings.TrimSpace(string(data))
        info.IsCharging = (status == "Charging")
    }

    // Read AC connection
    if data, err := os.ReadFile("/sys/class/power_supply/AC/online"); err == nil {
        info.IsACConnected = strings.TrimSpace(string(data)) == "1"
    }

    m.evaluateBattery(info)
}

func (m *BatteryHealthMonitor) evaluateBattery(info *BatteryHealthEvent) {
    // Check percentage thresholds
    if info.Percentage <= m.config.CriticalThreshold {
        if m.lastPercentage > m.config.CriticalThreshold {
            m.onCriticalBattery(info)
        }
    } else if info.Percentage <= m.config.LowThreshold {
        if m.lastPercentage > m.config.LowThreshold {
            m.onLowBattery(info)
        }
    }

    // Check charging completion
    if info.IsCharging && !m.lastChargingState && info.Percentage >= 95 {
        m.onChargingComplete(info)
    }

    // Check AC connection changes
    if info.IsACConnected != m.lastChargingState && !info.IsCharging {
        if info.IsACConnected {
            m.onAdapterConnected(info)
        } else {
            m.onAdapterDisconnected(info)
        }
    }

    // Check health degradation
    if info.HealthPercent < m.config.HealthThreshold &&
       m.lastHealthPercent >= m.config.HealthThreshold {
        m.onHealthDegraded(info)
    }

    // Update last state
    m.lastPercentage = info.Percentage
    m.lastHealthPercent = info.HealthPercent
    m.lastChargingState = info.IsCharging
}

func (m *BatteryHealthMonitor) onLowBattery(info *BatteryHealthEvent) {
    if !m.config.SoundOnLow {
        return
    }

    if time.Since(m.lastLowTime) < 1*time.Hour {
        return
    }

    m.lastLowTime = time.Now()

    sound := m.config.Sounds["low"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BatteryHealthMonitor) onCriticalBattery(info *BatteryHealthEvent) {
    if !m.config.SoundOnCritical {
        return
    }

    if time.Since(m.lastCriticalTime) < 30*time.Minute {
        return
    }

    m.lastCriticalTime = time.Now()

    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *BatteryHealthMonitor) onChargingComplete(info *BatteryHealthEvent) {
    if !m.config.SoundOnCharged {
        return
    }

    sound := m.config.Sounds["charged"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BatteryHealthMonitor) onHealthDegraded(info *BatteryHealthEvent) {
    if !m.config.SoundOnHealthDegraded {
        return
    }

    sound := m.config.Sounds["health_degraded"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *BatteryHealthMonitor) onAdapterConnected(info *BatteryHealthEvent) {
    sound := m.config.Sounds["adapter_connected"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *BatteryHealthMonitor) onAdapterDisconnected(info *BatteryHealthEvent) {
    sound := m.config.Sounds["adapter_disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pmset | System Tool | Free | macOS power management |
| /sys/class/power_supply | File | Free | Linux battery info |

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
| Windows | Not Supported | ccbell only supports macOS/Linux |
