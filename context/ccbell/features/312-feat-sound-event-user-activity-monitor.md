# Feature: Sound Event User Activity Monitor

Play sounds for user login sessions and activity events.

## Summary

Monitor user login sessions, session activity, and user switches, playing sounds for user events.

## Motivation

- User awareness
- Session security
- Login detection
- Activity feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### User Activity Events

| Event | Description | Example |
|-------|-------------|---------|
| User Login | New session started | ssh user@host |
| User Logout | Session ended | logout |
| User Switch | Fast user switching | Switched to user |
| Sudo Use | Elevated privileges | sudo command |

### Configuration

```go
type UserActivityMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchUsers    []string          `json:"watch_users"] // "root", "admin"
    SoundOnLogin  bool              `json:"sound_on_login"]
    SoundOnLogout bool              `json:"sound_on_logout"]
    SoundOnSudo   bool              `json:"sound_on_sudo"]
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 10 default
}

type UserActivityEvent struct {
    User      string
    TTY       string
    From      string
    PID       int
    EventType string // "login", "logout", "switch", "sudo"
}
```

### Commands

```bash
/ccbell:user status                   # Show user activity status
/ccbell:user add root                 # Add user to watch
/ccbell:user remove root
/ccbell:user sound login <sound>
/ccbell:user sound sudo <sound>
/ccbell:user test                     # Test user sounds
```

### Output

```
$ ccbell:user status

=== Sound Event User Activity Monitor ===

Status: Enabled
Login Sounds: Yes
Sudo Sounds: Yes

Watched Users: 2

[1] root
    Active Sessions: 2
    Last Login: 5 min ago
    Sudo Uses Today: 10
    Sound: bundled:stop

[2] admin
    Active Sessions: 1
    Last Login: 1 hour ago
    Sudo Uses Today: 5
    Sound: bundled:stop

Recent Events:
  [1] admin: User Login (5 min ago)
       tty1 from :0
  [2] root: Sudo Use (10 min ago)
       apt update
  [3] admin: User Logout (1 hour ago)
       tty1

User Statistics (Today):
  Logins: 5
  Logouts: 3
  Sudo Uses: 15

Sound Settings:
  Login: bundled:user-login
  Logout: bundled:stop
  Sudo: bundled:user-sudo

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

User activity monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### User Activity Monitor

```go
type UserActivityMonitor struct {
    config          *UserActivityMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    activeSessions  map[string]*SessionInfo
    lastEventTime   map[string]time.Time
}

type SessionInfo struct {
    User      string
    TTY       string
    PID       int
    LoginTime time.Time
    From      string
}

func (m *UserActivityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeSessions = make(map[string]*SessionInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *UserActivityMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotUserSessions()

    for {
        select {
        case <-ticker.C:
            m.checkUserActivity()
        case <-m.stopCh:
            return
        }
    }
}

func (m *UserActivityMonitor) snapshotUserSessions() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinSessions()
    } else {
        m.snapshotLinuxSessions()
    }
}

func (m *UserActivityMonitor) snapshotDarwinSessions() {
    // Use who and last
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseWhoOutput(string(output))
}

func (m *UserActivityMonitor) snapshotLinuxSessions() {
    // Use who and w
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseWhoOutput(string(output))
}

func (m *UserActivityMonitor) checkUserActivity() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinActivity()
    } else {
        m.checkLinuxActivity()
    }
}

func (m *UserActivityMonitor) checkDarwinActivity() {
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseWhoOutput(string(output))

    // Also check for sudo usage
    m.checkSudoUsage()
}

func (m *UserActivityMonitor) checkLinuxActivity() {
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseWhoOutput(string(output))

    // Check for sudo usage
    m.checkSudoUsage()
}

func (m *UserActivityMonitor) parseWhoOutput(output string) {
    lines := strings.Split(output, "\n")
    currentSessions := make(map[string]*SessionInfo)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        user := parts[0]
        tty := parts[1]
        timeStr := parts[2]

        // Check if we should watch this user
        if len(m.config.WatchUsers) > 0 {
            shouldWatch := false
            for _, watchUser := range m.config.WatchUsers {
                if user == watchUser {
                    shouldWatch = true
                    break
                }
            }
            if !shouldWatch {
                continue
            }
        }

        sessionKey := fmt.Sprintf("%s:%s", user, tty)
        currentSessions[sessionKey] = &SessionInfo{
            User:      user,
            TTY:       tty,
            LoginTime: m.parseTime(timeStr),
        }
    }

    // Check for new sessions
    for key, session := range currentSessions {
        if _, exists := m.activeSessions[key]; !exists {
            m.onUserLogin(session)
        }
    }

    // Check for ended sessions
    for key, lastSession := range m.activeSessions {
        if _, exists := currentSessions[key]; !exists {
            m.onUserLogout(lastSession)
        }
    }

    m.activeSessions = currentSessions
}

func (m *UserActivityMonitor) checkSudoUsage() {
    // Check auth log for sudo usage
    var logPath string
    if runtime.GOOS == "darwin" {
        logPath = "/var/log/system.log"
    } else {
        logPath = "/var/log/auth.log"
        if _, err := os.Stat(logPath); os.IsNotExist(err) {
            logPath = "/var/log/syslog"
        }
    }

    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    recentTime := time.Now().Add(-time.Duration(m.config.PollInterval) * time.Second)

    for _, line := range lines {
        if strings.Contains(line, "sudo:") && strings.Contains(line, "COMMAND") {
            timestamp := m.extractLogTimestamp(line)
            if timestamp.After(recentTime) {
                m.onSudoUsage(line)
            }
        }
    }
}

func (m *UserActivityMonitor) onUserLogin(session *SessionInfo) {
    if !m.config.SoundOnLogin {
        return
    }

    if len(m.config.WatchUsers) > 0 {
        shouldWatch := false
        for _, user := range m.config.WatchUsers {
            if session.User == user {
                shouldWatch = true
                break
            }
        }
        if !shouldWatch {
            return
        }
    }

    key := fmt.Sprintf("login:%s", session.User)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["login"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserActivityMonitor) onUserLogout(session *SessionInfo) {
    if !m.config.SoundOnLogout {
        return
    }

    key := fmt.Sprintf("logout:%s", session.User)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["logout"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserActivityMonitor) onSudoUsage(line string) {
    if !m.config.SoundOnSudo {
        return
    }

    // Extract username from sudo log
    parts := strings.Split(line, " ")
    for i, part := range parts {
        if part == "COMMAND=" {
            command := strings.Trim(strings.Join(parts[i+1:], " "), `"`)
            user := m.extractUserFromLine(line)

            if len(m.config.WatchUsers) > 0 {
                shouldWatch := false
                for _, watchUser := range m.config.WatchUsers {
                    if user == watchUser {
                        shouldWatch = true
                        break
                    }
                }
                if !shouldWatch {
                    return
                }
            }

            key := fmt.Sprintf("sudo:%s", user)
            if m.shouldAlert(key, 2*time.Minute) {
                sound := m.config.Sounds["sudo"]
                if sound != "" {
                    m.player.Play(sound, 0.5)
                }
            }
            break
        }
    }
}

func (m *UserActivityMonitor) parseTime(timeStr string) time.Time {
    // Parse who output time format (e.g., "Jan 14 10:30")
    now := time.Now()
    layout := "Jan 02 15:04"
    t, err := time.Parse(layout, timeStr)
    if err != nil {
        return now
    }
    return t
}

func (m *UserActivityMonitor) extractLogTimestamp(line string) time.Time {
    // Extract timestamp from syslog/auth.log
    parts := strings.SplitN(line, " ", 3)
    if len(parts) < 2 {
        return time.Now()
    }

    // Format: "Jan 14 10:30:45"
    now := time.Now()
    layout := "Jan 02 15:04:05"
    t, err := time.Parse(layout, parts[1]+" "+parts[2][:8])
    if err != nil {
        return now
    }
    return t
}

func (m *UserActivityMonitor) extractUserFromLine(line string) string {
    // Extract username from sudo log line
    re := regexp.MustCompile(`([a-zA-Z0-9_-]+):`)
    match := re.FindStringSubmatch(line)
    if match != nil {
        return match[1]
    }
    return ""
}

func (m *UserActivityMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| who | System Tool | Free | User sessions |
| /var/log/auth.log | File | Free | Sudo logs |
| /var/log/system.log | File | Free | macOS logs |

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
| macOS | Supported | Uses who, /var/log/system.log |
| Linux | Supported | Uses who, /var/log/auth.log |
| Windows | Not Supported | ccbell only supports macOS/Linux |
