# Feature: Sound Event System Boot Monitor

Play sounds for system boot and shutdown events.

## Summary

Monitor system boot process, shutdown events, and login screen appearance, playing sounds for system lifecycle events.

## Motivation

- Boot completion alerts
- Shutdown detection
- Login feedback
- System recovery awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### System Boot Events

| Event | Description | Example |
|-------|-------------|---------|
| Boot Started | System booting | BIOS/UEFI init |
| Boot Complete | Login screen | Desktop ready |
| Shutdown Started | System halting | Power off |
| User Logged In | Session started | GUI ready |
| Recovery Mode | Safe boot | Diagnostics |

### Configuration

```go
type SystemBootMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    SoundOnBoot     bool              `json:"sound_on_boot"`
    SoundOnComplete bool              `json:"sound_on_complete"`
    SoundOnShutdown bool              `json:"sound_on_shutdown"`
    SoundOnLogin    bool              `json:"sound_on_login"`
    Sounds          map[string]string `json:"sounds"`
}

type SystemBootEvent struct {
    EventType  string // "boot_start", "boot_complete", "shutdown", "login", "recovery"
    BootTime   time.Duration
    UserName   string
}
```

### Commands

```bash
/ccbell:boot status             # Show boot status
/ccbell:boot sound boot <sound>
/ccbell:boot sound complete <sound>
/ccbell:boot test               # Test boot sounds
```

### Output

```
$ ccbell:boot status

=== Sound Event System Boot Monitor ===

Status: Enabled
Complete Sounds: Yes
Shutdown Sounds: Yes

Last Boot:
  Time: Today at 8:15 AM
  Duration: 45 seconds
  User: user

System Uptime: 5 days, 12 hours

Recent Events:
  [1] Boot Complete (5 days ago)
       Duration: 45 seconds
  [2] User Logged In (5 days ago)
  [3] Shutdown Started (6 days ago)
       Graceful shutdown

Sound Settings:
  Boot Start: bundled:stop
  Boot Complete: bundled:stop
  Shutdown: bundled:stop
  Login: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

System boot monitoring doesn't play sounds directly:
- Monitoring feature using system boot time tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Boot Monitor

```go
type SystemBootMonitor struct {
    config        *SystemBootMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    bootStartTime time.Time
    lastBootTime  time.Time
    isShuttingDown bool
}
```

```go
func (m *SystemBootMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})

    // Record boot start time
    m.bootStartTime = time.Now()

    go m.monitor()
}

func (m *SystemBootMonitor) monitor() {
    ticker := time.NewTicker(1 * time.Second)
    defer ticker.Stop()

    // Initial check
    m.checkBootStatus()

    for {
        select {
        case <-ticker.C:
            m.checkBootStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemBootMonitor) checkBootStatus() {
    // Check if system has just booted
    uptime := m.getSystemUptime()

    if uptime < 5*time.Minute {
        // System is still booting
        if m.bootStartTime.IsZero() || m.bootStartTime.After(time.Now().Add(-10*time.Minute)) {
            m.bootStartTime = time.Now()
            m.onBootStarted()
        }
    }

    // Check for boot completion
    if uptime > 30*time.Second && m.lastBootTime.IsZero() {
        m.lastBootTime = time.Now()
        m.onBootComplete(uptime)
    }

    // Check for user login
    if runtime.GOOS == "darwin" {
        m.checkDarwinLogin()
    } else {
        m.checkLinuxLogin()
    }
}

func (m *SystemBootMonitor) getSystemUptime() time.Duration {
    if runtime.GOOS == "darwin" {
        return m.getDarwinUptime()
    }
    return m.getLinuxUptime()
}

func (m *SystemBootMonitor) getDarwinUptime() time.Duration {
    cmd := exec.Command("uptime")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    // Parse uptime output
    re := regexp.MustCompile(`up\s+([^,]+)`)
    match := re.FindStringSubmatch(string(output))
    if len(match) < 2 {
        return 0
    }

    uptimeStr := match[1]
    return m.parseUptimeString(uptimeStr)
}

func (m *SystemBootMonitor) getLinuxUptime() time.Duration {
    data, err := os.ReadFile("/proc/uptime")
    if err != nil {
        return 0
    }

    parts := strings.Fields(string(data))
    if len(parts) < 1 {
        return 0
    }

    seconds, err := strconv.ParseFloat(parts[0], 64)
    if err != nil {
        return 0
    }

    return time.Duration(seconds * float64(time.Second))
}

func (m *SystemBootMonitor) parseUptimeString(s string) time.Duration {
    // Parse formats like "5 days, 1:23", "3:45", "45 secs"
    now := time.Now()

    // Try various formats
    if strings.Contains(s, "day") {
        // "5 days, 1:23"
        re := regexp.MustCompile(`(\d+)\s+days?,\s+(\d+):(\d+)`)
        match := re.FindStringSubmatch(s)
        if len(match) >= 4 {
            days, _ := strconv.Atoi(match[1])
            hours, _ := strconv.Atoi(match[2])
            mins, _ := strconv.Atoi(match[3])
            return time.Duration(days)*24*time.Hour + time.Duration(hours)*time.Hour + time.Duration(mins)*time.Minute
        }
    }

    if strings.Contains(s, ":") {
        // "1:23" or "01:23:45"
        parts := strings.Split(s, ":")
        if len(parts) >= 2 {
            hours, _ := strconv.Atoi(parts[0])
            mins, _ := strconv.Atoi(parts[1])
            if len(parts) >= 3 {
                secs, _ := strconv.Atoi(parts[2])
                return time.Duration(hours)*time.Hour + time.Duration(mins)*time.Minute + time.Duration(secs)*time.Second
            }
            return time.Duration(hours)*time.Hour + time.Duration(mins)*time.Minute
        }
    }

    // Try "45 secs"
    re := regexp.MustCompile(`(\d+)\s+secs?`)
    match := re.FindStringSubmatch(s)
    if len(match) >= 2 {
        secs, _ := strconv.Atoi(match[1])
        return time.Duration(secs) * time.Second
    }

    return 0
}

func (m *SystemBootMonitor) checkDarwinLogin() {
    // Check for loginwindow process
    cmd := exec.Command("pgrep", "-x", "loginwindow")
    err := cmd.Run()

    if err == nil && m.lastBootTime.IsZero() {
        // loginwindow is running - user logged in
        m.onUserLoggedIn()
    }
}

func (m *SystemBootMonitor) checkLinuxLogin() {
    // Check for graphical session
    cmd := exec.Command("loginctl", "list-sessions")
    output, err := cmd.Output()

    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "Seat") {
                // Active session found
                if m.lastBootTime.IsZero() || m.bootStartTime.After(time.Now().Add(-5*time.Minute)) {
                    m.onUserLoggedIn()
                }
                break
            }
        }
    }
}

func (m *SystemBootMonitor) checkShutdown() {
    // This would be triggered by a signal or shutdown hook
    // Not polling-based

    // Check for shutdown in progress
    cmd := exec.Command("shutdown", "-k")
    err := cmd.Run()

    if err == nil {
        m.onShutdownStarted()
    }
}

func (m *SystemBootMonitor) onBootStarted() {
    if !m.config.SoundOnBoot {
        return
    }

    sound := m.config.Sounds["boot_start"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemBootMonitor) onBootComplete(bootTime time.Duration) {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["boot_complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemBootMonitor) onShutdownStarted() {
    if !m.config.SoundOnShutdown {
        return
    }

    sound := m.config.Sounds["shutdown"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemBootMonitor) onUserLoggedIn() {
    if !m.config.SoundOnLogin {
        return
    }

    sound := m.config.Sounds["login"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| uptime | System Tool | Free | System uptime |
| pgrep | System Tool | Free | Process checking |
| loginctl | System Tool | Free | Linux login sessions |
| /proc/uptime | File | Free | Linux uptime |

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
| macOS | Supported | Uses uptime, pgrep |
| Linux | Supported | Uses uptime, loginctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
