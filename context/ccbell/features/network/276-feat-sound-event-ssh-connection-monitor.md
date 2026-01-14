# Feature: Sound Event SSH Connection Monitor

Play sounds for SSH connection establishment and termination.

## Summary

Monitor SSH connections, tunnel activity, and remote session events, playing sounds for SSH activity.

## Motivation

- Remote access awareness
- Connection security alerts
- Session detection
- Tunnel activity feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### SSH Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Opened | SSH session started | ssh user@host |
| Connection Closed | Session terminated | Connection closed |
| Tunnel Created | Port forward | -L 8080:localhost:80 |
| Auth Failed | Authentication error | Permission denied |
| SFTP Transfer | File transfer started | sftp upload |

### Configuration

```go
type SSHConnectionMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchUsers       []string          `json:"watch_users"`
    WatchHosts       []string          `json:"watch_hosts"`
    SoundOnConnect   bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool             `json:"sound_on_disconnect"]
    SoundOnAuthFail  bool              `json:"sound_on_auth_fail"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type SSHConnectionEvent struct {
    UserName   string
    HostName   string
    RemoteIP   string
    LocalPort  int
    RemotePort int
    EventType  string // "connect", "disconnect", "auth_fail", "tunnel"
}
```

### Commands

```bash
/ccbell:ssh status                 # Show SSH status
/ccbell:ssh add user               # Add user to watch
/ccbell:ssh remove user
/ccbell:ssh sound connect <sound>
/ccbell:ssh sound disconnect <sound>
/ccbell:ssh test                   # Test SSH sounds
```

### Output

```
$ ccbell:ssh status

=== Sound Event SSH Connection Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Current Connections: 2

[1] user@192.168.1.100 (pts/0)
    Connected: 5 min ago
    From: 192.168.1.50
    Duration: 5 min
    Sound: bundled:stop

[2] admin@server.example.com
    Connected: 1 hour ago
    From: 10.0.0.25
    Port Forward: 8080 -> 10.0.0.1:80
    Sound: bundled:stop

Recent Events:
  [1] user@192.168.1.100: Connected (5 min ago)
  [2] admin@server.example.com: Tunnel Created (1 hour ago)
  [3] user@192.168.1.100: Disconnected (2 hours ago)

Sound Settings:
  Connect: bundled:stop
  Disconnect: bundled:stop
  Auth Fail: bundled:stop
  Tunnel: bundled:stop

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

SSH monitoring doesn't play sounds directly:
- Monitoring feature using system tools
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
    activeSessions  map[string]*SSHSession
}

type SSHSession struct {
    UserName   string
    HostName   string
    RemoteIP   string
    TTY        string
    PID        int
    StartTime  time.Time
}
```

```go
func (m *SSHConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeSessions = make(map[string]*SSHSession)
    go m.monitor()
}

func (m *SSHConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSSHConnections()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSHConnectionMonitor) checkSSHConnections() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinSSH()
    } else {
        m.checkLinuxSSH()
    }
}

func (m *SSHConnectionMonitor) checkDarwinSSH() {
    // Use who and ps to find SSH sessions
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "sshd") || strings.Contains(line, "pts") {
            session := m.parseWhoLine(line)
            if session != nil {
                m.evaluateSession(session)
            }
        }
    }
}

func (m *SSHConnectionMonitor) checkLinuxSSH() {
    // Check active SSH sessions using who and lastlog
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "sshd") || strings.Contains(line, "pts") {
            session := m.parseWhoLine(line)
            if session != nil {
                m.evaluateSession(session)
            }
        }
    }

    // Also check for SSH processes directly
    m.checkSSHProcesses()
}

func (m *SSHConnectionMonitor) parseWhoLine(line string) *SSHSession {
    parts := strings.Fields(line)
    if len(parts) < 7 {
        return nil
    }

    user := parts[0]
    tty := parts[1]
    ip := parts[6]

    // Check user filter
    if len(m.config.WatchUsers) > 0 {
        found := false
        for _, watchUser := range m.config.WatchUsers {
            if user == watchUser {
                found = true
                break
            }
        }
        if !found {
            return nil
        }
    }

    return &SSHSession{
        UserName: user,
        TTY:      tty,
        RemoteIP: ip,
    }
}

func (m *SSHConnectionMonitor) checkSSHProcesses() {
    // Find sshd processes
    cmd := exec.Command("pgrep", "-a", "sshd")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 2 {
            continue
        }

        pid, _ := strconv.Atoi(parts[0])
        cmdLine := strings.Join(parts[1:], " ")

        // Check for sshd with specific user
        if strings.Contains(cmdLine, "-o") {
            // Parse SSH options
            re := regexp.MustCompile(`-o\s+RemoteUser=(\w+)`)
            match := re.FindStringSubmatch(cmdLine)
            if len(match) >= 2 {
                session := &SSHSession{
                    UserName: match[1],
                    PID:      pid,
                }
                m.evaluateSession(session)
            }
        }
    }
}

func (m *SSHConnectionMonitor) evaluateSession(session *SSHSession) {
    key := fmt.Sprintf("%s-%s", session.UserName, session.TTY)

    if m.activeSessions[key] == nil {
        // New session
        session.StartTime = time.Now()
        m.activeSessions[key] = session
        m.onSSHConnected(session)
    }
}

func (m *SSHConnectionMonitor) onSSHConnected(session *SSHSession) {
    if !m.config.SoundOnConnect {
        return
    }

    // Check host filter
    if len(m.config.WatchHosts) > 0 {
        for _, host := range m.config.WatchHosts {
            if strings.Contains(session.HostName, host) {
                m.playConnectSound()
                return
            }
        }
    }

    m.playConnectSound()
}

func (m *SSHConnectionMonitor) onSSHDisconnected(session *SSHSession) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("%s-%s", session.UserName, session.TTY)
    delete(m.activeSessions, key)

    m.playDisconnectSound()
}

func (m *SSHConnectionMonitor) onAuthFailed(userName string) {
    if !m.config.SoundOnAuthFail {
        return
    }

    sound := m.config.Sounds["auth_fail"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *SSHConnectionMonitor) playConnectSound() {
    sound := m.config.Sounds["connect"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SSHConnectionMonitor) playDisconnectSound() {
    sound := m.config.Sounds["disconnect"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| who | System Tool | Free | User sessions |
| pgrep | System Tool | Free | Process checking |
| sshd | System Tool | Free | SSH daemon |

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
| macOS | Supported | Uses who, pgrep |
| Linux | Supported | Uses who, pgrep, sshd |
| Windows | Not Supported | ccbell only supports macOS/Linux |
