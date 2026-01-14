# Feature: Sound Event VPN Monitor

Play sounds for VPN connection events.

## Summary

Monitor VPN connections, tunnel status, and network security changes, playing sounds for VPN-related events.

## Motivation

- VPN connection feedback
- Security awareness
- Tunnel status alerts
- Disconnection warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### VPN Events

| Event | Description | Example |
|-------|-------------|---------|
| VPN Connected | Tunnel established | Connected to work VPN |
| VPN Disconnected | Tunnel closed | Disconnected |
| VPN Reconnecting | Connection dropped | Retrying connection |
| VPN Auth Failed | Authentication error | Invalid credentials |
| Tunnel Active | Tunnel is healthy | Connected |

### Configuration

```go
type VPNMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchVPNs          []string          `json:"watch_vpns"` // VPN names
    SoundOnConnect     bool              `json:"sound_on_connect"`
    SoundOnDisconnect  bool              `json:"sound_on_disconnect"`
    SoundOnError       bool              `json:"sound_on_error"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type VPNEvent struct {
    VPNName   string
    EventType string // "connected", "disconnected", "reconnecting", "auth_failed"
    Server    string
    IPAddress string
}
```

### Commands

```bash
/ccbell:vpn status                # Show VPN status
/ccbell:vpn add "Work VPN"        # Add VPN to watch
/ccbell:vpn remove "Work VPN"     # Remove VPN
/ccbell:vpn connect on            # Enable connect sounds
/ccbell:vpn sound connected <sound>
/ccbell:vpn sound disconnected <sound>
/ccbell:vpn test                  # Test VPN sounds
```

### Output

```
$ ccbell:vpn status

=== Sound Event VPN Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Active VPN: Work VPN
  Status: Connected
  Server: vpn.company.com
  IP: 10.0.0.50
  Duration: 2 hours
  Sound: bundled:stop

Watched VPNs: 2

[1] Work VPN
    Status: Connected
    Sound: bundled:stop
    [Edit] [Remove]

[2] Personal VPN
    Status: Disconnected
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] Work VPN: Connected (2 hours ago)
  [2] Personal VPN: Disconnected (1 day ago)
  [3] Personal VPN: Auth Failed (1 day ago)

Sound Settings:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Error: bundled:stop

[Configure] [Add VPN] [Test All]
```

---

## Audio Player Compatibility

VPN monitoring doesn't play sounds directly:
- Monitoring feature using VPN management tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### VPN Monitor

```go
type VPNMonitor struct {
    config      *VPNMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    vpnStates   map[string]string
    activeVPN   string
}

func (m *VPNMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.vpnStates = make(map[string]string)
    go m.monitor()
}

func (m *VPNMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkVPNStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *VPNMonitor) checkVPNStatus() {
    vpns := m.getVPNConnections()

    for _, vpn := range vpns {
        if m.shouldWatch(vpn) {
            status := m.getVPNStatus(vpn)
            m.evaluateVPN(vpn, status)
        }
    }
}

func (m *VPNMonitor) getVPNConnections() []string {
    var vpns []string

    if runtime.GOOS == "darwin" {
        vpns = m.getMacOSVPNConnections()
    } else if runtime.GOOS == "linux" {
        vpns = m.getLinuxVPNConnections()
    }

    return vpns
}

func (m *VPNMonitor) getMacOSVPNConnections() []string {
    var vpns []string

    cmd := exec.Command("scutil", "--nc", "list")
    output, err := cmd.Output()
    if err != nil {
        return vpns
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "VPN") || strings.Contains(line, "IPSec") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                vpns = append(vpns, parts[1])
            }
        }
    }

    return vpns
}

func (m *VPNMonitor) getLinuxVPNConnections() []string {
    var vpns []string

    // Check for WireGuard interfaces
    cmd := exec.Command("ip", "link", "show")
    output, err := cmd.Output()
    if err != nil {
        return vpns
    }

    if strings.Contains(string(output), "wg0") {
        vpns = append(vpns, "WireGuard")
    }

    // Check for OpenVPN processes
    cmd = exec.Command("pgrep", "-a", "openvpn")
    output, err = cmd.Output()
    if err == nil {
        vpns = append(vpns, "OpenVPN")
    }

    // Check for anyconnect
    cmd = exec.Command("pgrep", "-a", "vpn")
    output, err = cmd.Output()
    if err == nil && strings.Contains(string(output), "anyconnect") {
        vpns = append(vpns, "Cisco AnyConnect")
    }

    return vpns
}

func (m *VPNMonitor) shouldWatch(vpn string) bool {
    if len(m.config.WatchVPNs) == 0 {
        return true
    }

    for _, v := range m.config.WatchVPNs {
        if strings.Contains(vpn, v) {
            return true
        }
    }

    return false
}

func (m *VPNMonitor) getVPNStatus(vpn string) string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSVPNStatus(vpn)
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxVPNStatus(vpn)
    }
    return "unknown"
}

func (m *VPNMonitor) getMacOSVPNStatus(vpn string) string {
    cmd := exec.Command("scutil", "--nc", "show", vpn)
    output, err := cmd.Output()
    if err != nil {
        return "disconnected"
    }

    if strings.Contains(string(output), "Connected") {
        return "connected"
    }
    if strings.Contains(string(output), "Disconnect") {
        return "disconnected"
    }
    if strings.Contains(string(output), "Connecting") {
        return "connecting"
    }

    return "disconnected"
}

func (m *VPNMonitor) getLinuxVPNStatus(vpn string) string {
    // Check tunnel interface
    cmd := exec.Command("ip", "tuntap", "list")
    output, err := cmd.Output()
    if err != nil {
        return "disconnected"
    }

    if strings.Contains(string(output), "tun0") || strings.Contains(string(output), "wg0") {
        return "connected"
    }

    return "disconnected"
}

func (m *VPNMonitor) evaluateVPN(vpn string, status string) {
    lastStatus := m.vpnStates[vpn]
    m.vpnStates[vpn] = status

    // Track active VPN
    if status == "connected" && lastStatus != "connected" {
        m.activeVPN = vpn
        m.onVPNConnected(vpn)
    } else if status == "disconnected" && lastStatus == "connected" {
        if m.activeVPN == vpn {
            m.activeVPN = ""
        }
        m.onVPNDisconnected(vpn)
    } else if status == "connecting" && lastStatus != "connecting" {
        m.onVPNReconnecting(vpn)
    } else if status == "auth_failed" {
        m.onVPNAuthFailed(vpn)
    }
}

func (m *VPNMonitor) onVPNConnected(vpn string) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *VPNMonitor) onVPNDisconnected(vpn string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *VPNMonitor) onVPNReconnecting(vpn string) {
    sound := m.config.Sounds["reconnecting"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *VPNMonitor) onVPNAuthFailed(vpn string) {
    if !m.config.SoundOnError {
        return
    }

    sound := m.config.Sounds["auth_failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| scutil | System Tool | Free | macOS network config |
| ip | iproute2 | Free | Linux network config |
| pgrep | procps | Free | Process checking |

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
| macOS | Supported | Uses scutil for IKEv2/L2TP |
| Linux | Supported | Uses ip and pgrep |
| Windows | Not Supported | ccbell only supports macOS/Linux |
