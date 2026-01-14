# Feature: Sound Event SSH Monitor

Play sounds for SSH connection events.

## Summary

Play sounds when SSH connections are established, failed, or closed.

## Motivation

- Security monitoring
- Connection awareness
- Server access alerts

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
| Connection | New SSH connection | User logged in |
| Failed | Failed login | Wrong password |
| Disconnected | Session ended | User disconnected |
| Session Active | Session running | Active session |

### Configuration

```go
type SSHMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 10 default
    WatchHosts    []*SSHHostWatch  `json:"watch_hosts"`
    ListenPort    int              `json:"listen_port,omitempty"` // 2222 for honey pot
    Sounds        map[string]string `json:"sounds"`
}

type SSHHostWatch struct {
    Host         string  `json:"host"` // IP or hostname
    Port         int     `json:"port"` // 22 default
    User         string  `json:"user,omitempty"` // Specific user
    Sound        string  `json:"sound"`
    Enabled      bool    `json:"enabled"`
}

type SSHConnection struct {
    User      string
    IP        string
    Port      int
    Timestamp time.Time
    Status    string // "connected", "failed", "disconnected"
}
```

### Commands

```bash
/ccbell:ssh status                  # Show SSH status
/ccbell:ssh add user@server.com     # Watch SSH host
/ccbell:ssh add 192.168.1.100 --port 22
/ccbell:ssh sound connection <sound>
/ccbell:ssh sound failed <sound>
/ccbell:ssh sound disconnected <sound>
/ccbell:ssh enable                  # Enable SSH monitoring
/ccbell:ssh disable                 # Disable SSH monitoring
/ccbell:ssh test                    # Test SSH sounds
```

### Output

```
$ ccbell:ssh status

=== Sound Event SSH Monitor ===

Status: Enabled
Check Interval: 10s

Watched Hosts: 2

[1] user@server.com
    Host: server.com:22
    Status: Connected
    Sessions: 3
    Last Activity: 5 min ago
    Sound: bundled:stop
    [Edit] [Remove]

[2] 192.168.1.100
    Host: 192.168.1.100:22
    Status: Disconnected
    Sessions: 0
    Last Activity: 2 hours ago
    Sound: bundled:stop
    [Edit] [Remove]

Recent Connections:
  [1] user → server.com (2 min ago)
  [2] root → server.com (5 min ago) [FAILED]

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

SSH monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### SSH Monitor

```go
type SSHMonitor struct {
    config   *SSHMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastState map[string]*SSHHostState
}

type SSHHostState struct {
    Connections []SSHConnection
    LastCheck   time.Time
}

func (m *SSHMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastState = make(map[string]*SSHHostState)
    go m.monitor()
}

func (m *SSHMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkHosts()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSHMonitor) checkHosts() {
    for _, host := range m.config.WatchHosts {
        if !host.Enabled {
            continue
        }

        state := m.checkSSHHost(host)
        m.evaluateState(host, state)
    }
}

func (m *SSHMonitor) checkSSHHost(host *SSHHostWatch) *SSHHostState {
    state := &SSHHostState{
        LastCheck: time.Now(),
        Connections: []SSHConnection{},
    }

    // Use 'who' or 'w' to get logged in users
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return state
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) >= 5 {
            conn := SSHConnection{
                User:      parts[0],
                Timestamp: time.Now(),
                Status:    "connected",
            }

            // Parse connection info from parts
            // parts[1] = tty, parts[2] = date, parts[3] = time, parts[4] = IP

            state.Connections = append(state.Connections, conn)
        }
    }

    return state
}

func (m *SSHMonitor) evaluateState(host *SSHHostWatch, state *SSHHostState) {
    lastState := m.lastState[host.Host]
    m.lastState[host.Host] = state

    if lastState == nil {
        return
    }

    // Check for new connections
    if len(state.Connections) > len(lastState.Connections) {
        m.playSSHEvent("connection", host.Sound)
    }

    // Check for disconnected sessions
    if len(state.Connections) < len(lastState.Connections) {
        m.playSSHEvent("disconnected", host.Sound)
    }
}

// Alternative: Use auth.log for SSH events
func (m *SSHMonitor) checkAuthLog() {
    logFile := "/var/log/auth.log"

    data, err := os.ReadFile(logFile)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.Contains(line, "sshd") {
            if strings.Contains(line, "Accepted") {
                m.playSSHEvent("connection", "default")
            } else if strings.Contains(line, "Failed") {
                m.playSSHEvent("failed", "default")
            }
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| who | System Tool | Free | Logged-in users |
| /var/log/auth.log | File | Free | SSH audit log |

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
| macOS | ✅ Supported | Uses who, last |
| Linux | ✅ Supported | Uses who, /var/log/auth.log |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
