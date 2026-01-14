# Feature: Sound Event Network Connection Monitor

Play sounds for network connection state changes and failures.

## Summary

Monitor network connections, connection failures, and port activity, playing sounds for connection events.

## Motivation

- Connection awareness
- Network failure alerts
- Port scan detection
- Connection leak detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Network Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Failed | Connection refused | Connection refused |
| Connection Timeout | Connection timed out | Timeout |
| Port Listening | New port opened | Port 8080 |
| Connection Spike | Many connections | > 100 connections |

### Configuration

```go
type NetworkConnectionMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchPorts         []int             `json:"watch_ports"` // 22, 80, 443
    WatchProcesses     []string          `json:"watch_processes"]
    MaxConnections     int               `json:"max_connections"` // 100 default
    SoundOnFail        bool              `json:"sound_on_fail"]
    SoundOnListen      bool              `json:"sound_on_listen"]
    SoundOnSpike       bool              `json:"sound_on_spike"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type NetworkConnectionEvent struct {
    LocalPort   int
    RemotePort  int
    State       string // "established", "time_wait", "close_wait"
    ProcessName string
    PID         int
    EventType   string
}
```

### Commands

```bash
/ccbell:conn status                   # Show connection status
/ccbell:conn add 8080                 # Add port to watch
/ccbell:conn remove 8080
/ccbell:conn sound fail <sound>
/ccbell:conn sound listen <sound>
/ccbell:conn test                     # Test connection sounds
```

### Output

```
$ ccbell:conn status

=== Sound Event Network Connection Monitor ===

Status: Enabled
Max Connections: 100
Fail Sounds: Yes
Listen Sounds: Yes

Watched Ports: 2

[1] Port 22 (SSH)
    State: LISTENING
    Connections: 5
    Sound: bundled:stop

[2] Port 443 (HTTPS)
    State: LISTENING
    Connections: 150
    Status: WARNING
    Sound: bundled:conn-warning

Recent Events:
  [1] Port 443: Connection Spike (5 min ago)
       150 connections
  [2] Port 22: Connection Failed (10 min ago)
       Connection refused
  [3] Port 8080: Port Listening (1 hour ago)
       New service started

Connection Statistics:
  Total connections: 234
  Established: 180
  Time wait: 54

Sound Settings:
  Fail: bundled:conn-fail
  Listen: bundled:stop
  Spike: bundled:conn-warning

[Configure] [Add Port] [Test All]
```

---

## Audio Player Compatibility

Network connection monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Connection Monitor

```go
type NetworkConnectionMonitor struct {
    config               *NetworkConnectionMonitorConfig
    player               *audio.Player
    running              bool
    stopCh               chan struct{}
    portConnections      map[int]int
    listeningPorts       map[int]bool
    lastFailTime         map[string]time.Time
}

func (m *NetworkConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.portConnections = make(map[int]int)
    m.listeningPorts = make(map[int]bool)
    m.lastFailTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotConnections()

    for {
        select {
        case <-ticker.C:
            m.checkConnections()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkConnectionMonitor) snapshotConnections() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinConnections()
    } else {
        m.snapshotLinuxConnections()
    }
}

func (m *NetworkConnectionMonitor) snapshotDarwinConnections() {
    cmd := exec.Command("netstat", "-an")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseNetstatOutput(string(output))
}

func (m *NetworkConnectionMonitor) snapshotLinuxConnections() {
    cmd := exec.Command("ss", "-tunapl")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSSOutput(string(output))
}

func (m *NetworkConnectionMonitor) checkConnections() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinConnections()
    } else {
        m.checkLinuxConnections()
    }
}

func (m *NetworkConnectionMonitor) checkDarwinConnections() {
    cmd := exec.Command("netstat", "-an")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseNetstatOutput(string(output))
}

func (m *NetworkConnectionMonitor) checkLinuxConnections() {
    cmd := exec.Command("ss", "-tunapl")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSSOutput(string(output))
}

func (m *NetworkConnectionMonitor) parseNetstatOutput(output string) {
    lines := strings.Split(output, "\n")
    currentPortConnections := make(map[int]int)
    currentListeningPorts := make(map[int]bool)

    for _, line := range lines {
        // Skip header lines
        if strings.HasPrefix(line, "Proto") || strings.HasPrefix(line, "Active") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        // Parse local address (last column usually contains port)
        localAddr := parts[3]
        state := parts[5]

        // Extract port number
        port := m.extractPort(localAddr)
        if port == 0 {
            continue
        }

        // Update listening ports
        if state == "LISTEN" {
            currentListeningPorts[port] = true
        }

        // Update connection count
        currentPortConnections[port]++
    }

    m.evaluateConnectionChanges(currentPortConnections, currentListeningPorts)
}

func (m *NetworkConnectionMonitor) parseSSOutput(output string) {
    lines := strings.Split(output, "\n")
    currentPortConnections := make(map[int]int)
    currentListeningPorts := make(map[int]bool)

    for _, line := range lines {
        if strings.HasPrefix(line, "Netid") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        localAddr := parts[4]
        state := parts[1]

        port := m.extractPort(localAddr)
        if port == 0 {
            continue
        }

        // Update listening ports
        if state == "LISTEN" {
            currentListeningPorts[port] = true
        }

        // Update connection count
        currentPortConnections[port]++
    }

    m.evaluateConnectionChanges(currentPortConnections, currentListeningPorts)
}

func (m *NetworkConnectionMonitor) extractPort(addr string) int {
    // Format: IP:PORT or *:PORT
    idx := strings.LastIndex(addr, ":")
    if idx == -1 {
        return 0
    }

    portStr := addr[idx+1:]
    port, err := strconv.Atoi(portStr)
    if err != nil {
        return 0
    }

    return port
}

func (m *NetworkConnectionMonitor) evaluateConnectionChanges(connections map[int]int, listening map[int]bool) {
    // Check for new listening ports
    for port := range listening {
        if !m.listeningPorts[port] && m.shouldWatchPort(port) {
            m.onPortListening(port)
        }
    }

    // Check connection spikes
    for port, count := range connections {
        if count > m.config.MaxConnections && m.shouldWatchPort(port) {
            m.onConnectionSpike(port, count)
        }
    }

    // Update state
    m.portConnections = connections
    m.listeningPorts = listening
}

func (m *NetworkConnectionMonitor) shouldWatchPort(port int) bool {
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

func (m *NetworkConnectionMonitor) onPortListening(port int) {
    if !m.config.SoundOnListen {
        return
    }

    // Only alert on specific ports
    if len(m.config.WatchPorts) > 0 && !m.shouldWatchPort(port) {
        return
    }

    sound := m.config.Sounds["listen"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *NetworkConnectionMonitor) onConnectionSpike(port int, count int) {
    if !m.config.SoundOnSpike {
        return
    }

    key := fmt.Sprintf("spike:%d", port)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["spike"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkConnectionMonitor) onConnectionFailed(port int) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%d", port)
    if m.shouldAlert(key, 2*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *NetworkConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastFailTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastFailTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| netstat | System Tool | Free | Network statistics |
| ss | System Tool | Free | Socket statistics |

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
| macOS | Supported | Uses netstat |
| Linux | Supported | Uses ss |
| Windows | Not Supported | ccbell only supports macOS/Linux |
