# Feature: Sound Event VPN Connection Monitor

Play sounds for VPN connection status, tunnel events, and IP changes.

## Summary

Monitor VPN connections for connected/disconnected states, tunnel status, and IP address changes, playing sounds for VPN events.

## Motivation

- VPN awareness
- Connection status alerts
- Tunnel health monitoring
- IP change detection
- Secure connection feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### VPN Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Connected | VPN established | tunnel up |
| Disconnected | VPN lost | tunnel down |
| Reconnecting | Attempting reconnect | retrying |
| IP Changed | New VPN IP | 10.0.0.x |
| Tunnel Up | GRE/IPsec OK | secure |
| Tunnel Down | Tunnel broken | timeout |

### Configuration

```go
type VPNConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchConnections  []string          `json:"watch_connections"` // "tun0", "wg0", "ppp0", "*"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnIPChange   bool              `json:"sound_on_ip_change"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:vpn status                     # Show VPN status
/ccbell:vpn add tun0                   # Add connection to watch
/ccbell:vpn remove tun0
/ccbell:vpn sound connect <sound>
/ccbell:vpn sound disconnect <sound>
/ccbell:vpn test                       # Test VPN sounds
```

### Output

```
$ ccbell:vpn status

=== Sound Event VPN Connection Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
IP Change Sounds: Yes

Watched Connections: 2

VPN Connections:

[1] tun0 (WireGuard)
    Status: Connected
    Local IP: 10.0.0.2
    Remote IP: 203.0.113.50
    Gateway: 203.0.113.1
    Uptime: 2 days
    Traffic: 1.5 GB / 500 MB
    Sound: bundled:vpn-wireguard

[2] ppp0 (OpenVPN)
    Status: Disconnected
    Last IP: 198.51.100.25
    Last Seen: 1 hour ago
    Disconnect Reason: Network changed
    Sound: bundled:vpn-openvpn *** DISCONNECTED ***

Recent Events:
  [1] tun0: Connected (2 days ago)
       WireGuard tunnel established
  [2] ppp0: Disconnected (1 hour ago)
       Network changed
  [3] tun0: IP Changed (3 days ago)
       10.0.0.3 -> 10.0.0.2

VPN Statistics:
  Total Connections: 2
  Connected: 1
  Disconnections Today: 3
  Uptime (tun0): 48h 30m

Sound Settings:
  Connect: bundled:vpn-connect
  Disconnect: bundled:vpn-disconnect
  IP Change: bundled:vpn-ip

[Configure] [Add Connection] [Test All]
```

---

## Audio Player Compatibility

VPN monitoring doesn't play sounds directly:
- Monitoring feature using wg/ip/ifconfig
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### VPN Connection Monitor

```go
type VPNConnectionMonitor struct {
    config          *VPNConnectionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    vpnState        map[string]*VPNInfo
    lastEventTime   map[string]time.Time
}

type VPNInfo struct {
    Interface   string
    Type        string // "wireguard", "openvpn", "ipsec", "pptp"
    Status      string // "connected", "disconnected", "connecting"
    LocalIP     string
    RemoteIP    string
    Gateway     string
    Uptime      time.Duration
    TrafficIn   int64
    TrafficOut  int64
    LastCheck   time.Time
}

func (m *VPNConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.vpnState = make(map[string]*VPNInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *VPNConnectionMonitor) monitor() {
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

func (m *VPNConnectionMonitor) snapshotVPNState() {
    m.checkVPNState()
}

func (m *VPNConnectionMonitor) checkVPNState() {
    // Check for WireGuard interfaces
    m.checkWireGuardInterfaces()

    // Check for generic VPN interfaces
    m.checkGenericVPNInterfaces()
}

func (m *VPNConnectionMonitor) checkWireGuardInterfaces() {
    // List WireGuard interfaces
    cmd := exec.Command("wg", "show", "interfaces")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        info := m.getWireGuardStatus(line)
        if info != nil {
            m.processVPNStatus(line, info)
        }
    }
}

func (m *VPNConnectionMonitor) getWireGuardStatus(iface string) *VPNInfo {
    info := &VPNInfo{
        Interface: iface,
        Type:      "wireguard",
        LastCheck: time.Now(),
    }

    // Get interface status
    cmd := exec.Command("wg", "show", iface, "latest-handshakes")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "disconnected"
        return info
    }

    // Check if we have recent handshakes
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) >= 2 {
            handshakeSec, _ := strconv.ParseInt(parts[1], 10, 64)
            if handshakeSec < 300 { // 5 minutes
                info.Status = "connected"
                break
            }
        }
    }

    if info.Status == "" {
        info.Status = "connecting"
    }

    // Get IP address
    cmd = exec.Command("ip", "addr", "show", iface)
    output, _ = cmd.Output()

    re := regexp.MustEach(`inet (\d+\.\d+\.\d+\.\d+)`)
    matches := re.FindAllStringSubmatch(string(output), -1)
    if len(matches) > 0 {
        info.LocalIP = matches[0][1]
    }

    return info
}

func (m *VPNConnectionMonitor) checkGenericVPNInterfaces() {
    // Check common VPN interface names
    vpnPrefixes := []string{"tun", "tap", "ppp", "wg"}

    for _, prefix := range vpnPrefixes {
        cmd := exec.Command("ifconfig", "-l")
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        lines := strings.Split(string(output), " ")
        for _, line := range lines {
            line = strings.TrimSpace(line)
            if strings.HasPrefix(line, prefix) {
                if _, exists := m.vpnState[line]; !exists {
                    info := m.getInterfaceStatus(line)
                    if info != nil {
                        m.processVPNStatus(line, info)
                    }
                }
            }
        }
    }
}

func (m *VPNConnectionMonitor) getInterfaceStatus(iface string) *VPNInfo {
    info := &VPNInfo{
        Interface: iface,
        LastCheck: time.Now(),
    }

    // Get interface status
    cmd := exec.Command("ifconfig", iface)
    output, err := cmd.Output()
    if err != nil {
        info.Status = "disconnected"
        return info
    }

    outputStr := string(output)

    if strings.Contains(outputStr, "UP") {
        info.Status = "connected"

        // Get IP address
        re := regexp.MustEach(`inet (\d+\.\d+\.\d+\.\d+)`)
        matches := re.FindAllStringSubmatch(outputStr, -1)
        if len(matches) > 0 {
            info.LocalIP = matches[0][1]
        }
    } else {
        info.Status = "disconnected"
    }

    return info
}

func (m *VPNConnectionMonitor) processVPNStatus(iface string, info *VPNInfo) {
    if !m.shouldWatchConnection(iface) {
        return
    }

    lastInfo := m.vpnState[iface]

    if lastInfo == nil {
        m.vpnState[iface] = info
        if info.Status == "connected" {
            m.onVPNConnected(iface, info)
        }
        return
    }

    // Check for status changes
    if lastInfo.Status != info.Status {
        if info.Status == "connected" {
            m.onVPNConnected(iface, info)
        } else if info.Status == "disconnected" {
            m.onVPNDisconnected(iface, info, lastInfo)
        }
    }

    // Check for IP changes
    if info.LocalIP != "" && lastInfo.LocalIP != "" && info.LocalIP != lastInfo.LocalIP {
        if m.config.SoundOnIPChange {
            m.onIPChanged(iface, info, lastInfo)
        }
    }

    m.vpnState[iface] = info
}

func (m *VPNConnectionMonitor) onVPNConnected(iface string, info *VPNInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    key := fmt.Sprintf("connect:%s", iface)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *VPNConnectionMonitor) onVPNDisconnected(iface string, info, lastInfo *VPNInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s", iface)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *VPNConnectionMonitor) onIPChanged(iface string, info, lastInfo *VPNInfo) {
    if !m.config.SoundOnIPChange {
        return
    }

    key := fmt.Sprintf("ipchange:%s", iface)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["ip_change"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *VPNConnectionMonitor) shouldWatchConnection(iface string) bool {
    if len(m.config.WatchConnections) == 0 {
        return true
    }

    for _, c := range m.config.WatchConnections {
        if c == "*" || c == iface {
            return true
        }
    }

    return false
}

func (m *VPNConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| wg | System Tool | Free | WireGuard CLI |
| ifconfig | System Tool | Free | Network config |
| ip | System Tool | Free | Network config |

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
| macOS | Supported | Uses ifconfig, wg (if installed) |
| Linux | Supported | Uses ip, wg, ifconfig |
