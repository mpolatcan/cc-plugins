# Feature: Sound Event Hardware Temperature Monitor

Play sounds for hardware temperature thresholds and thermal events.

## Summary

Monitor hardware temperatures (CPU, GPU, disk, ambient), playing sounds when temperatures exceed thresholds.

## Motivation

- Overheating prevention
- Hardware protection alerts
- Fan speed warnings
- Thermal throttling detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Hardware Temperature Events

| Event | Description | Example |
|-------|-------------|---------|
| High Temp | Temp > 80C | CPU at 85C |
| Critical Temp | Temp > 95C | CPU at 97C |
| Thermal Throttling | CPU throttled | Performance reduced |
| Fan Speed High | Fan > 80% | Cooling max |

### Configuration

```go
type HardwareTemperatureMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    CPUWarningTemp     int               `json:"cpu_warning_temp_c"` // 80 default
    CPUCriticalTemp    int               `json:"cpu_critical_temp_c"` // 95 default
    GPUWarningTemp     int               `json:"gpu_warning_temp_c"` // 75 default
    GPUCriticalTemp    int               `json:"gpu_critical_temp_c"` // 90 default
    DiskWarningTemp    int               `json:"disk_warning_temp_c"` // 50 default
    SoundOnWarning     bool              `json:"sound_on_warning"]
    SoundOnCritical    bool              `json:"sound_on_critical"]
    SoundOnThrottling  bool              `json:"sound_on_throttling"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type HardwareTemperatureEvent struct {
    Component   string // "cpu", "gpu", "disk", "ambient"
    Temperature float64 // Celsius
    Throttled   bool
    EventType   string // "warning", "critical", "throttling"
}
```

### Commands

```bash
/ccbell:temp status                  # Show temperature status
/ccbell:temp set-cpu-warning 80      # Set CPU warning temp
/ccbell:temp sound warning <sound>
/ccbell:temp sound critical <sound>
/ccbell:temp test                    # Test temp sounds
```

### Output

```
$ ccbell:temp status

=== Sound Event Hardware Temperature Monitor ===

Status: Enabled
CPU Warning: 80C
CPU Critical: 95C
GPU Warning: 75C
GPU Critical: 90C

Current Temperatures:

[1] CPU Core 0
    Temperature: 72C
    Status: OK
    Throttled: No
    Sound: bundled:stop

[2] CPU Core 1
    Temperature: 74C
    Status: OK
    Throttled: No
    Sound: bundled:stop

[3] GPU
    Temperature: 65C
    Status: OK
    Throttled: No
    Sound: bundled:stop

[4] NVMe Drive
    Temperature: 42C
    Status: OK
    Sound: bundled:stop

  [CPU========..........] 72C
  [GPU======............] 65C

Recent Events:
  [1] CPU Core 0: High Temperature (30 min ago)
       82C
  [2] CPU Core 1: High Temperature (1 hour ago)
       81C
  [3] GPU: Thermal Throttling (2 days ago)

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Throttling: bundled:stop

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Hardware temperature monitoring doesn't play sounds directly:
- Monitoring feature using hardware sensors
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Hardware Temperature Monitor

```go
type HardwareTemperatureMonitor struct {
    config              *HardwareTemperatureMonitorConfig
    player              *audio.Player
    running             bool
    stopCh              chan struct{}
    sensorState         map[string]*SensorStatus
    lastWarningTime     map[string]time.Time
    lastCriticalTime    map[string]time.Time
}

type SensorStatus struct {
    Component   string
    Temperature float64
    Throttled   bool
    LastCheck   time.Time
}
```

```go
func (m *HardwareTemperatureMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sensorState = make(map[string]*SensorStatus)
    m.lastWarningTime = make(map[string]time.Time)
    m.lastCriticalTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *HardwareTemperatureMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkTemperatures()
        case <-m.stopCh:
            return
        }
    }
}

func (m *HardwareTemperatureMonitor) checkTemperatures() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinTemperatures()
    } else {
        m.checkLinuxTemperatures()
    }
}

func (m *HardwareTemperatureMonitor) checkDarwinTemperatures() {
    // Use powermetrics or iStats
    cmd := exec.Command("powermetrics", "-s", "cpu_power", "-n", "1")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePowerMetricsOutput(string(output))

    // Also try using iStats if available
    cmd = exec.Command("istats", "all")
    output, err = cmd.Output()
    if err == nil {
        m.parseIStatsOutput(string(output))
    }
}

func (m *HardwareTemperatureMonitor) checkLinuxTemperatures() {
    // Read from thermal zones
    thermalPath := "/sys/class/thermal"

    entries, err := os.ReadDir(thermalPath)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !strings.HasPrefix(entry.Name(), "thermal_zone") {
            continue
        }

        zonePath := filepath.Join(thermalPath, entry.Name())

        // Read temperature
        tempFile := filepath.Join(zonePath, "temp")
        data, err := os.ReadFile(tempFile)
        if err != nil {
            continue
        }

        tempStr := strings.TrimSpace(string(data))
        temp, _ := strconv.ParseFloat(tempStr, 64)
        tempCelsius := temp / 1000

        // Determine component type
        typeFile := filepath.Join(zonePath, "type")
        if typeData, err := os.ReadFile(typeFile); err == nil {
            sensorType := strings.TrimSpace(string(typeData))
            component := m.getComponentFromType(sensorType)
            m.evaluateTemperature(component, tempCelsius)
        }
    }
}

func (m *HardwareTemperatureMonitor) getComponentFromType(sensorType string) string {
    sensorType = strings.ToLower(sensorType)
    if strings.Contains(sensorType, "cpu") {
        return "cpu"
    } else if strings.Contains(sensorType, "gpu") || strings.Contains(sensorType, "显卡") {
        return "gpu"
    } else if strings.Contains(sensorType, "disk") || strings.Contains(sensorType, "nvme") {
        return "disk"
    }
    return "other"
}

func (m *HardwareTemperatureMonitor) parsePowerMetricsOutput(output string) {
    // Parse powermetrics output for CPU temperature
    re := regexp.MustCompile(`CPU die temperature: (\d+\.\d+)`)
    match := re.FindStringSubmatch(output)
    if len(match) >= 2 {
        if temp, err := strconv.ParseFloat(match[1], 64); err == nil {
            m.evaluateTemperature("cpu", temp)
        }
    }
}

func (m *HardwareTemperatureMonitor) parseIStatsOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        // Parse lines like "CPU Temperature: 72.0C"
        re := regexp.MustCompile(`(\w+)\s+Temperature:\s+(\d+\.?\d*)C`)
        match := re.FindStringSubmatch(line)
        if len(match) >= 3 {
            component := strings.ToLower(match[1])
            if temp, err := strconv.ParseFloat(match[2], 64); err == nil {
                m.evaluateTemperature(component, temp)
            }
        }
    }
}

func (m *HardwareTemperatureMonitor) evaluateTemperature(component string, temp float64) {
    key := component
    lastState := m.sensorState[key]

    event := &SensorStatus{
        Component:   component,
        Temperature: temp,
        LastCheck:   time.Now(),
    }

    if lastState == nil {
        m.sensorState[key] = event
        return
    }

    // Determine threshold based on component
    warningThreshold := m.getWarningThreshold(component)
    criticalThreshold := m.getCriticalThreshold(component)

    // Check for critical temperature
    if temp >= criticalThreshold {
        if lastState.Temperature < criticalThreshold {
            m.onCriticalTemperature(component, temp)
        }
    } else if temp >= warningThreshold {
        if lastState.Temperature < warningThreshold {
            m.onHighTemperature(component, temp)
        }
    }

    m.sensorState[key] = event
}

func (m *HardwareTemperatureMonitor) getWarningThreshold(component string) int {
    switch component {
    case "cpu":
        return m.config.CPUWarningTemp
    case "gpu":
        return m.config.GPUWarningTemp
    case "disk":
        return m.config.DiskWarningTemp
    default:
        return 80
    }
}

func (m *HardwareTemperatureMonitor) getCriticalThreshold(component string) int {
    switch component {
    case "cpu":
        return m.config.CPUCriticalTemp
    case "gpu":
        return m.config.GPUCriticalTemp
    case "disk":
        return m.config.DiskWarningTemp + 10
    default:
        return 95
    }
}

func (m *HardwareTemperatureMonitor) onHighTemperature(component string, temp float64) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%s", component)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *HardwareTemperatureMonitor) onCriticalTemperature(component string, temp float64) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("critical:%s", component)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *HardwareTemperatureMonitor) onThermalThrottling(component string) {
    if !m.config.SoundOnThrottling {
        return
    }

    sound := m.config.Sounds["throttling"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *HardwareTemperatureMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastWarningTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastWarningTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| powermetrics | System Tool | Free | macOS power metrics |
| iStats | External Tool | Free | macOS sensor info |
| /sys/class/thermal | File | Free | Linux thermal zones |

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
| macOS | Supported | Uses powermetrics, iStats |
| Linux | Supported | Uses /sys/class/thermal |
| Windows | Not Supported | ccbell only supports macOS/Linux |
