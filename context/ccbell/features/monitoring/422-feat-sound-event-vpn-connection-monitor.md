# Feature: Sound Event VPN Connection Monitor

Play sounds for VPN connection status, tunnel changes, and reconnection events.

## Summary

Monitor VPN connections for status changes, tunnel establishment, and disconnection events, playing sounds for VPN events.

## Motivation

- VPN awareness
- Tunnel status alerts
- Reconnection feedback
- Security status
- Connection quality

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### VPN Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| VPN Connected | Tunnel established | Connected |
| VPN Disconnected | Tunnel closed | Disconnected |
| VPN Reconnecting | Re-establishing | Retrying |
| VPN Auth Failed | Authentication error | Failed |
| VPN Auth Success | Authenticated | OK |
| Tunnel Changed | Server switched | new IP |

### Configuration

```go
type VPNConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchVPNs         []string          `json:"watch_vpns"` // "WireGuard", "OpenVPN", "*"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnReconnect  bool              `json:"sound_on_reconnect"`
    SoundOnAuthFail   bool              `json:"sound_on_auth_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 15 default
}
```

### Commands

```bash
/ccbell:vpn status                   # Show VPN status
/ccbell:vpn add WireGuard            # Add VPN to watch
/ccbell:vpn remove WireGuard
/ccbell:vpn sound connect <sound>
/ccbell:vpn sound disconnect <sound>
/ccbell:vpn test                     # Test VPN sounds
```

### Output

```
$ ccbell:vpn status

=== Sound Event VPN Connection Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Reconnect Sounds: Yes

Watched VPNs: 2

VPN Status:

[1] WireGuard (wg0)
    Status: CONNECTED
    Server: us-east-1.vpn.example.com
    IP: 10.0.0.5
    Gateway: 10.0.0.1
    DNS: 10.0.0.1
    Connected: 2 hours 30 min
    Handshake: 5 min ago
    Sound: bundled:vpn-wireguard

[2] OpenVPN (office)
    Status: DISCONNECTED
    Last Server: office.vpn.example.com
    Last Disconnect: 1 day ago
    Reason: User requested
    Sound: bundled:vpn-office

Connection Details:

  WireGuard:
    Protocol: UDP 51820
    Cipher: ChaCha20-Poly1305
    Status: Secure

  OpenVPN:
    Protocol: TCP 443
    Cipher: AES-256-GCM
    Status: Not Connected

Recent VPN Events:
  [1] WireGuard: VPN Connected (2 hours ago)
       us-east-1.vpn.example.com
       Sound: bundled:vpn-connect
  [2] WireGuard: Handshake (5 min ago)
       Rekey successful
  [3] OpenVPN: VPN Disconnected (1 day ago)
       User requested disconnect

VPN Statistics:
  Total Connections Today: 1
  Disconnections: 0
  Reconnections: 0
  Avg Connection Time: 2h 30m

Sound Settings:
  Connect: bundled:vpn-connect
  Disconnect: bundled:vpn-disconnect
  Reconnect: bundled:vpn-reconnect
  Auth Fail: bundled:vpn-auth-fail

[Configure] [Add VPN] [Test All]
```

---

## Audio Player Compatibility

VPN monitoring doesn't play sounds directly:
- Monitoring feature using wg/ipsec/ovpn
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
    Name       string
    Type       string // "WireGuard", "OpenVPN", "IPSec"
    Status     string // "connected", "disconnected", "connecting", "reconnecting"
    Server     string
    LocalIP    string
    Gateway    string
    ConnectedAt time.Time
    Reconnected bool
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
    vpns := m.listVPNs()

    for _, vpn := range vpns {
        if !m.shouldWatchVPN(vpn.Name) {
            continue
        }
        m.processVPNStatus(vpn)
    }
}

func (m *VPNConnectionMonitor) listVPNs() []*VPNInfo {
    var vpns []*VPNInfo

    // Check WireGuard interfaces
    wgVPNs := m.checkWireGuard()
    vpns = append(vpns, wgVPNs...)

    // Check OpenVPN processes
    ovpnVPNs := m.checkOpenVPN()
    vpns = append(vpns, ovpnVPNs...)

    // Check IPSec tunnels
    ipsecVPNs := m.checkIPSec()
    vpns = append(vpns, ipsecVPNs...)

    return vpns
}

func (m *VPNConnectionMonitor) checkWireGuard() []*VPNInfo {
    var vpns []*VPNInfo

    // List WireGuard interfaces
    cmd := exec.Command("wg", "show")
    output, err := cmd.Output()

    if err != nil {
        return vpns
    }

    lines := strings.Split(string(output), "\n")
    currentName := ""

    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.HasPrefix(line, "interface:") {
            currentName = strings.TrimPrefix(line, "interface:")
            currentName = strings.TrimSpace(currentName)
            continue
        }

        if currentName != "" && strings.HasPrefix(line, "peer:") {
            vpn := &VPNInfo{
                Name:   currentName,
                Type:   "WireGuard",
                Status: "connected",
            }

            // Extract endpoint
            endpointRe := regexp.MustEach(`endpoint: ([0-9.:]+)`)
            matches := endpointRe.FindStringSubmatch(line)
            if len(matches) >= 2 {
                vpn.Server = matches[1]
            }

            vpns = append(vpns, vpn)
            currentName = ""
        }
    }

    // Check for wg-quick interfaces
    if runtime.GOOS == "linux" {
        wgDir := "/etc/wireguard"
        entries, _ := os.ReadDir(wgDir)
        for _, entry := range entries {
            if strings.HasSuffix(entry.Name(), ".conf") {
                name := strings.TrimSuffix(entry.Name(), ".conf")
                // Check if interface exists
                cmd := exec.Command("ip", "link", "show", name)
                if err := cmd.Run(); err == nil {
                    // Interface exists, check if it's up
                    vpn := &VPNInfo{
                        Name:   name,
                        Type:   "WireGuard",
                        Status: "connected",
                    }
                    vpns = append(vpns, vpn)
                }
            }
        }
    }

    return vpns
}

func (m *VPNConnectionMonitor) checkOpenVPN() []*VPNInfo {
    var vpns []*VPNInfo

    // Check for running OpenVPN processes
    cmd := exec.Command("pgrep", "-a", "openvpn")
    output, err := cmd.Output()

    if err != nil {
        return vpns
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 2 {
            continue
        }

        // Try to extract config name from arguments
        configName := "openvpn"
        for _, part := range parts {
            if strings.HasSuffix(part, ".conf") {
                configName = filepath.Base(part)
                configName = strings.TrimSuffix(configName, ".conf")
                break
            }
        }

        vpn := &VPNInfo{
            Name:   configName,
            Type:   "OpenVPN",
            Status: "connected",
        }

        vpns = append(vpns, vpn)
    }

    return vpns
}

func (m *VPNConnectionMonitor) checkIPSec() []*VPNInfo {
    var vpns []*VPNInfo

    // Check for IPsec tunnels
    if runtime.GOOS == "linux" {
        cmd := exec.Command("ipsec", "status")
        output, err := cmd.Output()

        if err == nil {
            // Parse IPsec status
            lines := strings.Split(string(output), "\n")
            for _, line := range lines {
                if strings.Contains(line, "ESTABLISHED") {
                    // Extract tunnel name
                    nameRe := regexp.MustEach(`([a-zA-Z0-9_-]+)\[[0-9+\]: ESTABLISHED`)
                    matches := nameRe.FindStringSubmatch(line)
                    if len(matches) >= 2 {
                        vpn := &VPNInfo{
                            Name:   matches[1],
                            Type:   "IPSec",
                            Status: "connected",
                        }
                        vpns = append(vpns, vpn)
                    }
                }
            }
        }
    }

    return vpns
}

func (m *VPNConnectionMonitor) shouldWatchVPN(name string) bool {
    if len(m.config.WatchVPNs) == 0 {
        return true
    }

    for _, v := range m.config.WatchVPNs {
        if v == "*" || name == v || strings.Contains(strings.ToLower(name), strings.ToLower(v)) {
            return true
        }
    }

    return false
}

func (m *VPNConnectionMonitor) processVPNStatus(vpn *VPNInfo) {
    lastInfo := m.vpnState[vpn.Name]

    if lastInfo == nil {
        m.vpnState[vpn.Name] = vpn
        if m.config.SoundOnConnect {
            m.onVPNConnected(vpn)
        }
        return
    }

    // Check for status changes
    if lastInfo.Status != vpn.Status {
        switch vpn.Status {
        case "connected":
            if m.config.SoundOnConnect {
                m.onVPNConnected(vpn)
            }
        case "disconnected":
            if m.config.SoundOnDisconnect {
                m.onVPNDisconnected(vpn)
            }
        case "reconnecting":
            if m.config.SoundOnReconnect {
                m.onVPNReconnecting(vpn)
            }
        }
    }

    m.vpnState[vpn.Name] = vpn
}

func (m *VPNConnectionMonitor) onVPNConnected(vpn *VPNInfo) {
    key := fmt.Sprintf("connect:%s", vpn.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *VPNConnectionMonitor) onVPNDisconnected(vpn *VPNInfo) {
    key := fmt.Sprintf("disconnect:%s", vpn.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *VPNConnectionMonitor) onVPNReconnecting(vpn *VPNInfo) {
    key := fmt.Sprintf("reconnect:%s", vpn.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["reconnect"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *VPNConnectionMonitor) onVPNAuthFail(vpn *VPNInfo) {
    key := fmt.Sprintf("auth_fail:%s", vpn.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["auth_fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
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
| ipsec | System Tool | Free | IPsec tools |
| openvpn | System Tool | Free | OpenVPN |
| pgrep | System Tool | Free | Process listing |

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
| macOS | Supported | Uses wg, pgrep |
| Linux | Supported | Uses wg, ipsec, pgrep |
