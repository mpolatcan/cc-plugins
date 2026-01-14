# Feature: Sound Event Temperature Monitor

Play sounds for system temperature changes and thermal threshold events.

## Summary

Monitor CPU, GPU, and system temperatures, playing sounds for temperature threshold crossings and thermal events.

## Motivation

- Thermal awareness
- Overheating prevention
- Fan speed feedback
- Hardware protection
- Performance throttling alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Temperature Events

| Event | Description | Example |
|-------|-------------|---------|
| Temperature Warning | Temperature above warning | CPU at 80C |
| Temperature Critical | Temperature at critical level | CPU at 95C |
| Temperature Normal | Temperature returned to normal | CPU at 45C |
| Fan Speed Changed | Fan speed increased/decreased | 30% -> 70% |
| Thermal Throttle | Thermal throttling started | CPU throttled |
| Sensor Added | New temperature sensor | Added GPU sensor |

### Configuration

```go
type TemperatureMonitorConfig struct {
    Enabled              bool              `json:"enabled"`
    WarningThreshold     int               `json:"warning_threshold"` // 80 default
    CriticalThreshold    int               `json:"critical_threshold"` // 95 default
    SoundOnWarning       bool              `json:"sound_on_warning"`
    SoundOnCritical      bool              `json:"sound_on_critical"`
    SoundOnNormal        bool              `json:"sound_on_normal"`
    SoundOnFanChange     bool              `json:"sound_on_fan_change"`
    WatchSensors         []string          `json:"watch_sensors"` // "cpu", "gpu", "*"
    Sounds               map[string]string `json:"sounds"`
    PollInterval         int               `json:"poll_interval_sec"` // 5 default
}

type TemperatureEvent struct {
    Sensor      string
    Name        string
    Temperature int // Celsius
    Unit        string // "C", "F"
    EventType   string // "warning", "critical", "normal", "fan", "throttle"
}
```

### Commands

```bash
/ccbell:temp status                   # Show temperature status
/ccbell:temp warning 80               # Set warning threshold
/ccbell:temp critical 95              # Set critical threshold
/ccbell:temp sound warning <sound>
/ccbell:temp sound critical <sound>
/ccbell:temp test                     # Test temperature sounds
```

### Output

```
$ ccbell:temp status

=== Sound Event Temperature Monitor ===

Status: Enabled
Warning: 80C
Critical: 95C
Warning Sounds: Yes
Critical Sounds: Yes

Temperature Sensors:

[1] CPU Core 0
    Current: 72C
    Status: OK
    Sound: bundled:temp-normal

[2] CPU Core 1
    Current: 74C
    Status: OK
    Sound: bundled:temp-normal

[3] GPU Temperature
    Current: 65C
    Status: OK
    Sound: bundled:temp-gpu

[4] NVMe SSD
    Current: 45C
    Status: OK
    Sound: bundled:temp-nvme

Recent Events:
  [1] CPU Core 1: Temperature Warning (5 min ago)
       Temperature rose to 80C
  [2] CPU Core 0: Temperature Normal (10 min ago)
       Temperature returned to normal
  [3] GPU: Fan Speed Changed (1 hour ago)
       Fan speed: 40% -> 65%

Temperature Statistics:
  Avg CPU Temp: 68C
  Max CPU Temp: 85C
  Thermal Throttles: 2

Sound Settings:
  Warning: bundled:temp-warning
  Critical: bundled:temp-critical
  Normal: bundled:temp-normal

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

Temperature monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Temperature Monitor

```go
type TemperatureMonitor struct {
    config          *TemperatureMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    sensorState     map[string]*SensorInfo
    lastEventTime   map[string]time.Time
}

type SensorInfo struct {
    Name        string
    Path        string
    CurrentTemp int
    Status      string // "normal", "warning", "critical"
    LastTemp    int
}

func (m *TemperatureMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sensorState = make(map[string]*SensorInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *TemperatureMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.discoverSensors()
    m.snapshotSensorState()

    for {
        select {
        case <-ticker.C:
            m.checkSensorState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *TemperatureMonitor) discoverSensors() {
    // Try different sensor sources
    if runtime.GOOS == "darwin" {
        m.discoverDarwinSensors()
    } else {
        m.discoverLinuxSensors()
    }
}

func (m *TemperatureMonitor) discoverLinuxSensors() {
    // Check hwmon directory
    hwmonPath := "/sys/class/hwmon"
    entries, err := os.ReadDir(hwmonPath)
    if err != nil {
        return
    }

    for _, entry := range entries {
        hwmonDir := filepath.Join(hwmonPath, entry.Name())
        namePath := filepath.Join(hwmonDir, "name")
        nameData, err := os.ReadFile(namePath)
        if err != nil {
            continue
        }

        sensorName := strings.TrimSpace(string(nameData))

        // Look for temp inputs
        tempDir := hwmonDir
        for i := 1; ; i++ {
            tempPath := filepath.Join(tempDir, fmt.Sprintf("temp%d_input", i))
            if _, err := os.Stat(tempPath); err != nil {
                break
            }

            labelPath := filepath.Join(tempDir, fmt.Sprintf("temp%d_label", i))
            labelData, _ := os.ReadFile(labelPath)
            label := strings.TrimSpace(string(labelData))
            if label == "" {
                label = fmt.Sprintf("%s_temp%d", sensorName, i)
            }

            key := fmt.Sprintf("%s:%d", sensorName, i)
            m.sensorState[key] = &SensorInfo{
                Name: label,
                Path: tempPath,
            }
        }
    }
}

func (m *TemperatureMonitor) discoverDarwinSensors() {
    // Use powermetrics or smc command
    cmd := exec.Command("smc", "-k", "TC0P")
    // This is a placeholder - actual implementation would use SMCKit
}

func (m *TemperatureMonitor) snapshotSensorState() {
    for key, sensor := range m.sensorState {
        temp := m.readTemperature(sensor.Path)
        if temp > 0 {
            sensor.CurrentTemp = temp
            sensor.Status = m.getStatus(temp)
        }
    }
}

func (m *TemperatureMonitor) checkSensorState() {
    for key, sensor := range m.sensorState {
        temp := m.readTemperature(sensor.Path)
        if temp <= 0 {
            continue
        }

        lastTemp := sensor.CurrentTemp
        sensor.CurrentTemp = temp

        newStatus := m.getStatus(temp)
        oldStatus := sensor.Status

        // Check for status changes
        if newStatus != oldStatus {
            if newStatus == "warning" && oldStatus == "normal" {
                m.onTemperatureWarning(key, sensor)
            } else if newStatus == "critical" && oldStatus != "critical" {
                m.onTemperatureCritical(key, sensor)
            } else if newStatus == "normal" && oldStatus != "normal" {
                m.onTemperatureNormal(key, sensor)
            }
        }

        // Check for large temperature changes
        if lastTemp > 0 {
            diff := temp - lastTemp
            if diff >= 10 || diff <= -10 {
                m.onTemperatureChanged(key, sensor, lastTemp)
            }
        }

        sensor.LastTemp = lastTemp
        sensor.Status = newStatus
    }
}

func (m *TemperatureMonitor) readTemperature(path string) int {
    data, err := os.ReadFile(path)
    if err != nil {
        return 0
    }

    // Temperature is in millidegrees
    val, _ := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
    return int(val / 1000)
}

func (m *TemperatureMonitor) getStatus(temp int) string {
    if temp >= m.config.CriticalThreshold {
        return "critical"
    } else if temp >= m.config.WarningThreshold {
        return "warning"
    }
    return "normal"
}

func (m *TemperatureMonitor) onTemperatureWarning(key string, sensor *SensorInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *TemperatureMonitor) onTemperatureCritical(key string, sensor *SensorInfo) {
    if !m.config.SoundOnCritical {
        return
    }

    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *TemperatureMonitor) onTemperatureNormal(key string, sensor *SensorInfo) {
    if !m.config.SoundOnNormal {
        return
    }

    // Only alert when returning from critical, not from warning
    if m.shouldAlert(key+":normal", 5*time.Minute) {
        sound := m.config.Sounds["normal"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *TemperatureMonitor) onTemperatureChanged(key string, sensor *SensorInfo, lastTemp int) {
    // Large temperature change - could indicate issue
    // Optional: add sound for rapid changes
}

func (m *TemperatureMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /sys/class/hwmon/* | Filesystem | Free | Hardware monitoring |
| sensors | System Tool | Free | lm-sensors (optional) |
| powermetrics | System Tool | Free | macOS temperature |

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
| macOS | Supported | Uses powermetrics or SMC |
| Linux | Supported | Uses hwmon sysfs |
