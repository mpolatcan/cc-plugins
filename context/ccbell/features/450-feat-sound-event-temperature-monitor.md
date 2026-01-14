# Feature: Sound Event Temperature Monitor

Play sounds for temperature threshold breaches and thermal throttling events.

## Summary

Monitor hardware temperature sensors (CPU, GPU, disk, ambient) for overheating and thermal throttling, playing sounds for temperature events.

## Motivation

- Thermal awareness
- Hardware protection
- Performance monitoring
- Fan noise awareness
- Prevent hardware damage

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
| High Temperature | Above warning threshold | > 70C |
| Critical Temperature | Above critical threshold | > 85C |
| Thermal Throttling | CPU throttled | throttled |
| Fan Speed High | Fan running fast | > 4000 RPM |
| Temperature Normal | Back to normal | < 50C |
| Sensor Error | Sensor read error | no data |

### Configuration

```go
type TemperatureMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchSensors      []string          `json:"watch_sensors"` // "cpu", "gpu", "disk", "*"
    WarningTemp       int               `json:"warning_temp_c"` // 70 default
    CriticalTemp      int               `json:"critical_temp_c"` // 85 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnNormal     bool              `json:"sound_on_normal"`
    SoundOnThrottle   bool              `json:"sound_on_throttle"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:temp status                 # Show temperature status
/ccbell:temp add cpu                # Add sensor to watch
/ccbell:temp warning 70             # Set warning threshold
/ccbell:temp sound warning <sound>
/ccbell:temp test                   # Test temperature sounds
```

### Output

```
$ ccbell:temp status

=== Sound Event Temperature Monitor ===

Status: Enabled
Warning: 70C
Critical: 85C

Sensor Status:

[1] CPU Core 0
    Temperature: 65C
    Status: NORMAL
    Sound: bundled:temp-cpu

[2] CPU Core 1
    Temperature: 68C
    Status: NORMAL
    Sound: bundled:temp-cpu

[3] GPU Temperature
    Temperature: 72C *** WARNING ***
    Status: HIGH
    Sound: bundled:temp-gpu *** WARNING ***

[4] NVMe Disk
    Temperature: 45C
    Status: NORMAL
    Sound: bundled:temp-disk

[5] Ambient
    Temperature: 25C
    Status: NORMAL
    Sound: bundled:temp-ambient

Recent Events:

[1] GPU Temperature: High Warning (5 min ago)
       72C > 70C threshold
       Sound: bundled:temp-warning
  [2] CPU Core 0: Back to Normal (1 hour ago)
       65C < 70C
       Sound: bundled:temp-normal
  [3] GPU Temperature: Critical (2 hours ago)
       88C > 85C threshold
       Sound: bundled:temp-critical

Temperature Statistics:
  Total Sensors: 5
  Normal: 4
  Warning: 1
  Critical: 0

Sound Settings:
  Warning: bundled:temp-warning
  Critical: bundled:temp-critical
  Normal: bundled:temp-normal
  Throttle: bundled:temp-throttle

[Configure] [Add Sensor] [Test All]
```

---

## Audio Player Compatibility

Temperature monitoring doesn't play sounds directly:
- Monitoring feature using powermetrics, sensors, vcgencmd
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Temperature Monitor

```go
type TemperatureMonitor struct {
    config        *TemperatureMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    sensorState   map[string]*SensorInfo
    lastEventTime map[string]time.Time
}

type SensorInfo struct {
    Name        string
    Type        string // "cpu", "gpu", "disk", "ambient"
    Temperature float64
    Status      string // "normal", "warning", "critical"
    Throttled   bool
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

func (m *TemperatureMonitor) snapshotSensorState() {
    m.checkSensorState()
}

func (m *TemperatureMonitor) checkSensorState() {
    // Try different methods based on platform
    m.checkMacOSTemperature()
    m.checkLinuxTemperature()
}

func (m *TemperatureMonitor) checkMacOSTemperature() {
    // Use powermetrics on macOS
    cmd := exec.Command("sudo", "powermetrics", "--samplers", "cpu_power", "-n", "1")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(strings.ToLower(line), "cpu") && strings.Contains(line, "C") {
            temp := m.parseTemperature(line)
            if temp > 0 {
                info := &SensorInfo{
                    Name:        "CPU",
                    Type:        "cpu",
                    Temperature: temp,
                    Status:      m.calculateStatus(temp),
                }
                m.processSensorStatus(info)
            }
        }
    }
}

func (m *TemperatureMonitor) checkLinuxTemperature() {
    // Try sensors command (lm-sensors)
    cmd := exec.Command("sensors")
    output, err := cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "+") && strings.Contains(line, "C") {
                temp := m.parseTemperature(line)
                if temp > 0 {
                    sensorName := m.extractSensorName(line)
                    info := &SensorInfo{
                        Name:        sensorName,
                        Type:        m.guessSensorType(sensorName),
                        Temperature: temp,
                        Status:      m.calculateStatus(temp),
                    }
                    m.processSensorStatus(info)
                }
            }
        }
    }

    // Try reading from thermal zones directly
    thermalPaths := []string{
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/class/thermal/thermal_zone1/temp",
    }

    for _, path := range thermalPaths {
        data, err := os.ReadFile(path)
        if err == nil {
            tempStr := strings.TrimSpace(string(data))
            tempMilli, _ := strconv.ParseInt(tempStr, 10, 64)
            temp := float64(tempMilli) / 1000.0

            info := &SensorInfo{
                Name:        path,
                Type:        "thermal",
                Temperature: temp,
                Status:      m.calculateStatus(temp),
            }
            m.processSensorStatus(info)
        }
    }
}

func (m *TemperatureMonitor) parseTemperature(line string) float64 {
    // Match patterns like "65.0C", "72°C", "+68.5°C"
    re := regexp.MustEach(`([+-]?\d+\.?\d*)\s*°?[Cc]`)
    matches := re.FindStringSubmatch(line)
    if len(matches) >= 2 {
        temp, _ := strconv.ParseFloat(matches[1], 64)
        return temp
    }
    return 0
}

func (m *TemperatureMonitor) extractSensorName(line string) string {
    // Extract sensor name before temperature
    re := regexp.MustEach(`^([^:]+):`)
    matches := re.FindStringSubmatch(line)
    if len(matches) >= 2 {
        return strings.TrimSpace(matches[1])
    }
    return "unknown"
}

func (m *TemperatureMonitor) guessSensorType(name string) string {
    nameLower := strings.ToLower(name)
    if strings.Contains(nameLower, "core") || strings.Contains(nameLower, "cpu") {
        return "cpu"
    }
    if strings.Contains(nameLower, "gpu") || strings.Contains(nameLower, "radeon") || strings.Contains(nameLower, "nvidia") {
        return "gpu"
    }
    if strings.Contains(nameLower, "disk") || strings.Contains(nameLower, "nvme") || strings.Contains(nameLower, "hdd") {
        return "disk"
    }
    if strings.Contains(nameLower, "ambient") || strings.Contains(nameLower, "env") {
        return "ambient"
    }
    return "other"
}

func (m *TemperatureMonitor) calculateStatus(temp float64) string {
    if temp >= float64(m.config.CriticalTemp) {
        return "critical"
    }
    if temp >= float64(m.config.WarningTemp) {
        return "warning"
    }
    return "normal"
}

func (m *TemperatureMonitor) processSensorStatus(info *SensorInfo) {
    if !m.shouldWatchSensor(info.Type) {
        return
    }

    lastInfo := m.sensorState[info.Name]

    if lastInfo == nil {
        m.sensorState[info.Name] = info
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "warning":
            if m.config.SoundOnWarning && m.shouldAlert(info.Name+"warning", 5*time.Minute) {
                m.onHighTemperature(info)
            }
        case "critical":
            if m.config.SoundOnCritical && m.shouldAlert(info.Name+"critical", 2*time.Minute) {
                m.onCriticalTemperature(info)
            }
        case "normal":
            if lastInfo.Status != "normal" && m.config.SoundOnNormal {
                m.onTemperatureNormal(info)
            }
        }
    }

    m.sensorState[info.Name] = info
}

func (m *TemperatureMonitor) shouldWatchSensor(sensorType string) bool {
    for _, sensor := range m.config.WatchSensors {
        if sensor == "*" || sensor == sensorType {
            return true
        }
    }
    return false
}

func (m *TemperatureMonitor) onHighTemperature(info *SensorInfo) {
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *TemperatureMonitor) onCriticalTemperature(info *SensorInfo) {
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *TemperatureMonitor) onTemperatureNormal(info *SensorInfo) {
    sound := m.config.Sounds["normal"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *TemperatureMonitor) onThermalThrottling(info *SensorInfo) {
    sound := m.config.Sounds["throttle"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
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
| powermetrics | System Tool | Free | macOS power metrics |
| sensors | System Tool | Free | lm-sensors package |
| vcgencmd | System Tool | Free | Raspberry Pi temperature |

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
| macOS | Supported | Uses powermetrics |
| Linux | Supported | Uses sensors, /sys/class/thermal |
