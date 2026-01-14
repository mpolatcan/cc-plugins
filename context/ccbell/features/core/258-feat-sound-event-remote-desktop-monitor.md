# Feature: Sound Event Remote Desktop Monitor

Play sounds for remote desktop connections and session events.

## Summary

Monitor remote desktop connections (SSH, VNC, RDP), playing sounds when remote sessions are established or terminated.

## Motivation

- Remote access awareness
- Session security alerts
- Connection feedback
- Disconnection detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Remote Desktop Events

| Event | Description | Example |
|-------|-------------|---------|
| SSH Connected | SSH session opened | ssh user@host |
| SSH Disconnected | SSH session closed | Connection closed |
| VNC Connected | VNC session started | Screen sharing |
| RDP Connected | RDP session established | mstsc /v:host |
| SFTP Connected | File transfer started | sftp user@host |

### Configuration

```go
type RemoteDesktopMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchUsers         []string          `json:"watch_users"`
    SoundOnConnect     bool              `json:"sound_on_connect"`
    SoundOnDisconnect  bool              `json:"sound_on_disconnect"`
    SoundOnVNC         bool              `json:"sound_on_vnc"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type RemoteDesktopEvent struct {
    UserName   string
    SessionType string // "ssh", "vnc", "rdp", "sftp"
    RemoteIP   string
    EventType  string // "connected", "disconnected"
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:remote-desktop status        # Show remote desktop status
/ccbell:remote-desktop add user      # Add user to watch
/ccbell:remote-desktop sound connect <sound>
/ccbell:remote-desktop sound disconnect <sound>
/ccbell:remote-desktop test          # Test remote sounds
```

### Output

```
$ ccbell:remote-desktop status

=== Sound Event Remote Desktop Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Current Sessions: 2

[1] SSH (user@192.168.1.100)
    Connected: 5 min ago
    Session ID: 12345
    Sound: bundled:stop

[2] VNC (Screen Sharing)
    Connected: 1 hour ago
    From: 192.168.1.50
    Sound: bundled:stop

Recent Events:
  [1] SSH: user Connected (5 min ago)
       From 192.168.1.100
  [2] VNC: Connected (1 hour ago)
       From 192.168.1.50
  [3] SSH: user Disconnected (2 hours ago)

Sound Settings:
  SSH Connect: bundled:stop
  SSH Disconnect: bundled:stop
  VNC Connect: bundled:stop

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

Remote desktop monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Remote Desktop Monitor

```go
type RemoteDesktopMonitor struct {
    config         *RemoteDesktopMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    activeSessions map[string]*RemoteSession
}

type RemoteSession struct {
    UserName     string
    SessionType  string
    RemoteIP     string
    SessionID    string
    StartTime    time.Time
}
```

```go
func (m *RemoteDesktopMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeSessions = make(map[string]*RemoteSession)
    go m.monitor()
}

func (m *RemoteDesktopMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSessions()
        case <-m.stopCh:
            return
        }
    }
}

func (m *RemoteDesktopMonitor) checkSessions() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinSessions()
    } else {
        m.checkLinuxSessions()
    }
}

func (m *RemoteDesktopMonitor) checkDarwinSessions() {
    // Check for SSH connections
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 8 {
            continue
        }

        user := parts[0]
        tty := parts[1]
        ip := parts[7]

        // Check if this is an SSH session
        if strings.HasPrefix(tty, "ttys") {
            session := &RemoteSession{
                UserName:  user,
                SessionType: "ssh",
                RemoteIP: ip,
                SessionID: tty,
                StartTime: time.Now(),
            }
            m.evaluateSession(session)
        }
    }

    // Check for screen sharing (VNC)
    cmd = exec.Command("ps", "aux")
    output, err = cmd.Output()
    if err != nil {
        return
    }

    if strings.Contains(string(output), "screencapture") ||
       strings.Contains(string(output), "vino-server") {
        // VNC session active
        m.onVNCConnected()
    }
}

func (m *RemoteDesktopMonitor) checkLinuxSessions() {
    // Check for SSH connections
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 8 {
            continue
        }

        user := parts[0]
        tty := parts[1]
        ip := parts[7]

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
                continue
            }
        }

        session := &RemoteSession{
            UserName:  user,
            SessionType: "ssh",
            RemoteIP: ip,
            SessionID: fmt.Sprintf("%s-%s", tty, time.Now().Format("150405")),
            StartTime: time.Now(),
        }
        m.evaluateSession(session)
    }

    // Check for VNC servers
    cmd = exec.Command("ps", "aux")
    output, err = cmd.Output()
    if err != nil {
        return
    }

    if strings.Contains(string(output), "Xvnc") ||
       strings.Contains(string(output), "x11vnc") {
        m.onVNCConnected()
    }
}

func (m *RemoteDesktopMonitor) evaluateSession(session *RemoteSession) {
    key := session.UserName + "-" + session.SessionType

    if m.activeSessions[key] == nil {
        // New session
        m.activeSessions[key] = session
        m.onSessionConnected(session)
    }
}

func (m *RemoteDesktopMonitor) onSessionConnected(session *RemoteSession) {
    if !m.config.SoundOnConnect {
        return
    }

    if session.SessionType == "ssh" {
        sound := m.config.Sounds["ssh_connect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *RemoteDesktopMonitor) onSessionDisconnected(session *RemoteSession) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnect"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *RemoteDesktopMonitor) onVNCConnected() {
    if !m.config.SoundOnVNC {
        return
    }

    sound := m.config.Sounds["vnc_connect"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| who | System Tool | Free | User sessions |
| ps | System Tool | Free | Process list |
| Xvnc | System Tool | Free | Linux VNC server |

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
| macOS | Supported | Uses who, ps |
| Linux | Supported | Uses who, ps, Xvnc |
| Windows | Not Supported | ccbell only supports macOS/Linux |
