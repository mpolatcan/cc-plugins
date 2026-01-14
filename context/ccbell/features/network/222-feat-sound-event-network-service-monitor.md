# Feature: Sound Event Network Service Monitor

Play sounds for network service state changes.

## Summary

Monitor network services and connectivity states, playing sounds for VPN connections, network interface changes, and service availability.

## Motivation

- VPN connection feedback
- Network state awareness
- Service availability alerts
- Connection security awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Network Service Events

| Event | Description | Example |
|-------|-------------|---------|
| VPN Connected | VPN tunnel established | OpenVPN connected |
| VPN Disconnected | VPN tunnel closed | Disconnected |
| WiFi Connected | WiFi network joined | Home network |
| WiFi Disconnected | WiFi network left | Roaming |
| Ethernet Connected | Cable plugged in | LAN connected |
| Ethernet Disconnected | Cable unplugged | LAN disconnected |
| Service Up | Network service available | DNS resolved |

### Configuration

```go
type NetworkServiceMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    VPNMonitor       bool              `json:"vpn_monitor"`
    WiFiMonitor      bool              `json:"wifi_monitor"`
    WatchVPNs        []string          `json:"watch_vpns"` // VPN names
    WatchServices    []string          `json:"watch_services"` // Service names
    Sounds           map[string]string `json:"sounds"`
}

type NetworkServiceEvent struct {
    Service   string
    Type      string // "vpn", "wifi", "ethernet", "service"
    State     string // "connected", "disconnected", "up", "down"
    SSID      string
    Gateway   string
}
```

### Commands

```bash
/ccbell:network-service status     # Show network status
/ccbell:network-service vpn on     # Enable VPN monitoring
/ccbell:network-service wifi on    # Enable WiFi monitoring
/ccbell:network-service add VPN "MyVPN"
/ccbell:network-service sound connected <sound>
/ccbell:network-service sound disconnected <sound>
/ccbell:network-service test       # Test sounds
```

### Output

```
$ ccbell:network-service status

=== Sound Event Network Service Monitor ===

Status: Enabled
VPN Monitoring: Yes
WiFi Monitoring: Yes

Network Services:

[1] VPN (MyVPN)
    Status: Connected
    Duration: 2 hours
    IP: 10.0.0.5
    Sound: bundled:stop

[2] WiFi (HomeNetwork)
    Status: Connected
    Signal: -45 dBm
    IP: 192.168.1.100
    Sound: bundled:stop

[3] Ethernet
    Status: Disconnected
    Cable: Unplugged
    Sound: bundled:stop

Recent Events:
  [1] VPN: Connected (2 hours ago)
  [2] WiFi: Connected (3 hours ago)
  [3] Ethernet: Disconnected (1 day ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Network service monitoring doesn't play sounds directly:
- Monitoring feature using network management APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Service Monitor

```go
type NetworkServiceMonitor struct {
    config      *NetworkServiceMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    lastStates  map[string]string
}

func (m *NetworkServiceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStates = make(map[string]string)
    go m.monitor()
}

func (m *NetworkServiceMonitor) monitor() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkNetworkServices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkServiceMonitor) checkNetworkServices() {
    if m.config.VPNMonitor {
        m.checkVPN()
    }

    if m.config.WiFiMonitor {
        m.checkWiFi()
    }

    m.checkEthernet()
}

func (m *NetworkServiceMonitor) checkVPN() {
    if runtime.GOOS == "darwin" {
        m.checkMacOSVPN()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxVPN()
    }
}

func (m *NetworkServiceMonitor) checkMacOSVPN() {
    // macOS: scutil --nc
    cmd := exec.Command("scutil", "--nc", "list")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "VPN") || strings.Contains(line, "IPSec") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                vpnName := parts[1]
                status := m.getVPNStatusMacOS(vpnName)
                m.onVPNStateChange(vpnName, status)
            }
        }
    }
}

func (m *NetworkServiceMonitor) getVPNStatusMacOS(vpnName string) string {
    cmd := exec.Command("scutil", "--nc", "show", vpnName)
    output, err := cmd.Output()
    if err != nil {
        return "unknown"
    }

    if strings.Contains(string(output), "Connected") {
        return "connected"
    }

    return "disconnected"
}

func (m *NetworkServiceMonitor) checkLinuxVPN() {
    // Check VPN tunnel interfaces
    cmd := exec.Command("ip", "tunnel", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Check for common VPN types
    vpnTypes := []string{"tun", "tap", "wg"}
    for _, vpnType := range vpnTypes {
        if strings.Contains(string(output), vpnType+"0") {
            m.onVPNStateChange(vpnType, "connected")
        }
    }

    // Check for active VPN processes
    vpns := []string{"openvpn", "wireguard", "strongswan"}
    for _, vpn := range vpns {
        cmd = exec.Command("pgrep", "-x", vpn)
        if cmd.Run() == nil {
            m.onVPNStateChange(vpn, "connected")
        }
    }
}

func (m *NetworkServiceMonitor) onVPNStateChange(vpnName string, state string) {
    key := "vpn:" + vpnName
    lastState := m.lastStates[key]

    if lastState != "" && lastState != state {
        if state == "connected" {
            m.playSound("vpn_connected")
        } else if state == "disconnected" {
            m.playSound("vpn_disconnected")
        }
    }

    m.lastStates[key] = state
}

func (m *NetworkServiceMonitor) checkWiFi() {
    if runtime.GOOS == "darwin" {
        m.checkMacOSWiFi()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxWiFi()
    }
}

func (m *NetworkServiceMonitor) checkMacOSWiFi() {
    cmd := exec.Command("networksetup", "-getairportpower", "en0")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    status := "off"
    if strings.Contains(string(output), "On") {
        status = "on"

        // Get SSID
        ssidCmd := exec.Command("networksetup", "-getairportnetwork", "en0")
        ssidOutput, _ := ssidCmd.Output()
        ssid := strings.TrimSpace(strings.TrimPrefix(string(ssidOutput), "Current Network: "))

        m.onWiFiStateChange(ssid, "connected")
    } else {
        m.onWiFiStateChange("", "disconnected")
    }
}

func (m *NetworkServiceMonitor) checkLinuxWiFi() {
    // Check WiFi interface
    cmd := exec.Command("iwgetid", "-r")
    output, err := cmd.Output()
    if err != nil {
        m.onWiFiStateChange("", "disconnected")
        return
    }

    ssid := strings.TrimSpace(string(output))
    if ssid != "" {
        m.onWiFiStateChange(ssid, "connected")
    } else {
        m.onWiFiStateChange("", "disconnected")
    }
}

func (m *NetworkServiceMonitor) onWiFiStateChange(ssid string, state string) {
    key := "wifi"
    lastState := m.lastStates[key]

    if lastState != "" && lastState != state {
        if state == "connected" {
            m.playSound("wifi_connected")
        } else if state == "disconnected" {
            m.playSound("wifi_disconnected")
        }
    }

    m.lastStates[key] = state
}

func (m *NetworkServiceMonitor) checkEthernet() {
    // Check for ethernet interface
    ifaces := []string{"en0", "en1", "eth0", "eth1"}

    connected := false
    for _, iface := range ifaces {
        if m.isInterfaceUp(iface) {
            connected = true
            break
        }
    }

    key := "ethernet"
    lastState := m.lastStates[key]

    if lastState == "connected" && !connected {
        m.playSound("ethernet_disconnected")
    } else if lastState != "connected" && connected {
        m.playSound("ethernet_connected")
    }

    if connected {
        m.lastStates[key] = "connected"
    } else {
        m.lastStates[key] = "disconnected"
    }
}

func (m *NetworkServiceMonitor) isInterfaceUp(iface string) bool {
    cmd := exec.Command("ip", "link", "show", iface)
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.Contains(string(output), "state UP")
}

func (m *NetworkServiceMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| scutil | System Tool | Free | macOS network config |
| networksetup | System Tool | Free | macOS network setup |
| ip | iproute2 | Free | Linux network config |
| iwgetid | Wireless Tools | Free | Linux WiFi info |

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
| macOS | Supported | Uses scutil/networksetup |
| Linux | Supported | Uses ip/iwgetid |
| Windows | Not Supported | ccbell only supports macOS/Linux |
