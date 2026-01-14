# Feature: Sound Event Battery Monitor

Play sounds for battery and power events.

## Summary

Monitor battery levels and power status, playing sounds for critical events like low battery, charging complete, or power adapter connected.

## Motivation

- Laptop users need battery awareness
- Prevent unexpected shutdowns
- Charging status notifications
- Power efficiency awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Battery Events

| Event | Description | Example |
|-------|-------------|---------|
| Low Battery | Battery below threshold | Below 20% |
| Critical Battery | Battery critically low | Below 10% |
| Charging | Power adapter connected | AC connected |
| Fully Charged | Battery at 100% | Charging complete |
| Power Adapter | AC power status change | Adapter unplugged |

### Configuration

```go
type BatteryMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    LowThreshold  int               `json:"low_threshold"` // 20 default
    CriticalThreshold int           `json:"critical_threshold"` // 10 default
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 60 default
    NotifyOnce    bool              `json:"notify_once"` // Don't repeat
}

type BatteryStatus struct {
    Percentage int
    Charging   bool
    ACConnected bool
    TimeRemaining time.Duration
}
```

### Commands

```bash
/ccbell:battery status              # Show battery status
/ccbell:battery low <percent>       # Set low threshold
/ccbell:battery critical <percent>  # Set critical threshold
/ccbell:battery sound low <sound>
/ccbell:battery sound critical <sound>
/ccbell:battery sound charging <sound>
/ccbell:battery sound full <sound>
ccbell:battery test                 # Test battery sounds
```

### Output

```
$ ccbell:battery status

=== Sound Event Battery Monitor ===

Status: Enabled
Low Threshold: 20%
Critical Threshold: 10%
Poll Interval: 60s

Current Status:
  Percentage: 45%
  Charging: Yes
  AC Connected: Yes
  Time Remaining: 2h 15m

Sound Settings:
  Low: bundled:stop
  Critical: bundled:stop
  Charging: bundled:stop
  Full: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Battery monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Battery Monitor

```go
type BatteryMonitor struct {
    config     *BatteryMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastStatus *BatteryStatus
    notifiedLow bool
}

func (m *BatteryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.notifiedLow = false
    go m.monitor()
}

func (m *BatteryMonitor) monitor() {
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

func (m *BatteryMonitor) checkBattery() {
    status := m.getBatteryStatus()
    m.evaluateStatus(status)
}

func (m *BatteryMonitor) getBatteryStatus() *BatteryStatus {
    status := &BatteryStatus{}

    // macOS: pmset -g batt
    if runtime.GOOS == "darwin" {
        return m.getMacOSBatteryStatus()
    }

    // Linux: /sys/class/power_supply/
    if runtime.GOOS == "linux" {
        return m.getLinuxBatteryStatus()
    }

    return status
}

func (m *BatteryMonitor) getMacOSBatteryStatus() *BatteryStatus {
    cmd := exec.Command("pmset", "-g", "batt")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    status := &BatteryStatus{}

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "%") {
            // Parse: "Now drawing from 'AC Power' - 100%; 15:00 remaining"
            parts := strings.Fields(line)
            for i, part := range parts {
                if part == "%" && i > 0 {
                    pct, _ := strconv.Atoi(strings.TrimSuffix(parts[i-1], "%"))
                    status.Percentage = pct
                }
            }
        }

        if strings.Contains(line, "discharging") {
            status.Charging = false
            status.ACConnected = false
        } else if strings.Contains(line, "charging") {
            status.Charging = true
            status.ACConnected = true
        } else if strings.Contains(line, "AC Power") {
            status.ACConnected = true
            status.Charging = false
        }
    }

    return status
}

func (m *BatteryMonitor) getLinuxBatteryStatus() *BatteryStatus {
    status := &BatteryStatus{}

    // Read battery capacity
    capacityPath := "/sys/class/power_supply/BAT0/capacity"
    if data, err := os.ReadFile(capacityPath); err == nil {
        pct, _ := strconv.Atoi(strings.TrimSpace(string(data)))
        status.Percentage = pct
    }

    // Check charging status
    statusPath := "/sys/class/power_supply/BAT0/status"
    if data, err := os.ReadFile(statusPath); err == nil {
        statusText := strings.TrimSpace(string(data))
        status.Charging = strings.Contains(statusText, "Charging")
        status.ACConnected = statusText != "Discharging"
    }

    return status
}

func (m *BatteryMonitor) evaluateStatus(status *BatteryStatus) {
    if status == nil || m.lastStatus == nil {
        m.lastStatus = status
        return
    }

    // Check charging state changes
    if status.ACConnected && !m.lastStatus.ACConnected {
        m.playSound("charging")
        m.notifiedLow = false
    } else if !status.ACConnected && m.lastStatus.ACConnected {
        m.playSound("power_adapter")
    }

    // Check fully charged
    if status.Charging && status.Percentage >= 100 && m.lastStatus.Percentage < 100 {
        m.playSound("full")
    }

    // Check low battery
    if !status.Charging && status.Percentage <= m.config.LowThreshold {
        if !m.notifiedLow || status.Percentage <= m.config.CriticalThreshold {
            if status.Percentage <= m.config.CriticalThreshold {
                m.playSound("critical")
                m.notifiedLow = true
            } else if !m.notifiedLow {
                m.playSound("low")
                m.notifiedLow = true
            }
        }
    } else if status.Percentage > m.config.LowThreshold {
        m.notifiedLow = false
    }

    m.lastStatus = status
}

func (m *BatteryMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pmset | System Tool | Free | macOS power management |
| /sys/class/power_supply | File System | Free | Linux battery info |

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
| macOS | Supported | Uses pmset command |
| Linux | Supported | Uses sysfs power_supply |
| Windows | Not Supported | ccbell only supports macOS/Linux |
