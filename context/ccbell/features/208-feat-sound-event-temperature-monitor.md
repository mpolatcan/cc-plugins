# Feature: Sound Event Temperature Monitor

Play sounds for system temperature events.

## Summary

Monitor CPU, GPU, and system temperatures, playing sounds when thresholds are exceeded or thermal throttling occurs.

## Motivation

- Prevent overheating damage
- Thermal throttling alerts
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

### Temperature Events

| Event | Description | Example |
|-------|-------------|---------|
| High CPU | CPU above threshold | Above 80C |
| Critical CPU | CPU critically hot | Above 95C |
| High GPU | GPU above threshold | Above 85C |
| Thermal Throttling | System throttling | Clock reduced |
| Fan Max | Fans at maximum speed | Loud fan noise |

### Configuration

```go
type TemperatureMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    CPUThreshold       int               `json:"cpu_threshold"` // 80 default
    CPUCritical        int               `json:"cpu_critical"` // 95 default
    GPUThreshold       int               `json:"gpu_threshold"` // 85 default
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
    Sounds             map[string]string `json:"sounds"`
    NotifyOnce         bool              `json:"notify_once"` // Don't repeat
}

type TemperatureStatus struct {
    CPU      float64
    GPU      float64
    Ambient  float64
    Throttling bool
    FanSpeed  int // Percentage
}
```

### Commands

```bash
/ccbell:temp status               # Show temperature status
/ccbell:temp cpu <degrees>        # Set CPU threshold
/ccbell:temp gpu <degrees>        # Set GPU threshold
/ccbell:temp sound high <sound>
/ccbell:temp sound critical <sound>
/ccbell:temp sound throttle <sound>
/ccbell:temp test                 # Test temp sounds
```

### Output

```
$ ccbell:temp status

=== Sound Event Temperature Monitor ===

Status: Enabled
CPU Threshold: 80C
CPU Critical: 95C
GPU Threshold: 85C
Poll Interval: 10s

Current Temperatures:
  CPU: 72C (Normal)
  GPU: 65C (Normal)
  Ambient: 25C

Status: Normal
  Throttling: No
  Fan Speed: 35%

Sound Settings:
  High: bundled:stop
  Critical: bundled:stop
  Throttling: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Temperature monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Temperature Monitor

```go
type TemperatureMonitor struct {
    config     *TemperatureMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastStatus *TemperatureStatus
    notifiedHigh bool
}

func (m *TemperatureMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.notifiedHigh = false
    go m.monitor()
}

func (m *TemperatureMonitor) monitor() {
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

func (m *TemperatureMonitor) checkTemperatures() {
    status := m.getTemperatureStatus()
    if status != nil {
        m.evaluateStatus(status)
    }
}

func (m *TemperatureMonitor) getTemperatureStatus() *TemperatureStatus {
    status := &TemperatureStatus{}

    if runtime.GOOS == "darwin" {
        return m.getMacOSTemperature(status)
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxTemperature(status)
    }

    return status
}

func (m *TemperatureMonitor) getMacOSTemperature(status *TemperatureStatus) *TemperatureStatus {
    // macOS: powermetrics or thermal readings
    cmd := exec.Command("sudo", "powermetrics", "--samplers", "thermal", "-n1")
    output, err := cmd.Output()
    if err != nil {
        // Fallback: use system_profiler
        cmd = exec.Command("system_profiler", "SPPowerDataType")
        output, err = cmd.Output()
        if err != nil {
            return nil
        }
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(strings.ToLower(line), "cpu") &&
           strings.Contains(strings.ToLower(line), "temperature") {
            parts := strings.Fields(line)
            for _, part := range parts {
                if temp, err := strconv.ParseFloat(part, 64); err == nil {
                    status.CPU = temp
                    break
                }
            }
        }
    }

    return status
}

func (m *TemperatureMonitor) getLinuxTemperature(status *TemperatureStatus) *TemperatureStatus {
    // Linux: /sys/class/thermal/
    thermalPaths := []string{
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/class/thermal/thermal_zone1/temp",
    }

    for i, path := range thermalPaths {
        if data, err := os.ReadFile(path); err == nil {
            temp, _ := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
            temp = temp / 1000 // Convert to Celsius

            if i == 0 {
                status.CPU = temp
            } else if i == 1 {
                status.GPU = temp
            }
        }
    }

    // Check fan speed if available
    fanPath := "/sys/class/hwmon/hwmon0/fan1_input"
    if data, err := os.ReadFile(fanPath); err == nil {
        fanSpeed, _ := strconv.Atoi(strings.TrimSpace(string(data)))
        status.FanSpeed = fanSpeed
    }

    return status
}

func (m *TemperatureMonitor) evaluateStatus(status *TemperatureStatus) {
    if m.lastStatus != nil {
        // Check critical temperature
        if status.CPU >= float64(m.config.CPUCritical) {
            if m.lastStatus.CPU < float64(m.config.CPUCritical) {
                m.playSound("critical")
            }
        }

        // Check high temperature
        if status.CPU >= float64(m.config.CPUThreshold) &&
           status.CPU < float64(m.config.CPUCritical) {
            if !m.notifiedHigh {
                m.playSound("high")
                m.notifiedHigh = true
            }
        }

        // Check cooling
        if status.CPU < float64(m.config.CPUThreshold) {
            m.notifiedHigh = false
        }

        // Check throttling (if CPU dropped significantly)
        if m.lastStatus.CPU > float64(m.config.CPUThreshold) &&
           status.CPU < float64(m.config.CPUThreshold)-10 {
            if status.Throttling {
                m.playSound("throttling")
            }
        }
    }

    m.lastStatus = status
}

func (m *TemperatureMonitor) playSound(event string) {
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
| powermetrics | System Tool | Free | macOS thermal info |
| /sys/class/thermal | File System | Free | Linux thermal zones |
| sudo | System Tool | Free | Required for powermetrics |

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
| Linux | Supported | Uses sysfs thermal zones |
| Windows | Not Supported | ccbell only supports macOS/Linux |
