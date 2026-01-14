# Feature: Sound Event System Fan Monitor

Play sounds for fan speed changes, temperature thresholds, and cooling system alerts.

## Summary

Monitor system fan speeds, temperature sensors, and cooling system status, playing sounds for fan events.

## Motivation

- Thermal management awareness
- Fan speed alerts
- Overheating prevention
- Hardware protection
- Performance throttling

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Fan Events

| Event | Description | Example |
|-------|-------------|---------|
| Fan Speed High | RPM > threshold | > 4000 |
| Fan Speed Low | RPM < threshold | < 500 |
| Fan Failed | Fan stopped | 0 RPM |
| Temperature High | Temp > threshold | > 80C |
| Temperature Critical | Very high temp | > 90C |
| Thermal Throttled | CPU throttled | 80% max |

### Configuration

```go
type SystemFanMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchFans         []string          `json:"watch_fans"` // "CPU Fan", "GPU Fan", "*"
    SpeedThreshold    int               `json:"speed_threshold"` // 4000 RPM
    TempThreshold     int               `json:"temp_threshold"` // 80C
    CriticalTemp      int               `json:"critical_temp"` // 90C
    SoundOnHighSpeed  bool              `json:"sound_on_high_speed"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnTemp       bool              `json:"sound_on_temp"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:fan status                     # Show fan status
/ccbell:fan add "CPU Fan"              # Add fan to watch
/ccbell:fan speed 4000                 # Set speed threshold
/ccbell:fan temp 80                    # Set temp threshold
/ccbell:fan sound high <sound>
/ccbell:fan sound failed <sound>
/ccbell:fan test                       # Test fan sounds
```

### Output

```
$ ccbell:fan status

=== Sound Event System Fan Monitor ===

Status: Enabled
Speed Threshold: 4000 RPM
Temp Threshold: 80C
High Speed Sounds: Yes
Failed Sounds: Yes

Fan Status:

[1] CPU Fan (pwm1)
    Speed: 3200 RPM (65%)
    Status: NORMAL
    Temperature: 55C
    Sound: bundled:fan-cpu

[2] GPU Fan (pwm2)
    Speed: 4500 RPM (85%)
    Status: HIGH
    Temperature: 72C
    Sound: bundled:fan-gpu *** WARNING ***

[3] Case Fan 1 (pwm3)
    Speed: 1200 RPM (40%)
    Status: NORMAL
    Temperature: 42C
    Sound: bundled:fan-case1

[4] Case Fan 2 (pwm4)
    Speed: 0 RPM (0%)
    Status: FAILED
    Temperature: 45C
    Sound: bundled:fan-case2 *** FAILED ***

Temperature Sensors:

  CPU Core: 55C (Normal)
  GPU Core: 72C (Normal)
  Motherboard: 42C (Normal)
  NVMe: 48C (Normal)

Recent Events:
  [1] GPU Fan: High Speed (5 min ago)
       4500 > 4000 RPM threshold
  [2] Case Fan 2: Fan Failed (1 hour ago)
       0 RPM detected
  [3] CPU Core: Temperature High (2 hours ago)
       82C > 80C threshold

Fan Statistics:
  Total Fans: 4
  Normal: 3
  High Speed: 1
  Failed: 1

Sound Settings:
  High Speed: bundled:fan-high
  Failed: bundled:fan-failed
  Temperature: bundled:fan-temp

[Configure] [Add Fan] [Test All]
```

---

## Audio Player Compatibility

Fan monitoring doesn't play sounds directly:
- Monitoring feature using sensors/lm-sensors
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Fan Monitor

```go
type SystemFanMonitor struct {
    config          *SystemFanMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    fanState        map[string]*FanInfo
    lastEventTime   map[string]time.Time
}

type FanInfo struct {
    Name       string
    Device     string
    Speed      int // RPM
    MaxSpeed   int
    Percentage int // 0-100
    Status     string // "normal", "high", "failed", "unknown"
    Temperature float64
}

func (m *SystemFanMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fanState = make(map[string]*FanInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemFanMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotFanState()

    for {
        select {
        case <-ticker.C:
            m.checkFanState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemFanMonitor) snapshotFanState() {
    m.checkFanState()
}

func (m *SystemFanMonitor) checkFanState() {
    fans := m.listFans()

    for _, fan := range fans {
        if !m.shouldWatchFan(fan.Name) {
            continue
        }
        m.processFanStatus(fan)
    }
}

func (m *SystemFanMonitor) listFans() []*FanInfo {
    var fans []*FanInfo

    // Try lm-sensors
    cmd := exec.Command("sensors")
    output, err := cmd.Output()
    if err == nil {
        fans = m.parseSensorsOutput(string(output))
    }

    // If no fans from sensors, try reading from sysfs directly
    if len(fans) == 0 {
        fans = m.readSysfsFans()
    }

    return fans
}

func (m *SystemFanMonitor) parseSensorsOutput(output string) []*FanInfo {
    var fans []*FanInfo
    lines := strings.Split(output, "\n")
    currentFan := ""

    for _, line := range lines {
        line = strings.TrimSpace(line)

        // Detect fan section
        if strings.Contains(line, "fan") || strings.Contains(line, "Fan") {
            if !strings.Contains(line, "input") && !strings.Contains(line, "label") {
                currentFan = strings.TrimSuffix(strings.TrimSpace(line), ":")
            }
        }

        // Parse fan speed
        if strings.HasPrefix(line, "fan") && strings.Contains(line, "RPM") {
            re := regexp.MustEach(`fan(\d+)_input:\s+(\d+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            for _, match := range matches {
                fanNum := match[1]
                rpm, _ := strconv.Atoi(match[2])

                fan := &FanInfo{
                    Device: fmt.Sprintf("fan%d", fanNum),
                    Speed:  rpm,
                    Status: "normal",
                }

                if rpm == 0 {
                    fan.Status = "failed"
                } else if rpm > m.config.SpeedThreshold {
                    fan.Status = "high"
                }

                fans = append(fans, fan)
            }
        }
    }

    return fans
}

func (m *SystemFanMonitor) readSysfsFans() []*FanInfo {
    var fans []*FanInfo

    // Read from /sys/class/hwmon
    hwmonPath := "/sys/class/hwmon"

    entries, err := os.ReadDir(hwmonPath)
    if err != nil {
        return fans
    }

    for _, entry := range entries {
        hwmonDir := filepath.Join(hwmonPath, entry.Name())

        // Read fan files
        fanFiles, _ := filepath.Glob(filepath.Join(hwmonDir, "fan*_input"))
        for _, fanFile := range fanFiles {
            fanName := filepath.Base(fanFile)
            rpmData, err := os.ReadFile(fanFile)
            if err != nil {
                continue
            }

            rpm, _ := strconv.Atoi(strings.TrimSpace(string(rpmData)))

            // Get label if available
            labelFile := strings.Replace(fanFile, "_input", "_label", 1)
            labelData, _ := os.ReadFile(labelFile)
            name := strings.TrimSpace(string(labelData))
            if name == "" {
                name = fmt.Sprintf("Fan %s", fanName)
            }

            fan := &FanInfo{
                Name:   name,
                Device: fanName,
                Speed:  rpm,
                Status: "normal",
            }

            if rpm == 0 {
                fan.Status = "failed"
            } else if rpm > m.config.SpeedThreshold {
                fan.Status = "high"
            }

            // Get temperature from same hwmon device
            tempFile := strings.Replace(fanFile, "fan", "temp", 1)
            tempFile = strings.Replace(tempFile, "_input", "", 1)
            if tempData, err := os.ReadFile(tempFile); err == nil {
                if tempVal, err := strconv.ParseFloat(strings.TrimSpace(string(tempData)), 64); err == nil {
                    fan.Temperature = tempVal / 1000 // Convert to Celsius
                }
            }

            fans = append(fans, fan)
        }
    }

    return fans
}

func (m *SystemFanMonitor) processFanStatus(fan *FanInfo) {
    lastInfo := m.fanState[fan.Device]

    if lastInfo == nil {
        m.fanState[fan.Device] = fan
        return
    }

    // Check for fan failure
    if fan.Speed == 0 && lastInfo.Speed > 0 {
        if m.config.SoundOnFailed {
            m.onFanFailed(fan)
        }
    }

    // Check for high speed
    if fan.Status == "high" && lastInfo.Status != "high" {
        if m.config.SoundOnHighSpeed {
            m.onHighSpeed(fan)
        }
    }

    // Check temperature
    if fan.Temperature >= float64(m.config.TempThreshold) {
        if lastInfo.Temperature < float64(m.config.TempThreshold) {
            if m.config.SoundOnTemp {
                m.onHighTemperature(fan)
            }
        }
    }

    m.fanState[fan.Device] = fan
}

func (m *SystemFanMonitor) shouldWatchFan(name string) bool {
    if len(m.config.WatchFans) == 0 {
        return true
    }

    for _, f := range m.config.WatchFans {
        if f == "*" || name == f || strings.Contains(strings.ToLower(name), strings.ToLower(f)) {
            return true
        }
    }

    return false
}

func (m *SystemFanMonitor) onFanFailed(fan *FanInfo) {
    key := fmt.Sprintf("failed:%s", fan.Device)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemFanMonitor) onHighSpeed(fan *FanInfo) {
    key := fmt.Sprintf("high:%s", fan.Device)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["high_speed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemFanMonitor) onHighTemperature(fan *FanInfo) {
    key := fmt.Sprintf("temp:%s", fan.Device)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["temp"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemFanMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| sensors | System Tool | Free | lm-sensors |
| /sys/class/hwmon | Linux Path | Free | Hardware monitoring |

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
| macOS | Supported | Uses system_profiler |
| Linux | Supported | Uses sensors, /sys/class/hwmon |
