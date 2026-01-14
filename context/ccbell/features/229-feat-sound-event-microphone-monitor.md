# Feature: Sound Event Microphone Monitor

Play sounds for microphone access and status events.

## Summary

Monitor microphone access, recording states, and input level changes, playing sounds for microphone events.

## Motivation

- Privacy awareness
- Recording state feedback
- Input level alerts
- Mute/unmute confirmation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Microphone Events

| Event | Description | Example |
|-------|-------------|---------|
| Recording | Microphone active | Voice call |
| Muted | Microphone muted | Mute button pressed |
| Input High | Input level high | Loud noise detected |
| Input Low | Input level low | Too quiet |
| Device Connected | Mic plugged in | USB mic attached |

### Configuration

```go
type MicrophoneMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnAccess     bool              `json:"sound_on_access"`
    SoundOnMute       bool              `json:"sound_on_mute"`
    HighThreshold     float64           `json:"high_threshold"` // 0.8 default
    LowThreshold      float64           `json:"low_threshold"` // 0.1 default
    WatchApps         []string          `json:"watch_apps"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 1 default
}

type MicrophoneEvent struct {
    AppName     string
    EventType   string // "recording", "muted", "input_high", "input_low"
    InputLevel  float64
    DeviceName  string
}
```

### Commands

```bash
/ccbell:microphone status         # Show microphone status
/ccbell:microphone access on      # Enable access sounds
/ccbell:microphone add Zoom       # Add app to watch
/ccbell:microphone sound recording <sound>
/ccbell:microphone sound muted <sound>
/ccbell:microphone test           # Test microphone sounds
```

### Output

```
$ ccbell:microphone status

=== Sound Event Microphone Monitor ===

Status: Enabled
Access Sounds: Yes
Mute Sounds: Yes

Current State:
  Status: Recording
  Input Level: 45%
  Muted: No
  Active Apps: 1

Devices: 2

[1] Built-in Microphone
    Status: Active
    Input: 45%
    Sound: bundled:stop

[2] USB Microphone
    Status: Connected
    Input: 0%
    Sound: bundled:stop

Recent Events:
  [1] Zoom: Recording started (2 min ago)
  [2] Microphone: Muted (15 min ago)
  [3] USB Microphone: Device Connected (1 hour ago)

Sound Settings:
  Recording: bundled:stop
  Muted: bundled:stop
  Input High: bundled:stop

[Configure] [Add App] [Test All]
```

---

## Audio Player Compatibility

Microphone monitoring doesn't play sounds directly:
- Monitoring feature using audio APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Microphone Monitor

```go
type MicrophoneMonitor struct {
    config        *MicrophoneMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    activeApps    map[string]bool
    isMuted       bool
    lastInputLevel float64
}

func (m *MicrophoneMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeApps = make(map[string]bool)
    m.isMuted = true
    go m.monitor()
}

func (m *MicrophoneMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkMicrophone()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MicrophoneMonitor) checkMicrophone() {
    // Check active microphone users
    activeUsers := m.getActiveMicrophoneUsers()

    for app, isActive := range activeUsers {
        wasActive := m.activeApps[app]
        m.activeApps[app] = isActive

        if isActive && !wasActive {
            m.onRecording(app)
        } else if !isActive && wasActive {
            m.onRecordingStopped(app)
        }
    }

    // Check input level
    inputLevel := m.getInputLevel()
    m.checkInputLevel(inputLevel)
    m.lastInputLevel = inputLevel

    // Check mute state
    muted := m.isMuted()
    if muted != m.isMuted {
        if muted {
            m.onMuted()
        } else {
            m.onUnmuted()
        }
        m.isMuted = muted
    }
}

func (m *MicrophoneMonitor) getActiveMicrophoneUsers() map[string]bool {
    users := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        users = m.getMacOSMicUsers()
    } else if runtime.GOOS == "linux" {
        users = m.getLinuxMicUsers()
    }

    // Filter to watched apps
    if len(m.config.WatchApps) > 0 {
        filtered := make(map[string]bool)
        for app, active := range users {
            for _, watched := range m.config.WatchApps {
                if strings.Contains(strings.ToLower(app), strings.ToLower(watched)) {
                    filtered[app] = active
                    break
                }
            }
        }
        return filtered
    }

    return users
}

func (m *MicrophoneMonitor) getMacOSMicUsers() map[string]bool {
    users := make(map[string]bool)

    cmd := exec.Command("lsof", "-i", "-P", "-n")
    output, err := cmd.Output()
    if err != nil {
        return users
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "coreaudio") || strings.Contains(line, "Hall") {
            parts := strings.Fields(line)
            if len(parts) > 0 {
                users[parts[0]] = true
            }
        }
    }

    return users
}

func (m *MicrophoneMonitor) getLinuxMicUsers() map[string]bool {
    users := make(map[string]bool)

    cmd := exec.Command("lsof", "/dev/snd/*")
    output, err := cmd.Output()
    if err != nil {
        return users
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) > 0 {
            users[parts[0]] = true
        }
    }

    return users
}

func (m *MicrophoneMonitor) getInputLevel() float64 {
    if runtime.GOOS == "darwin" {
        return m.getMacOSInputLevel()
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxInputLevel()
    }
    return 0
}

func (m *MicrophoneMonitor) getMacOSInputLevel() float64 {
    cmd := exec.Command("osascript", "-e",
        "input volume of (get volume settings)")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    vol, _ := strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
    return vol / 100
}

func (m *MicrophoneMonitor) getLinuxInputLevel() float64 {
    cmd := exec.Command("amixer", "sget", "Capture")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    match := regexp.MustCompile(`\[(\d+)%\]`).FindStringSubmatch(string(output))
    if match != nil {
        vol, _ := strconv.ParseFloat(match[1], 64)
        return vol / 100
    }

    return 0
}

func (m *MicrophoneMonitor) isMuted() bool {
    if runtime.GOOS == "darwin" {
        return m.isMacOSMuted()
    }
    if runtime.GOOS == "linux" {
        return m.isLinuxMuted()
    }
    return true
}

func (m *MicrophoneMonitor) isMacOSMuted() bool {
    cmd := exec.Command("osascript", "-e",
        "input muted of (get volume settings)")
    output, err := cmd.Output()
    if err != nil {
        return true
    }

    return strings.TrimSpace(string(output)) == "true"
}

func (m *MicrophoneMonitor) isLinuxMuted() bool {
    cmd := exec.Command("amixer", "sget", "Capture")
    output, err := cmd.Output()
    if err != nil {
        return true
    }

    return strings.Contains(string(output), "[off]")
}

func (m *MicrophoneMonitor) checkInputLevel(level float64) {
    if m.lastInputLevel == 0 {
        return
    }

    if level >= m.config.HighThreshold && m.lastInputLevel < m.config.HighThreshold {
        m.onInputHigh()
    } else if level <= m.config.LowThreshold && m.lastInputLevel > m.config.LowThreshold {
        m.onInputLow()
    }
}

func (m *MicrophoneMonitor) onRecording(appName string) {
    if !m.config.SoundOnAccess {
        return
    }

    sound := m.config.Sounds["recording"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *MicrophoneMonitor) onRecordingStopped(appName string) {
    sound := m.config.Sounds["stopped"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *MicrophoneMonitor) onMuted() {
    if !m.config.SoundOnMute {
        return
    }

    sound := m.config.Sounds["muted"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *MicrophoneMonitor) onUnmuted() {
    sound := m.config.Sounds["unmuted"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *MicrophoneMonitor) onInputHigh() {
    sound := m.config.Sounds["input_high"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *MicrophoneMonitor) onInputLow() {
    sound := m.config.Sounds["input_low"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lsof | System Tool | Free | File descriptor checking |
| osascript | System Tool | Free | macOS audio control |
| amixer | ALSA | Free | Linux audio control |

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
| macOS | Supported | Uses lsof/osascript |
| Linux | Supported | Uses lsof/amixer |
| Windows | Not Supported | ccbell only supports macOS/Linux |
