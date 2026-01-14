# Feature: Sound Event SSH Connection Monitor

Play sounds for SSH connections, login attempts, and session activities.

## Summary

Monitor SSH daemon connections, authentication events, and session lifecycle, playing sounds for SSH events.

## Motivation

- Security awareness
- Remote access notifications
- Login detection
- Brute force protection
- Session management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSH Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Established | New SSH connection | User logged in |
| Login Failed | Failed authentication | Wrong password |
| Session Opened | Shell session started | Terminal opened |
| Session Closed | Shell session ended | Logout |
| Disconnection | Connection dropped | Network timeout |
| Root Login | Root user authenticated | sudo access |

### Configuration

```go
type SSHConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchUsers        []string          `json:"watch_users"` // "admin", "*"
    WatchOrigins      []string          `json:"watch_origins"` // "192.168.1.*", "*"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnRoot       bool              `json:"sound_on_root"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:ssh status                   # Show SSH status
/ccbell:ssh add user admin           # Add user to watch
/ccbell:ssh remove user admin
/ccbell:ssh sound connect <sound>
/ccbell:ssh sound fail <sound>
/ccbell:ssh test                     # Test SSH sounds
```

### Output

```
$ ccbell:ssh status

=== Sound Event SSH Connection Monitor ===

Status: Enabled
Connect Sounds: Yes
Fail Sounds: Yes
Root Sounds: Yes

Watched Users: 2
Watched Origins: 1

Active Sessions: 3

[1] admin (192.168.1.100)
    Connected: 5 min ago
    Session: pts/1
    Sound: bundled:ssh-admin

[2] root (10.0.0.50)
    Connected: 1 hour ago
    Session: pts/2
    Sound: bundled:ssh-root

[3] deploy (192.168.1.105)
    Connected: 2 hours ago
    Session: pts/3
    Sound: bundled:ssh-deploy

Recent Events:
  [1] admin: Connection Established (5 min ago)
       From: 192.168.1.100
  [2] deploy: Session Closed (1 hour ago)
       Duration: 4h 30m
  [3] root: Root Login (2 hours ago)
       From: 10.0.0.50

SSH Statistics:
  Total Sessions Today: 12
  Failed Logins: 3
  Active Connections: 3

Sound Settings:
  Connect: bundled:ssh-connect
  Fail: bundled:ssh-fail
  Root: bundled:ssh-root
  Disconnect: bundled:ssh-disconnect

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

SSH monitoring doesn't play sounds directly:
- Monitoring feature using journalctl/lastlog
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSH Connection Monitor

```go
type SSHConnectionMonitor struct {
    config          *SSHConnectionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    sessionState    map[string]*SessionInfo
    lastEventTime   map[string]time.Time
    lastLoginTime   time.Time
}

type SessionInfo struct {
    User      string
    Origin    string
    Session   string
    PID       int
    Connected time.Time
    Command   string
}

func (m *SSHConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sessionState = make(map[string]*SessionInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastLoginTime = time.Now()
    go m.monitor()
}

func (m *SSHConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSessionState()

    for {
        select {
        case <-ticker.C:
            m.checkSessionState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSHConnectionMonitor) snapshotSessionState() {
    // Get active SSH sessions
    m.getActiveSSHSessions()
}

func (m *SSHConnectionMonitor) checkSessionState() {
    // Get current sessions
    currentSessions := m.getActiveSSHSessions()

    // Check for new sessions
    for id, session := range currentSessions {
        if _, exists := m.sessionState[id]; !exists {
            m.sessionState[id] = session
            m.onSessionConnected(session)
        }
    }

    // Check for closed sessions
    for id, lastSession := range m.sessionState {
        if _, exists := currentSessions[id]; !exists {
            delete(m.sessionState, id)
            m.onSessionDisconnected(lastSession)
        }
    }

    // Check auth log for failed attempts
    m.checkFailedLogins()
}

func (m *SSHConnectionMonitor) getActiveSSHSessions() map[string]*SessionInfo {
    sessions := make(map[string]*SessionInfo)

    // Use 'who' or 'w' to get logged in users with SSH sessions
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return sessions
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) >= 5 {
            user := parts[0]
            tty := parts[1]
            date := parts[2]
            time := parts[3]
            origin := parts[4]

            // Check if it's an SSH session
            if strings.HasPrefix(tty, "pts/") || strings.HasPrefix(tty, "tty") {
                id := fmt.Sprintf("%s-%s-%s", user, tty, origin)

                sessions[id] = &SessionInfo{
                    User:      user,
                    Origin:    origin,
                    Session:   tty,
                    Connected: m.parseTime(date, time),
                }
            }
        }
    }

    return sessions
}

func (m *SSHConnectionMonitor) checkFailedLogins() {
    // Read from auth log for SSH failures
    cmd := exec.Command("journalctl", "-u", "sshd", "-t", "auth", "-p", "info", "-g", "Failed", "--since", m.lastLoginTime.Format("2006-01-02 15:04:05"), "--no-pager")
    output, err := cmd.Output()

    m.lastLoginTime = time.Now()

    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Failed password") {
            m.onLoginFailed(line)
        }
    }
}

func (m *SSHConnectionMonitor) onSessionConnected(session *SessionInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    // Check if user should be watched
    if !m.shouldWatchUser(session.User) {
        return
    }

    key := fmt.Sprintf("connect:%s", session.User)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }

    // Check for root login
    if session.User == "root" && m.config.SoundOnRoot {
        key = fmt.Sprintf("root:%s", session.Origin)
        if m.shouldAlert(key, 1*time.Hour) {
            sound := m.config.Sounds["root"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    }
}

func (m *SSHConnectionMonitor) onSessionDisconnected(session *SessionInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s", session.User)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SSHConnectionMonitor) onLoginFailed(line string) {
    if !m.config.SoundOnFail {
        return
    }

    // Extract username from failed attempt
    user := m.extractUserFromFailedLogin(line)
    origin := m.extractOriginFromFailedLogin(line)

    key := fmt.Sprintf("fail:%s:%s", user, origin)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSHConnectionMonitor) shouldWatchUser(user string) bool {
    if len(m.config.WatchUsers) == 0 {
        return true
    }

    for _, u := range m.config.WatchUsers {
        if u == "*" || u == user {
            return true
        }
    }

    return false
}

func (m *SSHConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}

func (m *SSHConnectionMonitor) parseTime(date, timeStr string) time.Time {
    // Parse "YYYY-MM-DD HH:MM" format
    layout := "2006-01-02 15:04"
    t, _ := time.Parse(layout, date+" "+timeStr)
    return t
}

func (m *SSHConnectionMonitor) extractUserFromFailedLogin(line string) string {
    re := regexp.MustCompile(`for user (\S+)`)
    match := re.FindStringSubmatch(line)
    if match != nil {
        return match[1]
    }
    return "unknown"
}

func (m *SSHConnectionMonitor) extractOriginFromFailedLogin(line string) string {
    re := regexp.MustCompile(`from (\S+)`)
    match := re.FindStringSubmatch(line)
    if match != nil {
        return match[1]
    }
    return "unknown"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| who | System Tool | Free | User sessions |
| w | System Tool | Free | User activity |
| journalctl | System Tool | Free | System logs (systemd) |
| lastlog | System Tool | Free | Last login info |

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
| macOS | Supported | Uses who, w, lastlog |
| Linux | Supported | Uses who, journalctl, lastlog |
