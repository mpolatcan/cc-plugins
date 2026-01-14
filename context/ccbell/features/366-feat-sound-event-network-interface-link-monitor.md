# Feature: Sound Event Network Interface Link Monitor

Play sounds for network interface link state changes and carrier events.

## Summary

Monitor network interface link status, carrier changes, and network interface events, playing sounds for link events.

## Motivation

- Network connectivity awareness
- Link state detection
- Cable disconnect alerts
- Interface up/down feedback
- Network redundancy monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Link Events

| Event | Description | Example |
|-------|-------------|---------|
| Link Up | Interface connected | Cable plugged in |
| Link Down | Interface disconnected | Cable unplugged |
| Carrier Lost | Carrier signal lost | No link pulse |
| Speed Changed | Link speed changed | 1Gbps -> 100Mbps |
| Duplex Changed | Duplex mode changed | Full -> Half |

### Configuration

```go
type NetworkLinkMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchInterfaces   []string          `json:"watch_interfaces"` // "eth0", "en0", "*"
    SoundOnUp         bool              `json:"sound_on_up"`
    SoundOnDown       bool              `json:"sound_on_down"]
    SoundOnSpeed      bool              `json:"sound_on_speed"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type NetworkLinkEvent struct {
    Interface  string
    State      string // "up", "down", "unknown"
    Speed      int // Mbps
    Duplex     string // "full", "half", "unknown"
    Carrier    bool
    EventType  string // "up", "down", "speed", "carrier"
}
```

### Commands

```bash
/ccbell:link status                  # Show link status
/ccbell:link add eth0                # Add interface to watch
/ccbell:link remove eth0
/ccbell:link sound up <sound>
/ccbell:link sound down <sound>
/ccbell:link test                    # Test link sounds
```

### Output

```
$ ccbell:link status

=== Sound Event Network Interface Link Monitor ===

Status: Enabled
Up Sounds: Yes
Down Sounds: Yes
Speed Sounds: Yes

Watched Interfaces: 3

[1] eth0
    State: UP
    Speed: 1000 Mbps
    Duplex: Full
    Carrier: Yes
    Sound: bundled:link-eth0

[2] wlan0
    State: UP
    Speed: 300 Mbps
    Duplex: Full
    Carrier: Yes
    Sound: bundled:link-wifi

[3] eth1 (Bonded)
    State: DOWN
    Speed: 0 Mbps
    Duplex: Unknown
    Carrier: No
    Sound: bundled:link-bond

Recent Events:
  [1] eth1: Link Down (5 min ago)
       Cable disconnected
  [2] eth0: Speed Changed (10 min ago)
       100 Mbps -> 1000 Mbps
  [3] wlan0: Link Up (1 hour ago)
       Connected to AP

Link Statistics:
  Total Interfaces: 3
  Up: 2
  Down: 1
  Changes Today: 5

Sound Settings:
  Up: bundled:link-up
  Down: bundled:link-down
  Speed: bundled:link-speed

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Network link monitoring doesn't play sounds directly:
- Monitoring feature using ip link/sysfs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Link Monitor

```go
type NetworkLinkMonitor struct {
    config          *NetworkLinkMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    linkState       map[string]*LinkInfo
    lastEventTime   map[string]time.Time
}

type LinkInfo struct {
    Interface  string
    State      string
    Speed      int
    Duplex     string
    Carrier    bool
    LastUpdate time.Time
}

func (m *NetworkLinkMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.linkState = make(map[string]*LinkInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkLinkMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotLinkState()

    for {
        select {
        case <-ticker.C:
            m.checkLinkState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkLinkMonitor) snapshotLinkState() {
    if runtime.GOOS == "linux" {
        m.readLinuxLinks()
    } else {
        m.readDarwinLinks()
    }
}

func (m *NetworkLinkMonitor) checkLinkState() {
    if runtime.GOOS == "linux" {
        m.readLinuxLinks()
    } else {
        m.readDarwinLinks()
    }
}

func (m *NetworkLinkMonitor) readLinuxLinks() {
    cmd := exec.Command("ip", "link", "show")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentLinks := m.parseIPLinkOutput(string(output))

    for name, info := range currentLinks {
        lastInfo := m.linkState[name]
        if lastInfo == nil {
            m.linkState[name] = info
            continue
        }

        // Check for state changes
        if lastInfo.State != info.State {
            if info.State == "UP" {
                m.onLinkUp(name, info)
            } else if info.State == "DOWN" {
                m.onLinkDown(name, info)
            }
        }

        // Check for speed changes
        if lastInfo.Speed != info.Speed && info.Speed > 0 {
            m.onSpeedChanged(name, info, lastInfo)
        }

        m.linkState[name] = info
    }
}

func (m *NetworkLinkMonitor) parseIPLinkOutput(output string) map[string]*LinkInfo {
    links := make(map[string]*LinkInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, " ") || line == "" {
            continue
        }

        // Parse: "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ..."
        parts := strings.SplitN(line, ":", 2)
        if len(parts) < 2 {
            continue
        }

        name := strings.TrimSpace(parts[1])
        name = strings.Split(name, ":")[0]

        if !m.shouldWatchInterface(name) {
            continue
        }

        info := &LinkInfo{
            Interface: name,
            LastUpdate: time.Now(),
        }

        // Check state
        if strings.Contains(line, "UP") {
            info.State = "UP"
        } else {
            info.State = "DOWN"
        }

        // Check carrier
        if strings.Contains(line, "LOWER_UP") {
            info.Carrier = true
        }

        // Get speed from ethtool
        info.Speed = m.getLinkSpeed(name)
        info.Duplex = m.getLinkDuplex(name)

        links[name] = info
    }

    return links
}

func (m *NetworkLinkMonitor) readDarwinLinks() {
    cmd := exec.Command("ifconfig", "-a")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIfconfigOutput(string(output))
}

func (m *NetworkLinkMonitor) parseIfconfigOutput(output string) {
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, " ") || line == "" {
            continue
        }

        parts := strings.SplitN(line, ":", 2)
        if len(parts) < 2 {
            continue
        }

        name := parts[0]
        if !m.shouldWatchInterface(name) {
            continue
        }

        // Parse interface info from following lines
    }
}

func (m *NetworkLinkMonitor) getLinkSpeed(name string) int {
    cmd := exec.Command("ethtool", name)
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    re := regexp.MustCompile(`Speed: (\d+)Mb/s`)
    match := re.FindStringSubmatch(string(output))
    if match != nil {
        speed, _ := strconv.Atoi(match[1])
        return speed
    }

    return 0
}

func (m *NetworkLinkMonitor) getLinkDuplex(name string) string {
    cmd := exec.Command("ethtool", name)
    output, err := cmd.Output()
    if err != nil {
        return "unknown"
    }

    if strings.Contains(string(output), "Duplex: Full") {
        return "full"
    } else if strings.Contains(string(output), "Duplex: Half") {
        return "half"
    }

    return "unknown"
}

func (m *NetworkLinkMonitor) shouldWatchInterface(name string) bool {
    if len(m.config.WatchInterfaces) == 0 {
        return true
    }

    for _, iface := range m.config.WatchInterfaces {
        if iface == "*" || iface == name {
            return true
        }
    }

    return false
}

func (m *NetworkLinkMonitor) onLinkUp(name string, info *LinkInfo) {
    if !m.config.SoundOnUp {
        return
    }

    key := fmt.Sprintf("up:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["up"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkLinkMonitor) onLinkDown(name string, info *LinkInfo) {
    if !m.config.SoundOnDown {
        return
    }

    key := fmt.Sprintf("down:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkLinkMonitor) onSpeedChanged(name string, newInfo *LinkInfo, lastInfo *LinkInfo) {
    if !m.config.SoundOnSpeed {
        return
    }

    key := fmt.Sprintf("speed:%s:%d->%d", name, lastInfo.Speed, newInfo.Speed)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["speed"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *NetworkLinkMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ip | System Tool | Free | Network interface info |
| ethtool | System Tool | Free | Link speed/duplex |
| ifconfig | System Tool | Free | macOS interface info |

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
| macOS | Supported | Uses ifconfig |
| Linux | Supported | Uses ip, ethtool |
