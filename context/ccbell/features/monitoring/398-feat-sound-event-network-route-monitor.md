# Feature: Sound Event Network Route Monitor

Play sounds for routing table changes, gateway switches, and route failures.

## Summary

Monitor network routing table for route changes, gateway switches, and connectivity issues, playing sounds for routing events.

## Motivation

- Route change awareness
- Gateway failover detection
- Network topology changes
- Routing table integrity
- Connectivity troubleshooting

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Network Route Events

| Event | Description | Example |
|-------|-------------|---------|
| Route Added | New route inserted | new subnet |
| Route Deleted | Route removed | old route |
| Gateway Changed | Default gateway switched | eth0 -> eth1 |
| Route Metric | Metric changed | lower cost |
| Interface Down | Interface route lost | eth0 down |
| ICMP Redirect | Redirect received | shorter path |

### Configuration

```go
type NetworkRouteMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchRoutes       []string          `json:"watch_routes"` // "default", "192.168.1.0/24", "*"
    WatchGateways     []string          `json:"watch_gateways"` // "192.168.1.1", "*"
    SoundOnChange     bool              `json:"sound_on_change"`
    SoundOnGateway    bool              `json:"sound_on_gateway"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:route status                   # Show route status
/ccbell:route add default              # Add route to watch
/ccbell:route remove default
/ccbell:route sound change <sound>
/ccbell:route sound gateway <sound>
/ccbell:route test                     # Test route sounds
```

### Output

```
$ ccbell:route status

=== Sound Event Network Route Monitor ===

Status: Enabled
Change Sounds: Yes
Gateway Sounds: Yes

Watched Routes: 2
Watched Gateways: 1

Current Routing Table:

[1] default via 192.168.1.1 dev eth0
    Metric: 100
    Gateway: 192.168.1.1
    Interface: eth0
    Status: Active
    Sound: bundled:route-default

[2] 192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100
    Metric: 100
    Interface: eth0
    Status: Active
    Sound: bundled:route-local

[3] 10.0.0.0/8 via 192.168.1.254 dev eth0
    Metric: 200
    Gateway: 192.168.1.254
    Interface: eth0
    Status: Active
    Sound: bundled:route-vpn

Route Statistics:
  Total Routes: 8
  Active: 8
  Changes Today: 3

Recent Events:
  [1] default: Gateway Changed (5 min ago)
       192.168.1.1 -> 192.168.1.254
  [2] 10.0.0.0/8: Route Added (1 hour ago)
       New VPN route
  [3] 192.168.2.0/24: Route Deleted (2 hours ago)
       Route expired

Gateway Status:
  192.168.1.1: Reachable
  192.168.1.254: Reachable

Sound Settings:
  Change: bundled:route-change
  Gateway: bundled:route-gateway
  Fail: bundled:route-fail

[Configure] [Test All]
```

---

## Audio Player Compatibility

Route monitoring doesn't play sounds directly:
- Monitoring feature using ip route/netstat
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Route Monitor

```go
type NetworkRouteMonitor struct {
    config          *NetworkRouteMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    routeState      map[string]*RouteInfo
    lastEventTime   map[string]time.Time
}

type RouteInfo struct {
    Destination string
    Gateway     string
    Interface   string
    Metric      int
    Flags       string
}

func (m *NetworkRouteMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.routeState = make(map[string]*RouteInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkRouteMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotRouteState()

    for {
        select {
        case <-ticker.C:
            m.checkRouteState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkRouteMonitor) snapshotRouteState() {
    m.checkRouteState()
}

func (m *NetworkRouteMonitor) checkRouteState() {
    routes := m.listRoutes()
    currentRoutes := make(map[string]*RouteInfo)

    for _, route := range routes {
        key := m.routeKey(route)
        currentRoutes[key] = route
    }

    // Check for new routes
    for key, route := range currentRoutes {
        if _, exists := m.routeState[key]; !exists {
            m.routeState[key] = route
            if m.shouldWatchRoute(route.Destination) {
                m.onRouteAdded(route)
            }
        }
    }

    // Check for removed routes
    for key, lastRoute := range m.routeState {
        if _, exists := currentRoutes[key]; !exists {
            delete(m.routeState, key)
            if m.shouldWatchRoute(lastRoute.Destination) {
                m.onRouteDeleted(lastRoute)
            }
        }

        // Check for gateway changes
        currentRoute := currentRoutes[key]
        if currentRoute != nil && lastRoute.Gateway != currentRoute.Gateway {
            if m.config.SoundOnGateway {
                m.onGatewayChanged(lastRoute, currentRoute)
            }
        }

        // Check for metric changes
        if currentRoute != nil && lastRoute.Metric != currentRoute.Metric {
            m.onMetricChanged(lastRoute, currentRoute)
        }
    }
}

func (m *NetworkRouteMonitor) listRoutes() []*RouteInfo {
    var routes []*RouteInfo

    cmd := exec.Command("ip", "route", "show")
    output, err := cmd.Output()
    if err != nil {
        return routes
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        route := m.parseRouteLine(line)
        if route != nil {
            routes = append(routes, route)
        }
    }

    return routes
}

func (m *NetworkRouteMonitor) parseRouteLine(line string) *RouteInfo {
    // Parse: "default via 192.168.1.1 dev eth0 metric 100"
    // Or: "192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100"

    route := &RouteInfo{}

    parts := strings.Fields(line)

    // Get destination
    route.Destination = parts[0]

    // Parse rest of the line
    i := 1
    for i < len(parts) {
        switch parts[i] {
        case "via":
            if i+1 < len(parts) {
                route.Gateway = parts[i+1]
                i++
            }
        case "dev":
            if i+1 < len(parts) {
                route.Interface = parts[i+1]
                i++
            }
        case "metric":
            if i+1 < len(parts) {
                metric, _ := strconv.Atoi(parts[i+1])
                route.Metric = metric
                i++
            }
        case "proto", "scope", "src", "advmss":
            i++
        }
        i++
    }

    return route
}

func (m *NetworkRouteMonitor) routeKey(route *RouteInfo) string {
    return fmt.Sprintf("%s-%s", route.Destination, route.Interface)
}

func (m *NetworkRouteMonitor) shouldWatchRoute(destination string) bool {
    if len(m.config.WatchRoutes) == 0 {
        return true
    }

    for _, r := range m.config.WatchRoutes {
        if r == "*" || r == destination {
            return true
        }
    }

    return false
}

func (m *NetworkRouteMonitor) onRouteAdded(route *RouteInfo) {
    if !m.config.SoundOnChange {
        return
    }

    key := fmt.Sprintf("add:%s", route.Destination)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["change"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *NetworkRouteMonitor) onRouteDeleted(route *RouteInfo) {
    if !m.config.SoundOnChange {
        return
    }

    key := fmt.Sprintf("delete:%s", route.Destination)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["change"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *NetworkRouteMonitor) onGatewayChanged(lastRoute, currentRoute *RouteInfo) {
    if !m.config.SoundOnGateway {
        return
    }

    if !m.shouldWatchGateway(currentRoute.Gateway) {
        return
    }

    key := fmt.Sprintf("gateway:%s", currentRoute.Destination)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["gateway"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkRouteMonitor) onMetricChanged(lastRoute, currentRoute *RouteInfo) {
    // Optional: sound for metric changes
}

func (m *NetworkRouteMonitor) shouldWatchGateway(gateway string) bool {
    if len(m.config.WatchGateways) == 0 {
        return true
    }

    for _, g := range m.config.WatchGateways {
        if g == "*" || g == gateway {
            return true
        }
    }

    return false
}

func (m *NetworkRouteMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ip | System Tool | Free | Network configuration |
| netstat | System Tool | Free | Network statistics |

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
| macOS | Supported | Uses netstat, route |
| Linux | Supported | Uses ip route |
