# Feature: Sound Event Screen Lock Monitor

Play sounds for screen lock events, unlock attempts, and screensaver activation.

## Summary

Monitor screen lock status for lock/unlock events, screensaver activation, and session changes, playing sounds for screen events.

## Motivation

- Security awareness
- Session management
- Privacy protection
- Lock feedback
- Idle detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Screen Lock Events

| Event | Description | Example |
|-------|-------------|---------|
| Screen Locked | Session locked | Locked |
| Screen Unlocked | Session unlocked | Unlocked |
| Screensaver Started | Saver activated | Active |
| Screensaver Stopped | User returned | Stopped |
| Session Active | User active | Idle reset |
| Lock Failed | Auth failed | Wrong password |

### Configuration

```go
type ScreenLockMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchLock         bool              `json:"watch_lock"` // true default
    WatchUnlock       bool              `json:"watch_unlock"` // true default
    WatchScreensaver  bool              `json:"watch_screensaver"` // true default
    SoundOnLock       bool              `json:"sound_on_lock"`
    SoundOnUnlock     bool              `json:"sound_on_unlock"`
    SoundOnScreensaver bool             `json:"sound_on_screensaver"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}
```

### Commands

```bash
/ccbell:lock status                 # Show lock status
/ccbell:lock sound lock <sound>
/ccbell:lock sound unlock <sound>
/ccbell:lock sound screensaver <sound>
/ccbell:lock test                   # Test lock sounds
```

### Output

```
$ ccbell:lock status

=== Sound Event Screen Lock Monitor ===

Status: Enabled
Watch Lock: Yes
Watch Unlock: Yes
Watch Screensaver: Yes

Screen Status:

[1] Current Session
    Status: UNLOCKED
    User: user
    Session Duration: 4h 30m
    Idle Time: 2 min
    Sound: bundled:lock-unlocked

[2] Lock Status
    Last Locked: Jan 14, 2026 08:00:00
    Last Unlocked: Jan 14, 2026 08:15:00
    Lock Method: Screensaver
    Sound: bundled:lock-status

[3] Screensaver
    Status: INACTIVE
    Last Active: Jan 13, 2026 22:00:00
    Duration: 15 min
    Sound: bundled:lock-saver

Recent Lock Events:
  [1] Screen Unlocked (30 min ago)
       User: user
       Method: Password
       Sound: bundled:lock-unlock
  [2] Screen Locked (1 hour ago)
       Method: Keyboard shortcut
       Sound: bundled:lock-lock
  [3] Screensaver Started (2 hours ago)
       After 10 min idle
       Sound: bundled:lock-saver

Lock Statistics:
  Locks Today: 12
  Unlocks Today: 11
  Screensaver Activations: 15
  Avg Lock Duration: 15 min

Sound Settings:
  Lock: bundled:lock-lock
  Unlock: bundled:lock-unlock
  Screensaver: bundled:lock-saver
  Failed: bundled:lock-failed

[Configure] [Test All]
```

---

## Audio Player Compatibility

Screen lock monitoring doesn't play sounds directly:
- Monitoring feature using pmset/screensaver command
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Screen Lock Monitor

```go
type ScreenLockMonitor struct {
    config          *ScreenLockMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    lockState       *ScreenLockInfo
    lastEventTime   map[string]time.Time
}

type ScreenLockInfo struct {
    Status         string // "locked", "unlocked", "screensaver", "unknown"
    IsLocked       bool
    IsScreensaver  bool
    IdleTime       time.Duration
    LastLockTime   time.Time
    LastUnlockTime time.Time
    LastActivity   time.Time
}

func (m *ScreenLockMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lockState = &ScreenLockInfo{
        Status: "unknown",
    }
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ScreenLockMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLockStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ScreenLockMonitor) checkLockStatus() {
    info := m.getLockStatus()
    if info == nil {
        return
    }

    m.processLockStatus(info)
}

func (m *ScreenLockMonitor) getLockStatus() *ScreenLockInfo {
    info := &ScreenLockInfo{
        LastActivity: time.Now(),
    }

    if runtime.GOOS == "darwin" {
        m.getDarwinLockStatus(info)
    } else {
        m.getLinuxLockStatus(info)
    }

    return info
}

func (m *ScreenLockMonitor) getDarwinLockStatus(info *ScreenLockInfo) {
    // Check if screen is locked using pmset
    cmd := exec.Command("pmset", "-g", " assertions")
    output, err := cmd.Output()

    if err == nil {
        outputStr := string(output)
        if strings.Contains(outputStr, "PreventUserIdleDisplaySleep") ||
           strings.Contains(outputStr, "PreventSystemSleep") {
            info.Status = "active"
        }
    }

    // Check for loginwindow process state
    cmd = exec.Command("pgrep", "-x", "ScreenSaverEngine")
    err = cmd.Run()
    if err == nil {
        info.IsScreensaver = true
        info.Status = "screensaver"
    }

    // Check idle time
    cmd = exec.Command("ioreg", "-c", "IOHIDSystem", "|", "grep", "HIDIdleTime")
    output, err = cmd.Output()

    if err == nil {
        outputStr := string(output)
        idleRe := regexp.MustEach(`"HIDIdleTime" = (\d+)`)
        matches := idleRe.FindStringSubmatch(outputStr)
        if len(matches) >= 2 {
            idleNano, _ := strconv.ParseInt(matches[1], 10, 64)
            info.IdleTime = time.Duration(idleNano) * time.Nanosecond
        }
    }

    // Check for lock status using security command
    cmd = exec.Command("security", "lock-status")
    output, err = cmd.Output()

    if err == nil {
        outputStr := string(output)
        if strings.Contains(outputStr, "LOCKED") {
            info.IsLocked = true
            info.Status = "locked"
        } else if strings.Contains(outputStr, "UNLOCKED") {
            info.IsLocked = false
            if info.Status == "screensaver" {
                // Still in screensaver mode
            } else {
                info.Status = "unlocked"
            }
        }
    }
}

func (m *ScreenLockMonitor) getLinuxLockStatus(info *ScreenLockInfo) {
    // Check for screen lock using loginctl
    if m.commandExists("loginctl") {
        cmd := exec.Command("loginctl", "session-status")
        output, err := cmd.Output()

        if err == nil {
            outputStr := string(output)
            if strings.Contains(outputStr, "State: active") {
                info.Status = "unlocked"
            } else if strings.Contains(outputStr, "State: closing") {
                info.Status = "locked"
            }
        }
    }

    // Check for GNOME screensaver
    cmd := exec.Command("gdbus", "call", "--session",
        "--dest=org.gnome.ScreenSaver",
        "--object-path=/org/gnome/ScreenSaver",
        "--method org.gnome.ScreenSaver.GetActive")
    output, err := cmd.Output()

    if err == nil {
        outputStr := string(output)
        if strings.Contains(outputStr, "true") {
            info.IsScreensaver = true
            info.Status = "screensaver"
        }
    }

    // Check for screensaver using xdotool or xssstate
    if m.commandExists("xssstate") {
        cmd = exec.Command("xssstate", "-s")
        output, err = cmd.Output()

        if err == nil {
            outputStr := string(output)
            if strings.Contains(outputStr, "screen saver active") {
                info.IsScreensaver = true
                info.Status = "screensaver"
            }
        }
    }

    // Get idle time
    if m.commandExists("xprintidle") {
        cmd = exec.Command("xprintidle")
        output, err = cmd.Output()

        if err == nil {
            idleMs, _ := strconv.ParseInt(strings.TrimSpace(string(output)), 10, 64)
            info.IdleTime = time.Duration(idleMs) * time.Millisecond
        }
    }

    // Check for xscreensaver
    cmd = exec.Command("xscreensaver-command", "-time")
    output, err = cmd.Output()

    if err == nil {
        outputStr := string(output)
        if strings.Contains(outputStr, "screen saver is active") {
            info.IsScreensaver = true
            info.Status = "screensaver"
        }
    }
}

func (m *ScreenLockMonitor) commandExists(cmd string) bool {
    _, err := exec.LookPath(cmd)
    return err == nil
}

func (m *ScreenLockMonitor) processLockStatus(info *ScreenLockInfo) {
    if m.lockState == nil {
        m.lockState = info
        return
    }

    // Check for lock state changes
    if info.IsLocked && !m.lockState.IsLocked {
        m.onScreenLocked()
        info.LastLockTime = time.Now()
    }

    if !info.IsLocked && m.lockState.IsLocked {
        m.onScreenUnlocked()
        info.LastUnlockTime = time.Now()
    }

    // Check for screensaver state changes
    if info.IsScreensaver && !m.lockState.IsScreensaver {
        m.onScreensaverStarted()
    }

    if !info.IsScreensaver && m.lockState.IsScreensaver {
        m.onScreensaverStopped()
    }

    m.lockState = info
}

func (m *ScreenLockMonitor) onScreenLocked() {
    if !m.config.SoundOnLock {
        return
    }

    key := "lock:locked"
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["lock"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *ScreenLockMonitor) onScreenUnlocked() {
    if !m.config.SoundOnUnlock {
        return
    }

    key := "lock:unlocked"
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["unlock"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ScreenLockMonitor) onScreensaverStarted() {
    if !m.config.SoundOnScreensaver {
        return
    }

    key := "lock:screensaver"
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["screensaver"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *ScreenLockMonitor) onScreensaverStopped() {
    // Optional: sound when user returns
}

func (m *ScreenLockMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| pmset | System Tool | Free | Power management (macOS) |
| security | System Tool | Free | macOS security tool |
| loginctl | System Tool | Free | Systemd login manager (Linux) |
| gdbus | System Tool | Free | D-Bus (Linux) |

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
| macOS | Supported | Uses pmset, security |
| Linux | Supported | Uses loginctl, gdbus |
