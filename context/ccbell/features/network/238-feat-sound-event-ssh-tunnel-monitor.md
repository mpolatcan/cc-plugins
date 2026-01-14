# Feature: Sound Event SSH Tunnel Monitor

Play sounds for SSH tunnel and port forwarding events.

## Summary

Monitor SSH tunnels, port forwards, and remote connections, playing sounds for SSH tunnel events.

## Motivation

- Tunnel establishment feedback
- Port forward alerts
- Remote connection awareness
- Security monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### SSH Tunnel Events

| Event | Description | Example |
|-------|-------------|---------|
| Tunnel Started | SSH tunnel established | Local port forward |
| Tunnel Closed | SSH tunnel ended | Connection closed |
| Port Forward | New port forward | 8080 -> remote:80 |
| Connection Active | Tunnel is active | Connected |
| Tunnel Failed | Connection error | Connection refused |

### Configuration

```go
type SSHTunnelMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchPorts      []int             `json:"watch_ports"` // Local ports
    WatchHosts      []string          `json:"watch_hosts"` // Remote hosts
    SoundOnConnect  bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool            `json:"sound_on_disconnect"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 10 default
}

type SSHTunnelEvent struct {
    LocalPort  int
    RemoteHost string
    RemotePort int
    EventType  string // "started", "closed", "active", "failed"
    PID        int
}
```

### Commands

```bash
/ccbell:ssh-tunnel status         # Show SSH tunnel status
/ccbell:ssh-tunnel add 8080       # Add port to watch
/ccbell:ssh-tunnel connect on     # Enable connect sounds
/ccbell:ssh-tunnel sound started <sound>
/ccbell:ssh-tunnel sound closed <sound>
/ccbell:ssh-tunnel test           # Test SSH tunnel sounds
```

### Output

```
$ ccbell:ssh-tunnel status

=== Sound Event SSH Tunnel Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Active Tunnels: 2

[1] Local: 8080 -> remote.example.com:80
    PID: 12345
    Status: Active
    Duration: 2 hours
    Sound: bundled:stop

[2] Local: 2222 -> server.internal:22
    PID: 12346
    Status: Active
    Duration: 30 min
    Sound: bundled:stop

Recent Events:
  [1] Tunnel 8080 -> remote.example.com:80 (2 hours ago)
  [2] Tunnel 2222 -> server.internal:22 (30 min ago)
  [3] Tunnel 9090 -> db.internal:5432 closed (1 day ago)

Sound Settings:
  Started: bundled:stop
  Closed: bundled:stop
  Failed: bundled:stop

[Configure] [Add Port] [Test All]
```

---

## Audio Player Compatibility

SSH tunnel monitoring doesn't play sounds directly:
- Monitoring feature using process and network tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSH Tunnel Monitor

```go
type SSHTunnelMonitor struct {
    config        *SSHTunnelMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    activeTunnels map[int]bool
}

func (m *SSHTunnelMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeTunnels = make(map[int]bool)
    go m.monitor()
}

func (m *SSHTunnelMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkTunnels()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSHTunnelMonitor) checkTunnels() {
    tunnels := m.getActiveTunnels()

    for port, isActive := range tunnels {
        wasActive := m.activeTunnels[port]
        m.activeTunnels[port] = isActive

        if isActive && !wasActive {
            m.onTunnelStarted(port)
        } else if !isActive && wasActive {
            m.onTunnelClosed(port)
        }
    }
}

func (m *SSHTunnelMonitor) getActiveTunnels() map[int]bool {
    tunnels := make(map[int]bool)

    // Find SSH processes with port forwarding
    cmd := exec.Command("ps", "ax")
    output, err := cmd.Output()
    if err != nil {
        return tunnels
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "ssh") && strings.Contains(line, "-L") {
            // Parse local port from -L flag
            port := m.parseLocalPort(line)
            if port > 0 {
                if m.shouldWatchPort(port) {
                    tunnels[port] = true
                }
            }
        }
    }

    return tunnels
}

func (m *SSHTunnelMonitor) parseLocalPort(sshLine string) int {
    // Parse: ssh -L 8080:localhost:80 user@host
    match := regexp.MustCompile(`-L\s+(\d+):`).FindStringSubmatch(sshLine)
    if match != nil {
        port, _ := strconv.Atoi(match[1])
        return port
    }
    return 0
}

func (m *SSHTunnelMonitor) shouldWatchPort(port int) bool {
    if len(m.config.WatchPorts) == 0 {
        return true
    }

    for _, p := range m.config.WatchPorts {
        if p == port {
            return true
        }
    }

    return false
}

func (m *SSHTunnelMonitor) onTunnelStarted(port int) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SSHTunnelMonitor) onTunnelClosed(port int) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["closed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SSHTunnelMonitor) onTunnelFailed(port int) {
    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | procps | Free | Process listing |
| ssh | OpenSSH | Free | SSH client |

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
| macOS | Supported | Uses ps and ssh |
| Linux | Supported | Uses ps and ssh |
| Windows | Not Supported | ccbell only supports macOS/Linux |
