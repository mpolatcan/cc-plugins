# Feature: Sound Event IP Address Monitor

Play sounds for IP address changes and network configuration updates.

## Summary

Monitor IP address changes, network configuration updates, and interface events, playing sounds for IP events.

## Motivation

- IP change detection
- Network configuration awareness
- Lease renewal feedback
- Interface state changes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### IP Address Events

| Event | Description | Example |
|-------|-------------|---------|
| IP Changed | New IP assigned | 192.168.1.100 |
| Lease Renewed | DHCP renewed | IP unchanged |
| Interface Up | Interface enabled | en0 up |
| Interface Down | Interface disabled | en0 down |
| New Route | Route added | Gateway change |

### Configuration

```go
type IPAddressMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchInterfaces    []string          `json:"watch_interfaces"` // "en0", "eth0"
    SoundOnIPChange    bool              `json:"sound_on_ip_change"]
    SoundOnInterfaceUp bool              `json:"sound_on_interface_up"]
    SoundOnInterfaceDown bool            `json:"sound_on_interface_down"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}

type IPAddressEvent struct {
    Interface   string
    OldIP       string
    NewIP       string
    SubnetMask  string
    Gateway     string
    EventType   string // "ip_change", "interface_up", "interface_down"
}
```

### Commands

```bash
/ccbell:ip status                   # Show IP status
/ccbell:ip add en0                  # Add interface to watch
/ccbell:ip remove en0
/ccbell:ip sound change <sound>
/ccbell:ip sound up <sound>
/ccbell:ip test                     # Test IP sounds
```

### Output

```
$ ccbell:ip status

=== Sound Event IP Address Monitor ===

Status: Enabled
IP Change Sounds: Yes
Interface Up Sounds: Yes

Watched Interfaces: 2

[1] en0 (Wi-Fi)
    Status: UP
    Current IP: 192.168.1.100
    Previous IP: 192.168.1.99
    Subnet: 255.255.255.0
    Gateway: 192.168.1.1
    DHCP: Yes
    Last Change: 2 hours ago
    Sound: bundled:stop

[2] en1 (Thunderbolt)
    Status: DOWN
    Last State Change: 1 day ago
    Sound: bundled:stop

Recent Events:
  [1] en0: IP Changed (2 hours ago)
       192.168.1.99 -> 192.168.1.100
  [2] en0: Interface UP (3 hours ago)
  [3] en1: Interface DOWN (1 day ago)

Sound Settings:
  IP Change: bundled:stop
  Interface Up: bundled:stop
  Interface Down: bundled:stop

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

IP address monitoring doesn't play sounds directly:
- Monitoring feature using network tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### IP Address Monitor

```go
type IPAddressMonitor struct {
    config           *IPAddressMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    interfaceState   map[string]*InterfaceInfo
    lastIP           map[string]string
}

type InterfaceInfo struct {
    InterfaceName string
    Status        string // "up", "down"
    IPAddress     string
    SubnetMask    string
    Gateway       string
}
```

```go
func (m *IPAddressMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.interfaceState = make(map[string]*InterfaceInfo)
    m.lastIP = make(map[string]string)
    go m.monitor()
}

func (m *IPAddressMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkIPAddresses()
        case <-m.stopCh:
            return
        }
    }
}

func (m *IPAddressMonitor) checkIPAddresses() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinIP()
    } else {
        m.checkLinuxIP()
    }
}

func (m *IPAddressMonitor) checkDarwinIP() {
    // Use ipconfig or ifconfig
    cmd := exec.Command("ipconfig", "getpacket", "en0")
    output, err := cmd.Output()

    if err == nil {
        info := m.parseIPConfig(string(output), "en0")
        m.evaluateInterface("en0", info)
    }

    // Check all interfaces
    cmd = exec.Command("ifconfig")
    output, err = cmd.Output()
    if err == nil {
        m.parseIfconfigOutput(string(output))
    }
}

func (m *IPAddressMonitor) checkLinuxIP() {
    // Use ip addr or ifconfig
    cmd := exec.Command("ip", "addr", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIPAddrOutput(string(output))
}

func (m *IPAddressMonitor) parseIPConfig(output string, interfaceName string) *InterfaceInfo {
    info := &InterfaceInfo{
        InterfaceName: interfaceName,
    }

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "ip_address") {
            parts := strings.SplitN(line, "=", 2)
            if len(parts) >= 2 {
                info.IPAddress = strings.TrimSpace(parts[1])
            }
        } else if strings.HasPrefix(line, "subnet_mask") {
            parts := strings.SplitN(line, "=", 2)
            if len(parts) >= 2 {
                info.SubnetMask = strings.TrimSpace(parts[1])
            }
        } else if strings.HasPrefix(line, "router") {
            parts := strings.SplitN(line, "=", 2)
            if len(parts) >= 2 {
                info.Gateway = strings.TrimSpace(parts[1])
            }
        }
    }

    if info.IPAddress != "" {
        info.Status = "up"
    } else {
        info.Status = "down"
    }

    return info
}

func (m *IPAddressMonitor) parseIfconfigOutput(output string) {
    lines := strings.Split(output, "\n")
    var currentInterface string

    for _, line := range lines {
        if strings.HasPrefix(line, "") && !strings.HasPrefix(line, "\t") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                currentInterface = parts[0]
                // Remove trailing colon
                currentInterface = strings.TrimSuffix(currentInterface, ":")

                // Check if we should watch this interface
                if !m.shouldWatchInterface(currentInterface) {
                    continue
                }

                status := &InterfaceInfo{
                    InterfaceName: currentInterface,
                }

                if strings.Contains(line, "UP") {
                    status.Status = "up"
                } else {
                    status.Status = "down"
                }

                m.evaluateInterface(currentInterface, status)
            }
        }
    }
}

func (m *IPAddressMonitor) parseIPAddrOutput(output string) {
    lines := strings.Split(output, "\n")
    var currentInterface string

    for _, line := range lines {
        if strings.HasPrefix(line, "") && !strings.HasPrefix(line, "\t") && !strings.HasPrefix(line, " ") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                currentInterface = parts[1]
                currentInterface = strings.TrimSuffix(currentInterface, ":")

                if !m.shouldWatchInterface(currentInterface) {
                    continue
                }

                status := &InterfaceInfo{
                    InterfaceName: currentInterface,
                }

                if strings.Contains(line, "UP") {
                    status.Status = "up"
                } else {
                    status.Status = "down"
                }

                m.evaluateInterface(currentInterface, status)
            }
        } else if strings.HasPrefix(line, "\tinet ") && currentInterface != "" {
            // Parse IP address
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                status := m.interfaceState[currentInterface]
                if status != nil {
                    status.IPAddress = parts[1]
                }
            }
        }
    }
}

func (m *IPAddressMonitor) shouldWatchInterface(interfaceName string) bool {
    if len(m.config.WatchInterfaces) == 0 {
        return true
    }

    for _, watch := range m.config.WatchInterfaces {
        if interfaceName == watch {
            return true
        }
    }

    return false
}

func (m *IPAddressMonitor) evaluateInterface(interfaceName string, info *InterfaceInfo) {
    lastState := m.interfaceState[interfaceName]

    if lastState == nil {
        m.interfaceState[interfaceName] = info
        m.lastIP[interfaceName] = info.IPAddress
        return
    }

    // Check for IP change
    if lastState.IPAddress != info.IPAddress && info.IPAddress != "" {
        m.onIPChanged(interfaceName, lastState.IPAddress, info.IPAddress)
    }

    // Check for interface status change
    if lastState.Status == "down" && info.Status == "up" {
        m.onInterfaceUp(interfaceName)
    } else if lastState.Status == "up" && info.Status == "down" {
        m.onInterfaceDown(interfaceName)
    }

    // Update state
    lastState.Status = info.Status
    lastState.IPAddress = info.IPAddress
    lastState.SubnetMask = info.SubnetMask
    lastState.Gateway = info.Gateway
}

func (m *IPAddressMonitor) onIPChanged(interfaceName string, oldIP string, newIP string) {
    if !m.config.SoundOnIPChange {
        return
    }

    sound := m.config.Sounds["ip_change"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *IPAddressMonitor) onInterfaceUp(interfaceName string) {
    if !m.config.SoundOnInterfaceUp {
        return
    }

    sound := m.config.Sounds["interface_up"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *IPAddressMonitor) onInterfaceDown(interfaceName string) {
    if !m.config.SoundOnInterfaceDown {
        return
    }

    sound := m.config.Sounds["interface_down"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ipconfig | System Tool | Free | macOS DHCP info |
| ifconfig | System Tool | Free | Interface config |
| ip | System Tool | Free | Linux IP management |

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
| macOS | Supported | Uses ipconfig, ifconfig |
| Linux | Supported | Uses ip command |
| Windows | Not Supported | ccbell only supports macOS/Linux |
