# Feature: Sound Event Network

Play sounds based on network conditions.

## Summary

Play sounds when network status changes - connected, disconnected, or quality changes.

## Motivation

- Network awareness
- Connection notifications
- Offline/online alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Events

| Event | Trigger | Example |
|-------|---------|---------|
| Connected | Network comes online | WiFi connected |
| Disconnected | Network goes offline | No connection |
| Speed Change | Bandwidth changes | Slow/fast connection |
| VPN Change | VPN toggled | Connected/disconnected |
| IP Change | New IP address | DHCP renewal |

### Configuration

```go
type NetworkConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 30 default
    MonitorTypes  []string          `json:"monitor_types"` // "connectivity", "speed", "vpn", "ip"
    Sounds        map[string]string `json:"sounds"`
    Interfaces    []string          `json:"interfaces,omitempty"` // Specific interfaces
}
```

### Commands

```bash
/ccbell:network status              # Show current network status
/ccbell:network monitor             # Start monitoring
/ccbell:network sound connected <sound>
/ccbell:network sound disconnected <sound>
/ccbell:network sound speed <sound>
/ccbell:network interface eth0      # Monitor specific interface
/ccbell:network enable              # Enable network monitoring
/ccbell:network disable             # Disable network monitoring
/ccbell:network test                # Test all network sounds
```

### Output

```
$ ccbell:network status

=== Sound Event Network ===

Status: Enabled
Check Interval: 30s
Monitor: connectivity, speed

Current State:
  Connected: Yes
  Interface: en0 (WiFi)
  IP: 192.168.1.100
  Speed: 100 Mbps (Good)
  VPN: Disconnected

Sounds:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Speed: bundled:stop
  VPN: bundled:stop

[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Network monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Network Monitoring

```go
type NetworkManager struct {
    config   *NetworkConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastState *NetworkState
}

type NetworkState struct {
    Connected   bool
    Interface   string
    IP          string
    SpeedMbps   float64
    VPN         bool
}

func (m *NetworkManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})

    go m.monitor()
}

func (m *NetworkManager) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkNetwork()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkManager) checkNetwork() {
    state, err := m.getNetworkState()
    if err != nil {
        log.Debug("Failed to get network state: %v", err)
        return
    }

    if m.lastState == nil {
        m.lastState = state
        return
    }

    // Check for events
    if !m.lastState.Connected && state.Connected {
        m.playNetworkEvent("connected", state)
    } else if m.lastState.Connected && !state.Connected {
        m.playNetworkEvent("disconnected", state)
    }

    if m.lastState.IP != state.IP {
        m.playNetworkEvent("ip_change", state)
    }

    if m.lastState.VPN != state.VPN {
        if state.VPN {
            m.playNetworkEvent("vpn_connected", state)
        } else {
            m.playNetworkEvent("vpn_disconnected", state)
        }
    }

    m.lastState = state
}

// getNetworkState reads network info from system
func (m *NetworkManager) getNetworkState() (*NetworkState, error) {
    state := &NetworkState{}

    // Check connectivity
    cmd := exec.Command("ping", "-c", "1", "-W", "1", "8.8.8.8")
    state.Connected = cmd.Run() == nil

    // Get default interface (macOS: route get default)
    cmd = exec.Command("route", "get", "default")
    output, err := cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "interface:") {
                state.Interface = strings.TrimSpace(strings.SplitAfterN(line, ":", 2)[1])
                break
            }
        }
    }

    // Get IP address
    cmd = exec.Command("ipconfig", "getifaddr", state.Interface)
    output, err = cmd.Output()
    if err == nil {
        state.IP = strings.TrimSpace(string(output))
    }

    return state, nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ping | System Tool | Free | Connectivity check |
| route | System Tool | Free | macOS routing table |
| ip | System Tool | Free | Linux networking |

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
| macOS | ✅ Supported | Uses route, ipconfig, ping |
| Linux | ✅ Supported | Uses ip, ping |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
