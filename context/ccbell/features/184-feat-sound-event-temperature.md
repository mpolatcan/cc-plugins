# Feature: Sound Event Temperature

Play sounds based on system temperature.

## Summary

Play different sounds when system temperature crosses thresholds.

## Motivation

- Overheating warnings
- Fan noise awareness
- Hardware protection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Temperature Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| CPU High | CPU temperature | > 80°C |
| GPU High | GPU temperature | > 85°C |
| Disk High | Disk temperature | > 60°C |
| Normal | Returned to normal | < 50°C |

### Configuration

```go
type TemperatureConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 30 default
    Thresholds    *TempThresholds   `json:"thresholds"`
    Sounds        map[string]string `json:"sounds"`
}

type TempThresholds struct {
    CPUWarning    float64 `json:"cpu_warning_celsius"`
    CPUCritical   float64 `json:"cpu_critical_celsius"`
    GPUWarning    float64 `json:"gpu_warning_celsius"`
    GPUCritical   float64 `json:"gpu_critical_celsius"`
    DiskWarning   float64 `json:"disk_warning_celsius"`
    DiskCritical  float64 `json:"disk_critical_celsius"`
}

type TemperatureState struct {
    CPU           float64
    GPU           float64
    Disk          float64
    Battery       float64 // If available
    Status        string // "normal", "warning", "critical"
}
```

### Commands

```bash
/ccbell:temp status                 # Show current temperatures
/ccbell:temp sound warning <sound>
/ccbell:temp sound critical <sound>
/ccbell:temp sound normal <sound>
/ccbell:temp threshold cpu 80       # Set CPU warning threshold
/ccbell:temp threshold gpu 85       # Set GPU warning threshold
/ccbell:temp enable                 # Enable temperature monitoring
/ccbell:temp disable                # Disable temperature monitoring
/ccbell:temp test                   # Test temperature sounds
```

### Output

```
$ ccbell:temp status

=== Sound Event Temperature ===

Status: Enabled
Check Interval: 30s

Current Temperatures:
  CPU: 65°C
  GPU: 58°C
  Battery: 42°C

Thresholds:
  CPU Warning: 80°C
  CPU Critical: 90°C
  GPU Warning: 85°C

Sounds:
  Warning: bundled:stop
  Critical: bundled:stop
  Normal: bundled:stop

Status: NORMAL
[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Temperature monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Temperature Monitor

```go
type TemperatureMonitor struct {
    config   *TemperatureConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastStatus string
}

func (m *TemperatureMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *TemperatureMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkTemperature()
        case <-m.stopCh:
            return
        }
    }
}

func (m *TemperatureMonitor) checkTemperature() {
    state, err := m.getTemperature()
    if err != nil {
        log.Debug("Failed to get temperature: %v", err)
        return
    }

    status := m.calculateStatus(state)
    if status != m.lastStatus {
        m.playTempEvent(status)
    }

    m.lastStatus = status
}

func (m *TemperatureMonitor) getTemperature() (*TemperatureState, error) {
    state := &TemperatureState{}

    // macOS: Use powermetrics or smc command
    // macOS SMC: sudo powermetrics -s thermal

    // Linux: Read from thermal zones
    thermalPaths := []string{
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/class/thermal/thermal_zone1/temp",
        "/sys/devices/platform/coretemp.0/temp1_input",
    }

    var cpuTemps []float64
    for _, path := range thermalPaths {
        if data, err := os.ReadFile(path); err == nil {
            if temp, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64); err == nil {
                cpuTemps = append(cpuTemps, temp/1000) // Convert to Celsius
            }
        }
    }

    if len(cpuTemps) > 0 {
        // Average of available sensors
        sum := 0.0
        for _, t := range cpuTemps {
            sum += t
        }
        state.CPU = sum / float64(len(cpuTemps))
    }

    // GPU temperature (NVIDIA)
    if data, err := os.ReadFile("/sys/class/hwmon/hwmon0/temp1_input"); err == nil {
        if temp, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64); err == nil {
            state.GPU = temp / 1000
        }
    }

    return state, nil
}

func (m *TemperatureMonitor) calculateStatus(state *TemperatureState) string {
    if state.CPU >= m.config.Thresholds.CPUCritical {
        return "critical"
    }
    if state.GPU >= m.config.Thresholds.GPUCritical {
        return "critical"
    }
    if state.CPU >= m.config.Thresholds.CPUWarning {
        return "warning"
    }
    if state.GPU >= m.config.Thresholds.GPUWarning {
        return "warning"
    }
    return "normal"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /sys/class/thermal | Filesystem | Free | Linux thermal zones |
| /sys/devices/platform | Filesystem | Free | CPU temperature |
| powermetrics | System Tool | Free | macOS thermal |

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
| macOS | ✅ Supported | Uses powermetrics |
| Linux | ✅ Supported | Uses /sys/class/thermal |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
