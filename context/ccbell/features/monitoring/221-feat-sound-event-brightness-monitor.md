# Feature: Sound Event Brightness Monitor

Play sounds for display brightness changes.

## Summary

Monitor display brightness levels and changes, playing sounds for significant brightness adjustments and ambient light transitions.

## Motivation

- Brightness change feedback
- Night shift awareness
- Ambient light alerts
- Eye strain prevention

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Brightness Events

| Event | Description | Example |
|-------|-------------|---------|
| Brightness Up | Brightness increased | Fn+F2 pressed |
| Brightness Down | Brightness decreased | Fn+F1 pressed |
| Max Brightness | Maximum brightness reached | At 100% |
| Min Brightness | Minimum brightness reached | At 0% |
| Night Shift | Night shift activated | Schedule trigger |
| Ambient Low | Low ambient light detected | Dark room |

### Configuration

```go
type BrightnessMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    BrightnessSounds  bool              `json:"brightness_sounds"`
    MinThreshold      float64           `json:"min_threshold"` // 0.1 default
    MaxThreshold      float64           `json:"max_threshold"` // 0.9 default
    NightShiftSounds  bool              `json:"night_shift_sounds"`
    AmbientSounds     bool              `json:"ambient_sounds"`
    Sounds            map[string]string `json:"sounds"`
}

type BrightnessEvent struct {
    Brightness  float64 // 0.0 - 1.0
    Delta       float64
    IsNightShift bool
    AmbientLux  float64
}
```

### Commands

```bash
/ccbell:brightness status         # Show brightness status
/ccbell:brightness sounds on      # Enable brightness sounds
/ccbell:brightness min <percent>  # Set minimum threshold
/ccbell:brightness max <percent>  # Set maximum threshold
/ccbell:brightness sound up <sound>
/ccbell:brightness sound down <sound>
/ccbell:brightness test           # Test brightness sounds
```

### Output

```
$ ccbell:brightness status

=== Sound Event Brightness Monitor ===

Status: Enabled
Brightness Sounds: Yes
Min Threshold: 10%
Max Threshold: 90%

Current Brightness:
  Level: 65%
  Status: Normal

Night Shift:
  Status: Active
  Schedule: 10 PM - 7 AM

Ambient Light:
  Sensor: Available
  Level: Normal

Sound Settings:
  Brightness Up: bundled:stop
  Brightness Down: bundled:stop
  Max Brightness: bundled:stop
  Min Brightness: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Brightness monitoring doesn't play sounds directly:
- Monitoring feature using display control APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Brightness Monitor

```go
type BrightnessMonitor struct {
    config         *BrightnessMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    lastBrightness float64
    lastNightShift bool
}

func (m *BrightnessMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastBrightness = m.getCurrentBrightness()
    m.lastNightShift = m.isNightShiftActive()
    go m.monitor()
}

func (m *BrightnessMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBrightness()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BrightnessMonitor) checkBrightness() {
    currentBrightness := m.getCurrentBrightness()
    currentNightShift := m.isNightShiftActive()

    delta := currentBrightness - m.lastBrightness

    // Check brightness up
    if delta > 0.05 && m.config.BrightnessSounds {
        m.onBrightnessUp(delta)
    }

    // Check brightness down
    if delta < -0.05 && m.config.BrightnessSounds {
        m.onBrightnessDown(-delta)
    }

    // Check max brightness
    if currentBrightness >= m.config.MaxThreshold && m.lastBrightness < m.config.MaxThreshold {
        m.onMaxBrightness()
    }

    // Check min brightness
    if currentBrightness <= m.config.MinThreshold && m.lastBrightness > m.config.MinThreshold {
        m.onMinBrightness()
    }

    // Check night shift change
    if currentNightShift != m.lastNightShift && m.config.NightShiftSounds {
        if currentNightShift {
            m.onNightShiftOn()
        } else {
            m.onNightShiftOff()
        }
    }

    m.lastBrightness = currentBrightness
    m.lastNightShift = currentNightShift
}

func (m *BrightnessMonitor) getCurrentBrightness() float64 {
    if runtime.GOOS == "darwin" {
        return m.getMacOSBrightness()
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxBrightness()
    }

    return 0.5
}

func (m *BrightnessMonitor) getMacOSBrightness() float64 {
    // macOS: brightness command or system_profiler
    cmd := exec.Command("brightness", "-l")
    output, err := cmd.Output()
    if err != nil {
        // Fallback: use pmset
        cmd = exec.Command("pmset", "-g", "brightness")
        output, _ = cmd.Output()
    }

    // Parse current brightness value
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Current") {
            parts := strings.Fields(line)
            for _, part := range parts {
                if val, err := strconv.ParseFloat(part, 64); err == nil {
                    if val <= 1.0 {
                        return val
                    }
                }
            }
        }
    }

    return 0.5
}

func (m *BrightnessMonitor) getLinuxBrightness() float64 {
    // Linux: /sys/class/backlight/*
    brightnessPath := m.findBacklightPath()

    if brightnessPath == "" {
        return 0.5
    }

    brightnessFile := filepath.Join(brightnessPath, "brightness")
    maxFile := filepath.Join(brightnessPath, "max_brightness")

    brightnessData, err := os.ReadFile(brightnessFile)
    if err != nil {
        return 0.5
    }

    maxData, err := os.ReadFile(maxFile)
    if err != nil {
        return 0.5
    }

    brightness, _ := strconv.ParseFloat(strings.TrimSpace(string(brightnessData)), 64)
    max, _ := strconv.ParseFloat(strings.TrimSpace(string(maxData)), 64)

    if max > 0 {
        return brightness / max
    }

    return 0.5
}

func (m *BrightnessMonitor) findBacklightPath() string {
    // Look for backlight devices
    paths := []string{
        "/sys/class/backlight",
        "/sys/class leds/backlight",
    }

    for _, basePath := range paths {
        entries, err := os.ReadDir(basePath)
        if err != nil {
            continue
        }

        for _, entry := range entries {
            if entry.IsDir() {
                return filepath.Join(basePath, entry.Name())
            }
        }
    }

    return ""
}

func (m *BrightnessMonitor) isNightShiftActive() bool {
    if runtime.GOOS == "darwin" {
        return m.isMacOSNightShiftActive()
    }

    if runtime.GOOS == "linux" {
        return m.isLinuxNightShiftActive()
    }

    return false
}

func (m *BrightnessMonitor) isMacOSNightShiftActive() bool {
    // Check Night Shift status
    cmd := exec.Command("defaults", "read", "com.apple.CoreBrightness", "CBBlueLightStatus")
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.Contains(string(output), "status = 1")
}

func (m *BrightnessMonitor) isLinuxNightShiftActive() bool {
    // Check redshift or similar
    cmd := exec.Command("pgrep", "-x", "redshift")
    err := cmd.Run()
    return err == nil
}

func (m *BrightnessMonitor) onBrightnessUp(delta float64) {
    sound := m.config.Sounds["up"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *BrightnessMonitor) onBrightnessDown(delta float64) {
    sound := m.config.Sounds["down"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *BrightnessMonitor) onMaxBrightness() {
    sound := m.config.Sounds["max"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BrightnessMonitor) onMinBrightness() {
    sound := m.config.Sounds["min"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BrightnessMonitor) onNightShiftOn() {
    sound := m.config.Sounds["night_shift_on"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BrightnessMonitor) onNightShiftOff() {
    sound := m.config.Sounds["night_shift_off"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| brightness | Homebrew | Free | macOS brightness control |
| /sys/class/backlight | File System | Free | Linux backlight control |
| redshift | APT | Free | Linux night shift |

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
| macOS | Supported | Uses brightness command |
| Linux | Supported | Uses sysfs backlight |
| Windows | Not Supported | ccbell only supports macOS/Linux |
