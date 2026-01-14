# Feature: Sound Event Network Port Monitor

Play sounds for network port changes, connection status, and port conflicts.

## Summary

Monitor network ports for binding status, connection attempts, and port conflicts, playing sounds for port events.

## Motivation

- Port binding awareness
- Service discovery feedback
- Conflict detection
- Connection monitoring
- Network service alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Network Port Events

| Event | Description | Example |
|-------|-------------|---------|
| Port Bound | Service started listening | 8080 |
| Port Closed | Service stopped listening | 8080 |
| Port Conflict | Multiple processes | 80 |
| New Connection | Active connection | established |
| Port Scan Detected | Multiple connection attempts | security |
| Port Unreachable | Service down | timeout |

### Configuration

```go
type NetworkPortMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPorts        []int             `json:"watch_ports"` // 80, 443, 8080, 0 for all
    WatchAddresses    []string          `json:"watch_addresses"` // "127.0.0.1", "0.0.0.0"
    SoundOnBound      bool              `json:"sound_on_bound"`
    SoundOnClosed     bool              `json:"sound_on_closed"`
    SoundOnConflict   bool              `json:"sound_on_conflict"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:port status                  # Show port status
/ccbell:port add 8080                # Add port to watch
/ccbell:port remove 8080
/ccbell:port sound bound <sound>
/ccbell:port sound closed <sound>
/ccbell:port test                    # Test port sounds
```

### Output

```
$ ccbell:port status

=== Sound Event Network Port Monitor ===

Status: Enabled
Bound Sounds: Yes
Closed Sounds: Yes
Conflict Sounds: Yes

Watched Ports: 5

Port Status:

[1] 80 (http)
    Address: 0.0.0.0:80
    Status: BOUND
    PID: 1234 (nginx)
    Protocol: TCP
    Sound: bundled:port-http

[2] 443 (https)
    Address: 0.0.0.0:443
    Status: BOUND
    PID: 1234 (nginx)
    Protocol: TCP
    Sound: bundled:port-https

[3] 5432 (postgres)
    Address: 127.0.0.1:5432
    Status: BOUND
    PID: 2345 (postgres)
    Protocol: TCP
    Sound: bundled:port-db

[4] 8080 (custom)
    Address: 127.0.0.1:8080
    Status: CLOSED
    Expected: custom-app
    Sound: bundled:port-8080 *** WARNING ***

[5] 22 (ssh)
    Address: 0.0.0.0:22
    Status: BOUND
    PID: 3456 (sshd)
    Protocol: TCP
    Sound: bundled:port-ssh

Active Connections:

  Port 22: 3 connections (正常)
  Port 80: 15 connections (正常)
  Port 443: 42 connections (正常)

Recent Events:
  [1] Port 8080: Closed (5 min ago)
       custom-app stopped listening
  [2] Port 80: Bound (1 hour ago)
       nginx started
  [3] Port 22: New Connection (2 hours ago)
       192.168.1.100 -> 22

Port Statistics:
  Total Watched: 5
  Bound: 4
  Closed: 1
  Conflicts: 0

Sound Settings:
  Bound: bundled:port-bound
  Closed: bundled:port-closed
  Conflict: bundled:port-conflict

[Configure] [Add Port] [Test All]
```

---

## Audio Player Compatibility

Port monitoring doesn't play sounds directly:
- Monitoring feature using ss/netstat/lsof
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Port Monitor

```go
type NetworkPortMonitor struct {
    config          *NetworkPortMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    portState       map[int]*PortInfo
    lastEventTime   map[string]time.Time
}

type PortInfo struct {
    Port        int
    Protocol    string
    Address     string
    PID         int
    ProcessName string
    Status      string // "bound", "closed", "unknown"
    Connections int
}

func (m *NetworkPortMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.portState = make(map[int]*PortInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkPortMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotPortState()

    for {
        select {
        case <-ticker.C:
            m.checkPortState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkPortMonitor) snapshotPortState() {
    m.checkPortState()
}

func (m *NetworkPortMonitor) checkPortState() {
    currentPorts := m.listBoundPorts()

    for _, port := range m.config.WatchPorts {
        if port == 0 {
            // Watch all ports
            for _, p := range currentPorts {
                m.processPortStatus(p)
            }
        } else {
            info := m.getPortInfo(port)
            if info != nil {
                m.processPortStatus(info)
            } else {
                // Port not bound - check if it was previously bound
                if lastInfo := m.portState[port]; lastInfo != nil {
                    m.processPortClosure(port, lastInfo)
                }
            }
        }
    }

    // Check for newly bound ports not in watch list
    for _, info := range currentPorts {
        if !m.shouldWatchPort(info.Port) {
            continue
        }
        if _, exists := m.portState[info.Port]; !exists {
            m.processPortStatus(info)
        }
    }
}

func (m *NetworkPortMonitor) listBoundPorts() []*PortInfo {
    var ports []*PortInfo

    // Try ss first (modern)
    cmd := exec.Command("ss", "-tlnp")
    output, err := cmd.Output()
    if err == nil {
        ports = m.parseSSOutput(string(output))
    }

    // Fallback to netstat
    if len(ports) == 0 {
        cmd = exec.Command("netstat", "-tlnp")
        output, err = cmd.Output()
        if err == nil {
            ports = m.parseNetstatOutput(string(output))
        }
    }

    return ports
}

func (m *NetworkPortMonitor) parseSSOutput(output string) []*PortInfo {
    var ports []*PortInfo
    lines := strings.Split(output, "\n")

    for _, line := range lines {
        if strings.HasPrefix(line, "State") || strings.HasPrefix(line, "LISTEN") {
            continue
        }

        line = strings.TrimSpace(line)
        parts := strings.Fields(line)

        if len(parts) < 4 {
            continue
        }

        // Parse: State  Recv-Q  Send-Q  Local Address:Port  Peer Address:Port
        localAddr := parts[3]
        portInfo := m.parseAddressPort(localAddr)

        if portInfo != nil && (m.config.WatchPorts[0] == 0 ||
           containsPort(m.config.WatchPorts, portInfo.Port)) {
            // Get process info
            portInfo.ProcessName = m.getProcessName(portInfo.Port)
            portInfo.PID = m.getPIDForPort(portInfo.Port)
            portInfo.Status = "bound"
            ports = append(ports, portInfo)
        }
    }

    return ports
}

func (m *NetworkPortMonitor) parseNetstatOutput(output string) []*PortInfo {
    var ports []*PortInfo
    lines := strings.Split(output, "\n")

    for _, line := range lines {
        if strings.HasPrefix(line, "Proto") || strings.HasPrefix(line, "tcp") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        localAddr := parts[3]
        portInfo := m.parseAddressPort(localAddr)

        if portInfo != nil {
            portInfo.ProcessName = m.getProcessName(portInfo.Port)
            portInfo.Status = "bound"
            ports = append(ports, portInfo)
        }
    }

    return ports
}

func (m *NetworkPortMonitor) parseAddressPort(addr string) *PortInfo {
    // Parse: 0.0.0.0:80 or [::]:443
    hostPort := addr
    if strings.Contains(addr, ":") {
        parts := strings.SplitN(addr, ":", 2)
        hostPort = parts[1]
    }

    port, err := strconv.Atoi(hostPort)
    if err != nil {
        return nil
    }

    return &PortInfo{
        Port:     port,
        Address:  addr,
        Protocol: "TCP",
    }
}

func (m *NetworkPortMonitor) getPortInfo(port int) *PortInfo {
    // Use lsof to get port info
    cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port), "-t")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }
        pid, _ := strconv.Atoi(line)
        return &PortInfo{
            Port: port,
            PID:  pid,
        }
    }

    return nil
}

func (m *NetworkPortMonitor) getPIDForPort(port int) int {
    cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port), "-t")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line != "" {
            pid, _ := strconv.Atoi(line)
            return pid
        }
    }

    return 0
}

func (m *NetworkPortMonitor) getProcessName(pid int) string {
    if pid == 0 {
        return "unknown"
    }
    cmd := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "comm=")
    output, err := cmd.Output()
    if err != nil {
        return "unknown"
    }
    return strings.TrimSpace(string(output))
}

func (m *NetworkPortMonitor) processPortStatus(info *PortInfo) {
    lastInfo := m.portState[info.Port]

    if lastInfo == nil {
        m.portState[info.Port] = info
        if m.config.SoundOnBound {
            m.onPortBound(info)
        }
        return
    }

    // Check for status changes
    if lastInfo.Status == "closed" && info.Status == "bound" {
        m.portState[info.Port] = info
        if m.config.SoundOnBound {
            m.onPortBound(info)
        }
    }

    m.portState[info.Port] = info
}

func (m *NetworkPortMonitor) processPortClosure(port int, lastInfo *PortInfo) {
    if lastInfo.Status == "bound" {
        if m.config.SoundOnClosed {
            m.onPortClosed(port, lastInfo)
        }
    }
    delete(m.portState, port)
}

func (m *NetworkPortMonitor) shouldWatchPort(port int) bool {
    if len(m.config.WatchPorts) == 0 || m.config.WatchPorts[0] == 0 {
        return true
    }

    for _, p := range m.config.WatchPorts {
        if p == port {
            return true
        }
    }

    return false
}

func (m *NetworkPortMonitor) onPortBound(info *PortInfo) {
    key := fmt.Sprintf("bound:%d", info.Port)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["bound"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkPortMonitor) onPortClosed(port int, info *PortInfo) {
    key := fmt.Sprintf("closed:%d", port)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["closed"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkPortMonitor) onPortConflict(info *PortInfo) {
    key := fmt.Sprintf("conflict:%d", info.Port)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["conflict"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkPortMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}

func containsPort(ports []int, port int) bool {
    for _, p := range ports {
        if p == port {
            return true
        }
    }
    return false
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ss | System Tool | Free | Socket statistics (iproute2) |
| netstat | System Tool | Free | Network statistics |
| lsof | System Tool | Free | List open files |
| ps | System Tool | Free | Process status |

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
| macOS | Supported | Uses lsof, ps |
| Linux | Supported | Uses ss, netstat, lsof, ps |
