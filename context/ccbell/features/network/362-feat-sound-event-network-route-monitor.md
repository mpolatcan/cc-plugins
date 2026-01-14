# Feature: Sound Event Network Route Monitor

Play sounds for network route changes and routing table modifications.

## Summary

Monitor network routing table changes, gateway switches, and route failures, playing sounds for routing events.

## Motivation

- Network path awareness
- Route change detection
- Gateway failover alerts
- Routing table monitoring
- Network path debugging

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Route Events

| Event | Description | Example |
|-------|-------------|---------|
| Route Added | New route added | Route to 10.0.0.0/24 |
| Route Deleted | Route removed | Route expired |
| Gateway Changed | Default gateway changed | eth0 -> wlan0 |
| Route Failed | Route unreachable | No route to host |
| Metric Changed | Route metric updated | Metric 100 -> 200 |

### Configuration

```go
type NetworkRouteMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDestinations []string          `json:"watch_destinations"` // "0.0.0.0/0", "10.0.0.0/8"
    WatchInterfaces   []string          `json:"watch_interfaces"` // "eth0", "wlan0", "*"
    SoundOnAdd        bool              `json:"sound_on_add"`
    SoundOnDelete     bool              `json:"sound_on_delete"`
    SoundOnGateway    bool              `json:"sound_on_gateway"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type NetworkRouteEvent struct {
    Destination  string
    Gateway      string
    Interface    string
    Metric       int
    RouteType    string // "add", "delete", "change"
    EventType    string // "add", "delete", "gateway", "metric", "fail"
}
```

### Commands

```bash
/ccbell:route status                  # Show route status
/ccbell:route add 10.0.0.0/8          # Add destination to watch
/ccbell:route remove 10.0.0.0/8
/ccbell:route sound add <sound>
/ccbell:route sound gateway <sound>
/ccbell:route test                    # Test route sounds
```

### Output

```
$ ccbell:route status

=== Sound Event Network Route Monitor ===

Status: Enabled
Add Sounds: Yes
Delete Sounds: Yes
Gateway Sounds: Yes

Watched Destinations: 2
Watched Interfaces: 2

Routing Table:
  [1] default -> 192.168.1.1 (eth0) metric 100
  [2] 10.0.0.0/8 -> 10.0.0.1 (eth0) metric 10
  [3] 172.16.0.0/12 -> 172.16.0.1 (eth1) metric 20

Recent Events:
  [1] Route Changed (5 min ago)
       10.0.0.0/8: metric 10 -> 20
  [2] Gateway Changed (10 min ago)
       Default: eth0 -> wlan0
  [3] Route Added (1 hour ago)
       172.16.0.0/12 via 172.16.0.1

Route Statistics:
  Routes: 5
  Changes Today: 12
  Gateway Changes: 2

Sound Settings:
  Add: bundled:route-add
  Delete: bundled:route-delete
  Gateway: bundled:route-gateway

[Configure] [Add Destination] [Test All]
```

---

## Audio Player Compatibility

Route monitoring doesn't play sounds directly:
- Monitoring feature using ip route
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
    RouteType   string // "unicast", "broadcast", "local"
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
    if runtime.GOOS == "linux" {
        m.readLinuxRoutes()
    } else {
        m.readDarwinRoutes()
    }
}

func (m *NetworkRouteMonitor) readLinuxRoutes() {
    cmd := exec.Command("ip", "route", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentRoutes := m.parseIPRouteOutput(string(output))

    // Check for new routes
    for key, route := range currentRoutes {
        if _, exists := m.routeState[key]; !exists {
            m.routeState[key] = route
            if m.shouldWatchRoute(route) {
                m.onRouteAdded(route)
            }
        }
    }

    // Check for deleted routes
    for key, lastRoute := range m.routeState {
        if _, exists := currentRoutes[key]; !exists {
            delete(m.routeState, key)
            if m.shouldWatchRoute(lastRoute) {
                m.onRouteDeleted(lastRoute)
            }
        }
    }

    // Check for metric changes
    for key, route := range currentRoutes {
        if lastRoute, exists := m.routeState[key]; exists {
            if route.Metric != lastRoute.Metric && m.shouldWatchRoute(route) {
                m.onMetricChanged(route, lastRoute)
            }
        }
    }
}

func (m *NetworkRouteMonitor) parseIPRouteOutput(output string) map[string]*RouteInfo {
    routes := make(map[string]*RouteInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse: default via 192.168.1.1 dev eth0 metric 100
        // Or: 10.0.0.0/8 via 10.0.0.1 dev eth0
        parts := strings.Fields(line)

        if len(parts) < 3 {
            continue
        }

        dest := parts[0]
        if dest == "default" {
            dest = "0.0.0.0/0"
        }

        route := &RouteInfo{
            Destination: dest,
        }

        for i := 1; i < len(parts); i++ {
            switch parts[i] {
            case "via":
                if i+1 < len(parts) {
                    route.Gateway = parts[i+1]
                }
            case "dev":
                if i+1 < len(parts) {
                    route.Interface = parts[i+1]
                }
            case "metric":
                if i+1 < len(parts) {
                    metric, _ := strconv.Atoi(parts[i+1])
                    route.Metric = metric
                }
            }
        }

        key := fmt.Sprintf("%s:%s", route.Destination, route.Interface)
        routes[key] = route
    }

    return routes
}

func (m *NetworkRouteMonitor) readDarwinRoutes() {
    cmd := exec.Command("netstat", "-nr", "-f", "inet")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse netstat output
    m.parseNetstatRoutes(string(output))
}

func (m *NetworkRouteMonitor) parseNetstatRoutes(output string) {
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Internet:") || strings.HasPrefix(line, "Internet6") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        // Parse destination, gateway, flags, interface
    }
}

func (m *NetworkRouteMonitor) shouldWatchRoute(route *RouteInfo) bool {
    // Check if destination matches
    for _, dest := range m.config.WatchDestinations {
        if dest == route.Destination {
            return true
        }
    }

    // Check if interface matches
    for _, iface := range m.config.WatchInterfaces {
        if iface == "*" || iface == route.Interface {
            return true
        }
    }

    // Default: watch all if no filters
    return len(m.config.WatchDestinations) == 0 && len(m.config.WatchInterfaces) == 0
}

func (m *NetworkRouteMonitor) onRouteAdded(route *RouteInfo) {
    if !m.config.SoundOnAdd {
        return
    }

    key := fmt.Sprintf("add:%s:%s", route.Destination, route.Interface)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["add"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkRouteMonitor) onRouteDeleted(route *RouteInfo) {
    if !m.config.SoundOnDelete {
        return
    }

    key := fmt.Sprintf("delete:%s:%s", route.Destination, route.Interface)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["delete"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *NetworkRouteMonitor) onMetricChanged(newRoute *RouteInfo, lastRoute *RouteInfo) {
    // Check for default gateway change
    if newRoute.Destination == "0.0.0.0/0" && newRoute.Interface != lastRoute.Interface {
        m.onGatewayChanged(newRoute, lastRoute)
    }
}

func (m *NetworkRouteMonitor) onGatewayChanged(newRoute *RouteInfo, lastRoute *RouteInfo) {
    if !m.config.SoundOnGateway {
        return
    }

    key := fmt.Sprintf("gateway:%s->%s", lastRoute.Interface, newRoute.Interface)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["gateway"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
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
| ip route | System Tool | Free | Linux routing table |
| netstat | System Tool | Free | macOS routing table |

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
