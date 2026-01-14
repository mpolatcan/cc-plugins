# Feature: Sound Event Sleep Monitor

Play sounds for system sleep and wake events.

## Summary

Monitor system sleep states, hibernation, and power management events, playing sounds for sleep-related events.

## Motivation

- Sleep confirmation feedback
- Wake awareness
- Battery saving awareness
- Power state confirmation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Sleep Events

| Event | Description | Example |
|-------|-------------|---------|
| Sleep | System going to sleep | Lid closed |
| Wake | System waking up | Lid opened |
| Hibernate | System hibernating | Deep sleep |
| Dark Wake | Partial wake | Network active |
| Shutdown | System powering off | Shutdown command |
| Restart | System restarting | Reboot command |

### Configuration

```go
type SleepMonitorConfig struct {
    Enabled      bool              `json:"enabled"`
    SleepSound   string            `json:"sleep_sound"`
    WakeSound    string            `json:"wake_sound"`
    HibernateSound string          `json:"hibernate_sound"`
    ShutdownSound string           `json:"shutdown_sound"`
    RestartSound string            `json:"restart_sound"`
    Sounds       map[string]string `json:"sounds"`
}

type SleepEvent struct {
    EventType string // "sleep", "wake", "hibernate", "shutdown", "restart"
    Duration  time.Duration // Time since last state
}
```

### Commands

```bash
/ccbell:sleep status              # Show sleep status
/ccbell:sleep sound sleep <sound>
/ccbell:sleep sound wake <sound>
/ccbell:sleep sound hibernate <sound>
/ccbell:sleep sound shutdown <sound>
/ccbell:sleep sound restart <sound>
/ccbell:sleep test                # Test sleep sounds
```

### Output

```
$ ccbell:sleep status

=== Sound Event Sleep Monitor ===

Status: Enabled

Current State: Awake
Last Sleep: 2 hours ago
Sleep Duration: 45 min
Total Sleep Today: 3 hours

Recent Sleep Events:
  [1] System Woke (2 hours ago)
       Duration: 45 min
       Sound: bundled:stop
  [2] System Sleep (3 hours ago)
       Duration: 1 hour
       Sound: bundled:stop
  [3] System Hibernate (Yesterday)
       Duration: 8 hours
       Sound: bundled:stop

Sound Settings:
  Sleep: bundled:stop
  Wake: bundled:stop
  Hibernate: bundled:stop
  Shutdown: bundled:stop
  Restart: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Sleep monitoring doesn't play sounds directly:
- Monitoring feature using power management APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Sleep Monitor

```go
type SleepMonitor struct {
    config       *SleepMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastState    string // "awake", "sleeping", "hibernating"
    lastStateTime time.Time
    stateHistory []SleepEvent
}

func (m *SleepMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastState = "awake"
    m.lastStateTime = time.Now()
    m.stateHistory = make([]SleepEvent, 0)
    go m.monitor()
}

func (m *SleepMonitor) monitor() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSleepState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SleepMonitor) checkSleepState() {
    currentState := m.getSleepState()

    if currentState != m.lastState {
        m.onStateChange(currentState)
        m.lastState = currentState
        m.lastStateTime = time.Now()
    }
}

func (m *SleepMonitor) getSleepState() string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSSleepState()
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxSleepState()
    }
    return "unknown"
}

func (m *SleepMonitor) getMacOSSleepState() string {
    // Check system state using pmset
    cmd := exec.Command("pmset", "-g", "assertions")
    output, err := cmd.Output()
    if err != nil {
        return "unknown"
    }

    // Check for prevent sleep assertion
    if strings.Contains(string(output), "PreventUserIdleSystemSleep") {
        return "awake"
    }

    // Check for sleep
    cmd = exec.Command("pmset", "-g", " assertionslog")
    output, err = cmd.Output()
    if err != nil {
        return "unknown"
    }

    if strings.Contains(string(output), "AppleClamshellState: closed") {
        return "sleeping"
    }

    // Check for dark wake
    if strings.Contains(string(output), "DarkWake") {
        return "dark_wake"
    }

    return "awake"
}

func (m *SleepMonitor) getLinuxSleepState() string {
    // Check /sys/power/state
    stateData, err := os.ReadFile("/sys/power/state")
    if err != nil {
        return "unknown"
    }

    state := strings.TrimSpace(string(stateData))
    if state == "mem" {
        return "sleeping"
    }

    // Check for systemd-logind
    cmd := exec.Command("systemctl", "status", "sleep.target")
    err = cmd.Run()

    if err == nil {
        return "awake"
    }

    return "awake"
}

func (m *SleepMonitor) onStateChange(newState string) {
    duration := time.Since(m.lastStateTime)

    event := SleepEvent{
        EventType: newState,
        Duration:  duration,
    }

    switch newState {
    case "sleeping":
        m.onSleep(duration)
    case "awake":
        if m.lastState == "sleeping" || m.lastState == "hibernating" {
            m.onWake(duration)
        }
    case "hibernating":
        m.onHibernate(duration)
    case "shutdown":
        m.onShutdown()
    case "restart":
        m.onRestart()
    }

    m.stateHistory = append([]SleepEvent{event}, m.stateHistory...)
    if len(m.stateHistory) > 50 {
        m.stateHistory = m.stateHistory[:50]
    }
}

func (m *SleepMonitor) onSleep(duration time.Duration) {
    sound := m.config.SleepSound
    if sound == "" {
        sound = m.config.Sounds["sleep"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SleepMonitor) onWake(duration time.Duration) {
    sound := m.config.WakeSound
    if sound == "" {
        sound = m.config.Sounds["wake"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SleepMonitor) onHibernate(duration time.Duration) {
    sound := m.config.HibernateSound
    if sound == "" {
        sound = m.config.Sounds["hibernate"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SleepMonitor) onShutdown() {
    sound := m.config.ShutdownSound
    if sound == "" {
        sound = m.config.Sounds["shutdown"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SleepMonitor) onRestart() {
    sound := m.config.RestartSound
    if sound == "" {
        sound = m.config.Sounds["restart"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SleepMonitor) getTotalSleepTime() time.Duration {
    var total time.Duration

    for _, event := range m.stateHistory {
        if event.EventType == "awake" {
            total += event.Duration
        }
    }

    return total
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pmset | System Tool | Free | macOS power management |
| /sys/power/state | File | Free | Linux power state |
| systemctl | System Tool | Free | Linux service management |

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
| macOS | Supported | Uses pmset |
| Linux | Supported | Uses /sys/power/systemctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
