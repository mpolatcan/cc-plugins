# Feature: Sound Event VPN Connection Monitor

Play sounds for VPN connection status changes.

## Summary

Monitor VPN connections, tunnel establishment, and disconnection events, playing sounds for VPN status changes.

## Motivation

- VPN connection feedback
- Tunnel establishment alerts
- Disconnection warnings
- Security status awareness

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
| VPN Connected | Tunnel established | OpenVPN connected |
| VPN Disconnected | Tunnel closed | Connection lost |
| Reconnecting | Retrying connection | Re-authenticating |
| Auth Failed | Authentication error | Invalid credentials |

### Configuration

```go
type VPNMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    VPNNames          []string          `json:"vpn_names"` // "Work VPN", "Personal VPN"
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnReconnect  bool              `json:"sound_on_reconnect"`
    SoundOnAuthFail   bool              `json:"sound_on_auth_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type VPNEvent struct {
    VPNName    string
    EventType  string // "connected", "disconnected", "reconnecting", "auth_failed"
    ServerIP   string
    Duration   time.Duration
}
```

### Commands

```bash
/ccbell:vpn status                # Show VPN status
/ccbell:vpn add "Work VPN"        # Add VPN to watch
/ccbell:vpn remove "Work VPN"
/ccbell:vpn sound connect <sound>
/ccbell:vpn sound disconnect <sound>
/ccbell:vpn test                  # Test VPN sounds
```

### Output

```
$ ccbell:vpn status

=== Sound Event VPN Connection Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Current Connection: Work VPN
  Status: Connected (2 hours)
  Server: vpn.work.com
  IP: 10.0.0.55
  Protocol: IKEv2

Available VPNs:
  [1] Work VPN (Connected)
  [2] Personal VPN (Disconnected)

Recent Events:
  [1] Work VPN: Connected (2 hours ago)
       Server: vpn.work.com
  [2] Personal VPN: Disconnected (1 day ago)
  [3] Work VPN: Reconnecting (3 days ago)

Sound Settings:
  Connect: bundled:stop
  Disconnect: bundled:stop
  Reconnecting: bundled:stop

[Configure] [Add VPN] [Test All]
```

---

## Audio Player Compatibility

VPN monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### VPN Monitor

```go
type VPNMonitor struct {
    config         *VPNMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    vpnState       map[string]*VPNStatus
    lastStatus     map[string]string
}

type VPNStatus struct {
    Name       string
    Connected  bool
    ServerIP   string
    ConnectTime time.Time
}
```

```go
func (m *VPNMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.vpnState = make(map[string]*VPNStatus)
    m.lastStatus = make(map[string]string)
    go m.monitor()
}

func (m *VPNMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkVPN()
        case <-m.stopCh:
            return
        }
    }
}

func (m *VPNMonitor) checkVPN() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinVPN()
    } else {
        m.checkLinuxVPN()
    }
}

func (m *VPNMonitor) checkDarwinVPN() {
    // Use scutil to check VPN status
    cmd := exec.Command("scutil", "--nc", "list")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if !strings.Contains(line, "VPN") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        vpnName := parts[2]

        // Check status
        statusCmd := exec.Command("scutil", "--nc", "show", vpnName)
        statusOutput, _ := statusCmd.Output()

        isConnected := strings.Contains(string(statusOutput), "Connected")

        m.evaluateVPNStatus(vpnName, isConnected)
    }
}

func (m *VPNMonitor) checkLinuxVPN() {
    // Check for various VPN clients
    vpnMethods := []string{
        m.checkOpenVPN,
        m.checkWireGuard,
        m.checkIPSec,
    }

    for _, check := range vpnMethods {
        check()
    }
}

func (m *VPNMonitor) checkOpenVPN() {
    // Check for openvpn processes
    cmd := exec.Command("pgrep", "-a", "openvpn")
    output, err := cmd.Output()

    if err == nil && len(output) > 0 {
        // Extract VPN name from process args
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "--config") {
                parts := strings.Fields(line)
                for i, part := range parts {
                    if part == "--config" && i+1 < len(parts) {
                        vpnName := filepath.Base(parts[i+1])
                        m.evaluateVPNStatus(vpnName, true)
                    }
                }
            }
        }
    }

    // Check tun interfaces
    m.checkTUNInterfaces()
}

func (m *VPNMonitor) checkWireGuard() {
    // Check for wg interfaces
    cmd := exec.Command("wg", "show")
    output, err := cmd.Output()

    if err == nil && len(output) > 0 {
        lines := strings.Split(string(output), "\n")
        if len(lines) > 0 && strings.Contains(lines[0], "interface") {
            parts := strings.Fields(lines[0])
            if len(parts) >= 2 {
                vpnName := parts[1]
                m.evaluateVPNStatus(vpnName, true)
            }
        }
    }
}

func (m *VPNMonitor) checkIPSec() {
    // Check for racoon or strongSwan processes
    cmd := exec.Command("pgrep", "-a", "racoon|strongswan")
    _, err := cmd.Output()

    if err == nil {
        m.evaluateVPNStatus("IPSec VPN", true)
    }
}

func (m *VPNMonitor) checkTUNInterfaces() {
    // Check for tun devices
    interfaces, _ := filepath.Glob("/sys/class/net/tun*")
    for _, iface := range interfaces {
        name := filepath.Base(iface)
        m.evaluateVPNStatus(name, true)
    }
}

func (m *VPNMonitor) evaluateVPNStatus(name string, connected bool) {
    lastState := m.lastStatus[name]
    currentState := "disconnected"
    if connected {
        currentState = "connected"
    }

    if lastState == "" {
        // First check
        m.lastStatus[name] = currentState
        if connected {
            m.onVPNConnected(name)
        }
        return
    }

    if lastState != currentState {
        m.lastStatus[name] = currentState

        if connected {
            m.onVPNConnected(name)
        } else {
            m.onVPNDisconnected(name)
        }
    }
}

func (m *VPNMonitor) onVPNConnected(name string) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connect"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *VPNMonitor) onVPNDisconnected(name string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnect"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *VPNMonitor) onVPNReconnecting(name string) {
    if !m.config.SoundOnReconnect {
        return
    }

    sound := m.config.Sounds["reconnecting"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *VPNMonitor) onVPNAuthFailed(name string) {
    if !m.config.SoundOnAuthFail {
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
| pgrep | System Tool | Free | Process checking |
| wg | System Tool | Free | WireGuard management |
| /sys/class/net | File | Free | Network interfaces |

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
| Linux | Supported | Uses wg, pgrep |
| Windows | Not Supported | ccbell only supports macOS/Linux |
