# Feature: Sound Event VPN Connection Monitor

Play sounds for VPN connection status changes and tunnel events.

## Summary

Monitor VPN tunnel status, connection events, and IP changes, playing sounds for VPN events.

## Motivation

- VPN awareness
- Connection status feedback
- IP change detection
- Tunnel health alerts
- Remote access monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### VPN Events

| Event | Description | Example |
|-------|-------------|---------|
| Connected | VPN tunnel established | Connected to work VPN |
| Disconnected | VPN tunnel closed | Connection lost |
| Reconnecting | Attempting reconnect | Retrying connection |
| IP Changed | VPN IP address changed | New virtual IP |
| Auth Failed | Authentication failed | Invalid credentials |

### Configuration

```go
type VPNMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    VPNType           string            `json:"vpn_type"` // "wireguard", "openvpn", "ikev2"
    Interface         string            `json:"interface"` // "wg0", "tun0", "*"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnReconnect  bool              `json:"sound_on_reconnect"`
    SoundOnAuthFail   bool              `json:"sound_on_auth_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type VPNEvent struct {
    Interface  string
    VPNType    string
    LocalIP    string
    RemoteIP   string
    Gateway    string
    Status     string // "connected", "disconnected", "reconnecting"
    EventType  string // "connect", "disconnect", "reconnect", "auth_fail", "ip_change"
}
```

### Commands

```bash
/ccbell:vpn status                    # Show VPN status
/ccbell:vpn type wireguard            # Set VPN type
/ccbell:vpn interface wg0             # Set interface
/ccbell:vpn sound connect <sound>
/ccbell:vpn sound disconnect <sound>
/ccbell:vpn test                      # Test VPN sounds
```

### Output

```
$ ccbell:vpn status

=== Sound Event VPN Connection Monitor ===

Status: Enabled
VPN Type: WireGuard
Interface: wg0
Connect Sounds: Yes
Disconnect Sounds: Yes

[1] wg0 (WireGuard)
    Status: CONNECTED
    Local IP: 10.0.0.2
    Remote IP: 203.0.113.1
    Gateway: 203.0.113.1
    Uptime: 5 days
    Handshake: 10 seconds ago
    Sound: bundled:vpn-wireguard

Recent Events:
  [1] wg0: Connected (5 min ago)
       VPN tunnel established
  [2] wg0: Reconnecting (1 hour ago)
       Handshake timeout, retrying
  [3] wg0: IP Changed (2 hours ago)
       New local IP: 10.0.0.2

VPN Statistics:
  Uptime: 5 days, 2 hours
  Disconnections: 3
  Reconnections: 2

Sound Settings:
  Connect: bundled:vpn-connect
  Disconnect: bundled:vpn-disconnect
  Reconnect: bundled:vpn-reconnect

[Configure] [Set Type] [Test All]
```

---

## Audio Player Compatibility

VPN monitoring doesn't play sounds directly:
- Monitoring feature using wg/ip commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### VPN Connection Monitor

```go
type VPNMonitor struct {
    config          *VPNMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    vpnState        map[string]*VPNInfo
    lastEventTime   map[string]time.Time
}

type VPNInfo struct {
    Interface  string
    VPNType    string
    LocalIP    string
    RemoteIP   string
    Gateway    string
    Status     string // "connected", "disconnected", "reconnecting"
    LastHandshake time.Time
    Uptime     time.Duration
}

func (m *VPNMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.vpnState = make(map[string]*VPNInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *VPNMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotVPNState()

    for {
        select {
        case <-ticker.C:
            m.checkVPNState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *VPNMonitor) snapshotVPNState() {
    if runtime.GOOS == "linux" {
        m.checkWireGuard()
        m.checkOpenVPN()
    } else {
        m.checkDarwinVPN()
    }
}

func (m *VPNMonitor) checkVPNState() {
    if runtime.GOOS == "linux" {
        m.checkWireGuard()
        m.checkOpenVPN()
    } else {
        m.checkDarwinVPN()
    }
}

func (m *VPNMonitor) checkWireGuard() {
    // Check for WireGuard interfaces
    cmd := exec.Command("wg", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    var currentInterfaces []string

    for _, line := range lines {
        if strings.HasPrefix(line, "interface:") {
            iface := strings.TrimSpace(strings.TrimPrefix(line, "interface:"))
            if m.shouldWatchInterface(iface) {
                currentInterfaces = append(currentInterfaces, iface)
                m.checkWireGuardInterface(iface, string(output))
            }
        }
    }

    // Check for removed interfaces
    for name := range m.vpnState {
        if m.config.Interface != "" && m.config.Interface != name {
            continue
        }

        found := false
        for _, iface := range currentInterfaces {
            if iface == name {
                found = true
                break
            }
        }

        if !found {
            m.onVPNDisconnected(name, m.vpnState[name])
            delete(m.vpnState, name)
        }
    }
}

func (m *VPNMonitor) checkWireGuardInterface(name string, fullOutput string) {
    info := &VPNInfo{
        Interface: name,
        VPNType:   "wireguard",
    }

    // Parse interface details
    lines := strings.Split(fullOutput, "\n")
    inInterface := false

    for _, line := range lines {
        if strings.HasPrefix(line, "interface:") {
            inInterface = true
            continue
        }

        if !inInterface || !strings.HasPrefix(line, "  ") {
            continue
        }

        line = strings.TrimSpace(line)

        if strings.HasPrefix(line, "public key:") {
            // Public key info
        } else if strings.HasPrefix(line, "listening port:") {
            // Port info
        } else if strings.HasPrefix(line, "peer:") {
            inInterface = false
        } else if strings.Contains(line, "endpoint:") {
            re := regexp.MustCompile(`endpoint: (\S+)`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                info.RemoteIP = match[1]
            }
        } else if strings.Contains(line, "allowed ips:") {
            re := regexp.MustCompile(`allowed ips: (\S+)`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                info.LocalIP = match[1]
            }
        } else if strings.HasPrefix(line, "latest handshake:") {
            handshake := strings.TrimPrefix(line, "latest handshake:")
            handshake = strings.TrimSpace(handshake)
            if handshake != "0 seconds ago" {
                info.Status = "connected"
            }
        }
    }

    m.evaluateVPNEvents(name, info)
}

func (m *VPNMonitor) checkOpenVPN() {
    // Check for OpenVPN processes
    cmd := exec.Command("pgrep", "-a", "openvpn")
    output, err := cmd.Output()
    if err != nil {
        // No OpenVPN running
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "--config") {
            // Parse config path
            re := regexp.MustExtract(`--config (\S+)`)
            // Get interface from config or process
        }
    }
}

func (m *VPNMonitor) checkDarwinVPN() {
    // Use scutil to check VPN status
    cmd := exec.Command("scutil", "-nc", "show", "VPN")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse VPN status
    m.parseDarwinVPNStatus(string(output))
}

func (m *VPNMonitor) parseDarwinVPNStatus(output string) {
    // Check for connected status
    if strings.Contains(output, "Connected : Yes") {
        // VPN is connected
    }
}

func (m *VPNMonitor) evaluateVPNEvents(name string, newInfo *VPNInfo) {
    lastInfo := m.vpnState[name]

    if lastInfo == nil {
        if newInfo.Status == "connected" {
            m.vpnState[name] = newInfo
            m.onVPNConnected(name, newInfo)
        }
        return
    }

    // Check for status changes
    if lastInfo.Status != "connected" && newInfo.Status == "connected" {
        m.onVPNConnected(name, newInfo)
    } else if lastInfo.Status == "connected" && newInfo.Status != "connected" {
        m.onVPNDisconnected(name, lastInfo)
    }

    // Check for IP changes
    if lastInfo.LocalIP != "" && newInfo.LocalIP != lastInfo.LocalIP {
        m.onVPNIPChanged(name, newInfo, lastInfo)
    }

    m.vpnState[name] = newInfo
}

func (m *VPNMonitor) shouldWatchInterface(name string) bool {
    if m.config.Interface == "" || m.config.Interface == "*" {
        return true
    }
    return m.config.Interface == name
}

func (m *VPNMonitor) onVPNConnected(name string, info *VPNInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    key := fmt.Sprintf("connect:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *VPNMonitor) onVPNDisconnected(name string, info *VPNInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *VPNMonitor) onVPNReconnecting(name string) {
    if !m.config.SoundOnReconnect {
        return
    }

    key := fmt.Sprintf("reconnect:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["reconnect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *VPNMonitor) onVPNIPChanged(name string, newInfo *VPNInfo, lastInfo *VPNInfo) {
    // Optional: sound when VPN IP changes
}

func (m *VPNMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| wg | System Tool | Free | WireGuard management |
| scutil | System Tool | Free | macOS network config |
| ip | System Tool | Free | Network interface info |

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
| macOS | Supported | Uses scutil |
| Linux | Supported | Uses wg, ip |
