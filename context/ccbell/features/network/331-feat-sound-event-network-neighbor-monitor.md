# Feature: Sound Event Network Neighbor Monitor

Play sounds for ARP/NDP table changes and neighbor discovery events.

## Summary

Monitor ARP and NDP cache changes, new neighbors, and reachability changes, playing sounds for neighbor events.

## Motivation

- Network awareness
- ARP spoofing detection
- New device detection
- Connectivity changes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Neighbor Events

| Event | Description | Example |
|-------|-------------|---------|
| Neighbor Added | New ARP entry | 192.168.1.100 -> aa:bb:cc:dd |
| Neighbor Removed | ARP entry expired | Entry timed out |
| Neighbor Reachable | State changed | STALE -> REACHABLE |
| Duplicate IP | IP conflict detected | Duplicate detected |

### Configuration

```go
type NetworkNeighborMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchSubnets      []string          `json:"watch_subnets"] // "192.168.1.0/24"
    SoundOnAdd        bool              `json:"sound_on_add"]
    SoundOnRemove     bool              `json:"sound_on_remove"]
    SoundOnDuplicate  bool              `json:"sound_on_duplicate"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type NeighborEvent struct {
    IP       string
    MAC      string
    Interface string
    State    string // "REACHABLE", "STALE", "DELAY", "PROBE"
    EventType string // "add", "remove", "change", "duplicate"
}
```

### Commands

```bash
/ccbell:neighbor status               # Show neighbor status
/ccbell:neighbor add 192.168.1.0/24   # Add subnet to watch
/ccbell:neighbor remove 192.168.1.0/24
/ccbell:neighbor sound add <sound>
/ccbell:neighbor sound duplicate <sound>
/ccbell:neighbor test                 # Test neighbor sounds
```

### Output

```
$ ccbell:neighbor status

=== Sound Event Network Neighbor Monitor ===

Status: Enabled
Add Sounds: Yes
Duplicate Sounds: Yes

Watched Subnets: 1

[1] 192.168.1.0/24
    Total Neighbors: 15
    Reachable: 10
    Stale: 5
    Sound: bundled:stop

Recent Events:
  [1] 192.168.1.105: Neighbor Added (5 min ago)
       aa:bb:cc:dd:ee:ff (en0)
  [2] 192.168.1.50: Duplicate IP (10 min ago)
       Conflict detected
  [3] 192.168.1.102: Neighbor Removed (1 hour ago)
       Entry timed out

Neighbor Statistics:
  New today: 3
  Removed: 2
  Duplicates: 1

Sound Settings:
  Add: bundled:neighbor-add
  Remove: bundled:stop
  Duplicate: bundled:neighbor-duplicate

[Configure] [Add Subnet] [Test All]
```

---

## Audio Player Compatibility

Neighbor monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Neighbor Monitor

```go
type NetworkNeighborMonitor struct {
    config           *NetworkNeighborMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    neighborState    map[string]*NeighborInfo
    lastEventTime    map[string]time.Time
}

type NeighborInfo struct {
    IP       string
    MAC      string
    Interface string
    State    string
    LastSeen time.Time
}

func (m *NetworkNeighborMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.neighborState = make(map[string]*NeighborInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkNeighborMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotNeighborState()

    for {
        select {
        case <-ticker.C:
            m.checkNeighborState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkNeighborMonitor) snapshotNeighborState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinNeighbors()
    } else {
        m.snapshotLinuxNeighbors()
    }
}

func (m *NetworkNeighborMonitor) snapshotDarwinNeighbors() {
    cmd := exec.Command("arp", "-a")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseARPOutput(string(output))
}

func (m *NetworkNeighborMonitor) snapshotLinuxNeighbors() {
    cmd := exec.Command("ip", "neigh", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIPNeighOutput(string(output))
}

func (m *NetworkNeighborMonitor) checkNeighborState() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinNeighbors()
    } else {
        m.checkLinuxNeighbors()
    }
}

func (m *NetworkNeighborMonitor) checkDarwinNeighbors() {
    cmd := exec.Command("arp", "-a")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseARPOutput(string(output))
}

func (m *NetworkNeighborMonitor) checkLinuxNeighbors() {
    cmd := exec.Command("ip", "neigh", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIPNeighOutput(string(output))
}

func (m *NetworkNeighborMonitor) parseARPOutput(output string) {
    lines := strings.Split(output, "\n")
    currentNeighbors := make(map[string]*NeighborInfo)

    for _, line := range lines {
        // Format: hostname (IP) at macaddr on interface [ethernet]
        re := regexp.MustCompile(`\(([^)]+)\) at ([^ ]+)`)
        match := re.FindStringSubmatch(line)
        if match != nil {
            ip := match[1]
            mac := match[2]

            if !m.shouldWatchIP(ip) {
                continue
            }

            // Extract interface
            interfaceRe := regexp.MustCompile(`on ([^ ]+)`)
            ifaceMatch := interfaceRe.FindStringSubmatch(line)
            iface := "unknown"
            if ifaceMatch != nil {
                iface = ifaceMatch[1]
            }

            info := &NeighborInfo{
                IP:       ip,
                MAC:      mac,
                Interface: iface,
                State:    "REACHABLE",
                LastSeen: time.Now(),
            }

            key := ip
            currentNeighbors[key] = info

            lastInfo := m.neighborState[key]
            if lastInfo == nil {
                m.onNeighborAdded(info)
            }
        }
    }

    // Check for removed neighbors
    m.checkRemovedNeighbors(currentNeighbors)

    m.neighborState = currentNeighbors
}

func (m *NetworkNeighborMonitor) parseIPNeighOutput(output string) {
    lines := strings.Split(output, "\n")
    currentNeighbors := make(map[string]*NeighborInfo)

    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        ip := parts[0]
        interfaceName := parts[2]
        mac := parts[4]
        state := parts[5]

        if !m.shouldWatchIP(ip) {
            continue
        }

        info := &NeighborInfo{
            IP:       ip,
            MAC:      mac,
            Interface: interfaceName,
            State:    state,
            LastSeen: time.Now(),
        }

        key := ip
        currentNeighbors[key] = info

        lastInfo := m.neighborState[key]
        if lastInfo == nil {
            m.onNeighborAdded(info)
        } else if lastInfo.MAC != mac {
            // MAC changed - could be duplicate or spoofing
            m.onNeighborChanged(info, lastInfo)
        }
    }

    // Check for removed neighbors
    m.checkRemovedNeighbors(currentNeighbors)

    m.neighborState = currentNeighbors
}

func (m *NetworkNeighborMonitor) checkRemovedNeighbors(current map[string]*NeighborInfo) {
    for ip, lastInfo := range m.neighborState {
        if _, exists := current[ip]; !exists {
            m.onNeighborRemoved(lastInfo)
        }
    }
}

func (m *NetworkNeighborMonitor) shouldWatchIP(ip string) bool {
    if len(m.config.WatchSubnets) == 0 {
        return true
    }

    for _, subnet := range m.config.WatchSubnets {
        // Simple check - would need proper subnet parsing
        if strings.HasPrefix(ip, strings.Split(subnet, "/")[0]) {
            return true
        }
    }

    return false
}

func (m *NetworkNeighborMonitor) onNeighborAdded(info *NeighborInfo) {
    if !m.config.SoundOnAdd {
        return
    }

    key := fmt.Sprintf("add:%s", info.IP)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["add"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *NetworkNeighborMonitor) onNeighborRemoved(info *NeighborInfo) {
    if !m.config.SoundOnRemove {
        return
    }

    key := fmt.Sprintf("remove:%s", info.IP)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["remove"]
        if sound != "" {
            m.player.Play(sound, 0.2)
        }
    }
}

func (m *NetworkNeighborMonitor) onNeighborChanged(current *NeighborInfo, last *NeighborInfo) {
    // MAC changed - could indicate duplicate IP
    if !m.config.SoundOnDuplicate {
        return
    }

    key := fmt.Sprintf("change:%s", current.IP)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["duplicate"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkNeighborMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| arp | System Tool | Free | ARP table |
| ip neigh | System Tool | Free | Neighbor table |

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
| macOS | Supported | Uses arp |
| Linux | Supported | Uses ip neigh |
| Windows | Not Supported | ccbell only supports macOS/Linux |
