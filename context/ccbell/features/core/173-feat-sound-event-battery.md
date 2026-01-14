# Feature: Sound Event Battery

Play sounds based on battery state.

## Summary

Play different sounds based on battery level, charging state, or power source.

## Motivation

- Battery alerts
- Charging notifications
- Power state awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Battery Events

| Event | Trigger | Example |
|-------|---------|---------|
| Low Battery | Below threshold | < 20% |
| Critical Battery | Very low | < 10% |
| Charging Started | Plug in | Any % |
| Charging Complete | 100% | Full |
| Power Source | Switch to AC/DC | On AC |

### Configuration

```go
type BatteryConfig struct {
    Enabled     bool              `json:"enabled"`
    CheckInterval int            `json:"check_interval_sec"` // 60 default
    Sounds      map[string]string `json:"sounds"` // event -> sound
    Thresholds  *BatteryThresholds `json:"thresholds"`
}

type BatteryThresholds struct {
    Low         float64 `json:"low"` // 0.0-1.0, default 0.2
    Critical    float64 `json:"critical"` // 0.0-1.0, default 0.1
    High        float64 `json:"high"` // 0.0-1.0, default 0.8
}
```

### Commands

```bash
/ccbell:battery status              # Show current battery status
/ccbell:battery set low <threshold> # Set low battery threshold (0-1)
/ccbell:battery set critical <threshold>
/ccbell:battery sound low <sound>   # Sound for low battery
/ccbell:battery sound charging <sound>
/ccbell:battery sound complete <sound>
/ccbell:battery enable              # Enable battery monitoring
/ccbell:battery disable             # Disable battery monitoring
/ccbell:battery test                # Test all battery sounds
```

### Output

```
$ ccbell:battery status

=== Sound Event Battery ===

Status: Enabled
Check Interval: 60s

Current State:
  Power Source: AC
  Battery Level: 75%
  Charging: No

Thresholds:
  Low: 20%
  Critical: 10%
  High: 80%

Sounds:
  Low: bundled:stop
  Critical: bundled:stop
  Charging: bundled:stop
  Complete: bundled:stop
  Power Source: bundled:stop

[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Battery monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Battery Monitoring

```go
type BatteryManager struct {
    config   *BatteryConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastState *BatteryState
}

type BatteryState struct {
    Percentage float64
    Charging   bool
    PowerSource string // "AC", "Battery"
}

func (m *BatteryManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})

    go m.monitor()
}

func (m *BatteryManager) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
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

func (m *BatteryManager) checkBattery() {
    state, err := m.getBatteryState()
    if err != nil {
        log.Debug("Failed to get battery state: %v", err)
        return
    }

    if m.lastState == nil {
        m.lastState = state
        return
    }

    // Check for events
    if state.Percentage < m.config.Thresholds.Critical &&
       m.lastState.Percentage >= m.config.Thresholds.Critical {
        m.playBatteryEvent("critical", state)
    } else if state.Percentage < m.config.Thresholds.Low &&
              m.lastState.Percentage >= m.config.Thresholds.Low {
        m.playBatteryEvent("low", state)
    }

    if !m.lastState.Charging && state.Charging {
        m.playBatteryEvent("charging", state)
    } else if m.lastState.Charging && !state.Charging {
        m.playBatteryEvent("discharging", state)
    }

    if state.Percentage >= m.config.Thresholds.High &&
       m.lastState.Percentage < m.config.Thresholds.High {
        m.playBatteryEvent("complete", state)
    }

    m.lastState = state
}

// getBatteryState reads battery info from system
func (m *BatteryManager) getBatteryState() (*BatteryState, error) {
    // macOS: pmset -g batt
    cmd := exec.Command("pmset", "-g", "batt")
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    // Parse output like: "Now drawing from 'AC Power'\n 100%; charged; 0:00 remaining"
    lines := strings.Split(string(output), "\n")
    // ... parsing logic

    return &BatteryState{
        Percentage: percentage,
        Charging:   charging,
        PowerSource: powerSource,
    }, nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pmset | System Tool | Free | macOS battery info |
| /sys/class/power_supply/* | Filesystem | Free | Linux battery info |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses pmset |
| Linux | ✅ Supported | Uses /sys/class/power_supply |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
