# Feature: Sound Event VPN Monitor

Play sounds for VPN connection status changes, disconnections, and tunnel events.

## Summary

Monitor VPN connections (OpenVPN, WireGuard, IPSec) for connection state changes, tunnel status, and security events, playing sounds for VPN events.

## Motivation

- VPN awareness
- Connection monitoring
- Security alerts
- Tunnel status
- Reconnection feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### VPN Events

| Event | Description | Example |
|-------|-------------|---------|
| VPN Connected | Tunnel established | connected |
| VPN Disconnected | Tunnel closed | disconnected |
| Handshake Failed | Auth failed | handshake |
| Reconnecting | Attempting reconnect | retrying |
| Traffic Allowed | Split tunnel allow | allowed |
| Traffic Blocked | Kill switch active | blocked |

### Configuration

```go
type VPNMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchVPNs         []string          `json:"watch_vpns"` // "wg0", "tun0", "*"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnReconnect  bool              `json:"sound_on_reconnect"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:vpn status                  # Show VPN status
/ccbell:vpn add wg0                 # Add VPN to watch
/ccbell:vpn sound connect <sound>
/ccbell:vpn test                    # Test VPN sounds
```

### Output

```
$ ccbell:vpn status

=== Sound Event VPN Monitor ===

Status: Enabled
Watch VPNs: all

VPN Status:

[1] wg0 (WireGuard)
    Status: CONNECTED
    Interface: wg0
    Public Key: xxxxx...xxxxx
    Endpoint: vpn.example.com:51820
    Handshake: 30s ago
    Transfer: 1.2 GB RX, 500 MB TX
    Sound: bundled:vpn-wg

[2] tun0 (OpenVPN)
    Status: DISCONNECTED *** DOWN ***
    Server: vpn.corp.com:1194
    Last Error: TLS handshake failed
    Attempts: 3/5
    Sound: bundled:vpn-ovpn *** FAILED ***

Recent Events:

[1] tun0: Disconnected (5 min ago)
       TLS handshake failed
       Sound: bundled:vpn-disconnect
  [2] wg0: Connected (1 hour ago)
       Tunnel established
       Sound: bundled:vpn-connect
  [3] tun0: Reconnecting (2 hours ago)
       Retry attempt 2/5
       Sound: bundled:vpn-reconnect

VPN Statistics:
  Total VPNs: 2
  Connected: 1
  Disconnected: 1

Sound Settings:
  Connect: bundled:vpn-connect
  Disconnect: bundled:vpn-disconnect
  Failed: bundled:vpn-failed
  Reconnect: bundled:vpn-reconnect

[Configure] [Add VPN] [Test All]
```

---

## Audio Player Compatibility

VPN monitoring doesn't play sounds directly:
- Monitoring feature using wg, ip, pgrep
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### VPN Monitor

```go
type VPNMonitor struct {
    config        *VPNMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    vpnState      map[string]*VPNInfo
    lastEventTime map[string]time.Time
}

type VPNInfo struct {
    Name        string
    Type        string // "wireguard", "openvpn", "ipsec"
    Status      string // "connected", "disconnected", "connecting", "failed"
    Interface   string
    Endpoint    string
    PublicKey   string
    TransferRX  int64
    TransferTX  int64
    Handshake   time.Time
    LastError   string
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
    m.checkVPNState()
}

func (m *VPNMonitor) checkVPNState() {
    // Check WireGuard
    m.checkWireGuard()

    // Check OpenVPN
    m.checkOpenVPN()

    // Check generic tunnels
    m.checkGenericTunnels()
}

func (m *VPNMonitor) checkWireGuard() {
    // Get WireGuard interfaces
    cmd := exec.Command("wg", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    var currentVPN *VPNInfo

    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.HasPrefix(line, "interface:") {
            if currentVPN != nil {
                m.processVPNStatus(currentVPN)
            }
            currentVPN = &VPNInfo{
                Name:      strings.TrimPrefix(line, "interface:"),
                Type:      "wireguard",
                Interface: strings.TrimPrefix(line, "interface:"),
            }
        } else if strings.HasPrefix(line, "peer:") && currentVPN != nil {
            // Extract public key
            currentVPN.PublicKey = strings.TrimPrefix(line, "peer:")
        } else if strings.HasPrefix(line, "endpoint:") && currentVPN != nil {
            currentVPN.Endpoint = strings.TrimPrefix(line, "endpoint:")
        } else if strings.HasPrefix(line, "latest handshake:") && currentVPN != nil {
            handshakeStr := strings.TrimPrefix(line, "latest handshake:")
            currentVPN.Handshake = m.parseHandshake(handshakeStr)
        } else if strings.HasPrefix(line, "transfer:") && currentVPN != nil {
            transferStr := strings.TrimPrefix(line, "transfer:")
            rx, tx := m.parseTransfer(transferStr)
            currentVPN.TransferRX = rx
            currentVPN.TransferTX = tx
        }
    }

    if currentVPN != nil {
        currentVPN.Status = "connected"
        m.processVPNStatus(currentVPN)
    }
}

func (m *VPNMonitor) parseHandshake(handshakeStr string) time.Time {
    handshakeStr = strings.TrimSpace(handshakeStr)

    // Parse "1 minute, 30 seconds ago" format
    re := regexp.MustEach(`(\d+)\s*(second|minute|hour|day)`)
    matches := re.FindAllStringSubmatch(handshakeStr, -1)

    var duration time.Duration
    for _, match := range matches {
        if len(match) >= 3 {
            value, _ := strconv.Atoi(match[1])
            switch match[2] {
            case "second":
                duration += time.Duration(value) * time.Second
            case "minute":
                duration += time.Duration(value) * time.Minute
            case "hour":
                duration += time.Duration(value) * time.Hour
            case "day":
                duration += time.Duration(value) * 24 * time.Hour
            }
        }
    }

    return time.Now().Add(-duration)
}

func (m *VPNMonitor) parseTransfer(transferStr string) (int64, int64) {
    // Parse "1.23 MiB received, 456.78 KiB sent"
    rx := int64(0)
    tx := int64(0)

    parts := strings.Split(transferStr, ",")
    for _, part := range parts {
        part = strings.TrimSpace(part)

        re := regexp.MustEach(`([\d.]+)\s*(KiB|MiB|GiB|TiB)\s*(received|sent)`)
        matches := re.FindStringSubmatch(part)

        if len(matches) >= 4 {
            value, _ := strconv.ParseFloat(matches[1], 64)
            multiplier := m.getByteMultiplier(matches[2])
            bytes := int64(value * float64(multiplier))

            if matches[3] == "received" {
                rx = bytes
            } else {
                tx = bytes
            }
        }
    }

    return rx, tx
}

func (m *VPNMonitor) getByteMultiplier(unit string) int64 {
    switch unit {
    case "KiB":
        return 1024
    case "MiB":
        return 1024 * 1024
    case "GiB":
        return 1024 * 1024 * 1024
    case "TiB":
        return 1024 * 1024 * 1024 * 1024
    default:
        return 1
    }
}

func (m *VPNMonitor) checkOpenVPN() {
    // Check for running OpenVPN processes
    cmd := exec.Command("pgrep", "-a", "openvpn")
    output, err := cmd.Output()

    if err != nil || len(output) == 0 {
        // Check if we have a known VPN that should be connected
        for _, vpnName := range m.config.WatchVPNs {
            if strings.Contains(vpnName, "openvpn") || vpnName == "ovpn" {
                info := &VPNInfo{
                    Name:   vpnName,
                    Type:   "openvpn",
                    Status: "disconnected",
                }
                m.processVPNStatus(info)
            }
        }
        return
    }

    // Parse OpenVPN status
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "openvpn") {
            // Extract interface name
            parts := strings.Fields(line)
            for _, part := range parts {
                if strings.HasPrefix(part, "--dev") || strings.HasPrefix(part, "tun") {
                    info := &VPNInfo{
                        Name:      part,
                        Type:      "openvpn",
                        Interface: part,
                        Status:    "connected",
                    }
                    m.processVPNStatus(info)
                    break
                }
            }
        }
    }
}

func (m *VPNMonitor) checkGenericTunnels() {
    // Check for tunnel interfaces
    cmd := exec.Command("ip", "tunnel", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) >= 3 {
            tunnelName := parts[0]
            if m.shouldWatchVPN(tunnelName) {
                info := &VPNInfo{
                    Name:      tunnelName,
                    Type:      "generic",
                    Interface: tunnelName,
                    Status:    "connected",
                }
                m.processVPNStatus(info)
            }
        }
    }
}

func (m *VPNMonitor) processVPNStatus(info *VPNInfo) {
    if !m.shouldWatchVPN(info.Name) {
        return
    }

    lastInfo := m.vpnState[info.Name]

    if lastInfo == nil {
        m.vpnState[info.Name] = info

        if info.Status == "connected" && m.config.SoundOnConnect {
            m.onVPNConnected(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "connected":
            if lastInfo.Status == "disconnected" || lastInfo.Status == "failed" {
                if m.config.SoundOnConnect {
                    m.onVPNConnected(info)
                }
            }
        case "disconnected":
            if lastInfo.Status == "connected" {
                if m.config.SoundOnDisconnect {
                    m.onVPNDisconnected(info)
                }
            }
        case "failed":
            if m.config.SoundOnFailed {
                m.onVPNFailed(info)
            }
        case "connecting":
            if m.config.SoundOnReconnect {
                m.onVPNReconnecting(info)
            }
        }
    }

    m.vpnState[info.Name] = info
}

func (m *VPNMonitor) shouldWatchVPN(name string) bool {
    for _, vpn := range m.config.WatchVPNs {
        if vpn == "*" || vpn == name || strings.Contains(name, vpn) {
            return true
        }
    }
    return false
}

func (m *VPNMonitor) onVPNConnected(info *VPNInfo) {
    key := fmt.Sprintf("connect:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *VPNMonitor) onVPNDisconnected(info *VPNInfo) {
    key := fmt.Sprintf("disconnect:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *VPNMonitor) onVPNFailed(info *VPNInfo) {
    key := fmt.Sprintf("failed:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *VPNMonitor) onVPNReconnecting(info *VPNInfo) {
    sound := m.config.Sounds["reconnect"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
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
| wg | System Tool | Free | WireGuard CLI |
| ip | System Tool | Free | Network interface tool |
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
| macOS | Supported | Uses wg, ip (via wireguard-go) |
| Linux | Supported | Uses wg, ip |
