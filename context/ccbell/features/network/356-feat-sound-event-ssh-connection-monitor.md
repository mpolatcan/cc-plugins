# Feature: Sound Event SSH Connection Monitor

Play sounds for SSH connection events, authentication attempts, and session activities.

## Summary

Monitor SSH daemon connections, authentication attempts, session activities, and security events, playing sounds for SSH events.

## Motivation

- SSH security awareness
- Brute force detection
- Session tracking
- Connection feedback
- Unauthorized access alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSH Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Opened | New SSH connection | User connected |
| Connection Closed | SSH session ended | User disconnected |
| Failed Login | Authentication failed | Invalid password |
| Root Login | Root user login | root login detected |
| Session Idle | Session idle timeout | Idle for 10 min |
| Port Forward | Port forward created | Local port forward |

### Configuration

```go
type SSHConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Port              int               `json:"port"` // 22 default
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnRoot       bool              `json:"sound_on_root"`
    WatchUsers        []string          `json:"watch_users"` // "root", "admin", "*"
    Sounds           map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type SSHConnectionEvent struct {
    User       string
    IP         string
    Port       int
    SessionID  string
    AuthMethod string // "password", "pubkey", "keyboard-interactive"
    EventType  string // "connect", "disconnect", "fail", "root", "idle"
}
```

### Commands

```bash
/ccbell:ssh status                    # Show SSH status
/ccbell:ssh add root                  # Add user to watch
/ccbell:ssh remove root
/ccbell:ssh sound connect <sound>
/ccbell:ssh sound fail <sound>
/ccbell:ssh test                      # Test SSH sounds
```

### Output

```
$ ccbell:ssh status

=== Sound Event SSH Connection Monitor ===

Status: Enabled
Port: 22
Connect Sounds: Yes
Disconnect Sounds: Yes
Failed Login Sounds: Yes

Active Sessions:

[1] admin (192.168.1.100)
    Session: 12345
    Connected: 2 hours ago
    Idle: 5 min
    Auth: pubkey
    Sound: bundled:ssh-admin

[2] deploy (10.0.0.50)
    Session: 12346
    Connected: 30 min ago
    Idle: 0 min
    Auth: password
    Sound: bundled:ssh-deploy

Recent Events:
  [1] root: Connection Opened (5 min ago)
       203.0.113.50 (pubkey)
  [2] admin: Connection Closed (10 min ago)
       Session ended by client
  [3] unknown: Failed Login (1 hour ago)
       5 failed attempts from 10.0.0.1

SSH Statistics:
  Total connections today: 45
  Failed logins: 12
  Active sessions: 2

Sound Settings:
  Connect: bundled:ssh-connect
  Disconnect: bundled:ssh-disconnect
  Fail: bundled:ssh-fail
  Root: bundled:ssh-root

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

SSH monitoring doesn't play sounds directly:
- Monitoring feature using ss/netstat
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
}

type SessionInfo struct {
    User       string
    IP         string
    Port       int
    SessionID  string
    AuthMethod string
    ConnectedAt time.Time
    LastActive time.Time
}

func (m *SSHConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sessionState = make(map[string]*SessionInfo)
    m.lastEventTime = make(map[string]time.Time)
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
    m.checkSessionState()
}

func (m *SSHConnectionMonitor) checkSessionState() {
    cmd := exec.Command("ss", "-tnp", "sport", "=", fmt.Sprintf(":%d", m.config.Port))
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentSessions := m.parseSSOutput(string(output))

    // Check for new sessions
    for key, session := range currentSessions {
        if _, exists := m.sessionState[key]; !exists {
            m.sessionState[key] = session
            m.onSSHConnected(session)
        }
    }

    // Check for closed sessions
    for key, lastSession := range m.sessionState {
        if _, exists := currentSessions[key]; !exists {
            delete(m.sessionState, key)
            m.onSSHDisconnected(lastSession)
        }
    }
}

func (m *SSHConnectionMonitor) parseSSOutput(output string) map[string]*SessionInfo {
    sessions := make(map[string]*SessionInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "State") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        // Parse: ESTAB 0 0 192.168.1.100:22 10.0.0.50:54321 users:(("sshd",pid=12345,fd=3))
        localAddr := parts[3]
        remoteAddr := parts[4]

        // Extract remote IP
        remoteIP := strings.Split(remoteAddr, ":")[0]

        // Extract PID from users field
        re := regexp.MustCompile(`pid=(\d+)`)
        match := re.FindStringSubmatch(line)
        if match == nil {
            continue
        }

        pid, _ := strconv.Atoi(match[1])

        // Get process info
        user := m.getProcessUser(pid)
        if user == "" {
            user = "unknown"
        }

        key := fmt.Sprintf("%s:%s", remoteIP, pid)
        sessions[key] = &SessionInfo{
            User:       user,
            IP:         remoteIP,
            Port:       m.config.Port,
            SessionID:  match[1],
            ConnectedAt: time.Now(),
            LastActive: time.Now(),
        }
    }

    return sessions
}

func (m *SSHConnectionMonitor) getProcessUser(pid int) string {
    cmd := exec.Command("ps", "-o", "user=", "-p", strconv.Itoa(pid))
    output, err := cmd.Output()
    if err != nil {
        return ""
    }
    return strings.TrimSpace(string(output))
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

func (m *SSHConnectionMonitor) onSSHConnected(session *SessionInfo) {
    if !m.shouldWatchUser(session.User) {
        return
    }

    if session.User == "root" && m.config.SoundOnRoot {
        key := fmt.Sprintf("root:%s", session.IP)
        if m.shouldAlert(key, 30*time.Minute) {
            sound := m.config.Sounds["root"]
            if sound != "" {
                m.player.Play(sound, 0.6)
            }
        }
    }

    if !m.config.SoundOnConnect {
        return
    }

    key := fmt.Sprintf("connect:%s:%s", session.User, session.IP)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SSHConnectionMonitor) onSSHDisconnected(session *SessionInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s:%s", session.User, session.IP)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SSHConnectionMonitor) onSSHFailedLogin(ip, user string) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s:%s", user, ip)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSHConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ss | System Tool | Free | Socket statistics |
| netstat | System Tool | Free | Network stats |
| ps | System Tool | Free | Process info |

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
| macOS | Supported | Uses ss, netstat |
| Linux | Supported | Uses ss, netstat |
