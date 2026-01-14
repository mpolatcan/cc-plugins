# Feature: Sound Event ARP Cache Monitor

Play sounds for ARP cache changes, duplicate IP detection, and ARP spoofing alerts.

## Summary

Monitor ARP cache (address resolution protocol) for cache entries, duplicate IPs, and suspicious activity, playing sounds for ARP events.

## Motivation

- Network awareness
- Duplicate IP detection
- ARP spoofing alerts
- Cache monitoring
- Network security

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### ARP Cache Events

| Event | Description | Example |
|-------|-------------|---------|
| New Entry | New MAC address | 00:11:22... |
| Entry Changed | MAC changed | changed |
| Duplicate IP | Two MACs for IP | conflict |
| Entry Expired | Cache entry aged out | expired |
| ARP Spoofing | Suspicious activity | detected |
| ARP Request | High request rate | > 100/s |

### Configuration

```go
type ARPCacheMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchInterfaces  []string          `json:"watch_interfaces"` // "eth0", "en0", "*"
    RequestThreshold int               `json:"request_threshold"` // 100 per minute
    SoundOnDuplicate bool              `json:"sound_on_duplicate"`
    SoundOnChanged   bool              `json:"sound_on_changed"`
    SoundOnSpoof     bool              `json:"sound_on_spoof"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:arp status                  # Show ARP cache status
/ccbell:arp add eth0                # Add interface to watch
/ccbell:arp sound duplicate <sound>
/ccbell:arp test                    # Test ARP sounds
```

### Output

```
$ ccbell:arp status

=== Sound Event ARP Cache Monitor ===

Status: Enabled
Watch Interfaces: all
Request Threshold: 100/min

ARP Cache Status:

[1] eth0
    Status: HEALTHY
    Entries: 256
    Stale: 5
    Incomplete: 0
    Sound: bundled:arp-eth0

[2] wlan0
    Status: WARNING *** WARNING ***
    Entries: 45
    Stale: 12
    Incomplete: 1
    Sound: bundled:arp-wlan0 *** WARNING ***

Recent Events:

[1] eth0: Duplicate IP Detected (5 min ago)
       192.168.1.100 has two MACs
       Sound: bundled:arp-duplicate
  [2] wlan0: Entry Changed (10 min ago)
       192.168.1.50 MAC changed
       Sound: bundled:arp-changed
  [3] eth0: New Entry (1 hour ago)
       192.168.1.200 -> 00:11:22:33:44:55
       Sound: bundled:arp-new

ARP Statistics:
  Total Entries: 301
  Stale: 17
  Incomplete: 1

Sound Settings:
  Duplicate: bundled:arp-duplicate
  Changed: bundled:arp-changed
  Spoof: bundled:arp-spoof
  New: bundled:arp-new

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

ARP monitoring doesn't play sounds directly:
- Monitoring feature using arp, ip neigh
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### ARP Cache Monitor

```go
type ARPCacheMonitor struct {
    config        *ARPCacheMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    arpState      map[string]*ARPInfo
    ipMacMap      map[string]string
    lastEventTime map[string]time.Time
}

type ARPInfo struct {
    Interface   string
    TotalEntries int
    StaleCount   int
    IncompleteCount int
    Status       string // "healthy", "warning", "critical"
    Entries      []ARPEntry
}

type ARPEntry struct {
    IP      string
    MAC     string
    State   string // "reachable", "stale", "failed", "incomplete"
    LastSeen time.Time
}

func (m *ARPCacheMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.arpState = make(map[string]*ARPInfo)
    m.ipMacMap = make(map[string]string)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ARPCacheMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotARPState()

    for {
        select {
        case <-ticker.C:
            m.checkARPState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ARPCacheMonitor) snapshotARPState() {
    m.checkARPState()
}

func (m *ARPCacheMonitor) checkARPState() {
    // Get ARP cache from ip neigh (Linux) or arp (macOS)
    if runtime.GOOS == "darwin" {
        m.checkMacOSARP()
    } else {
        m.checkLinuxARP()
    }
}

func (m *ARPCacheMonitor) checkMacOSARP() {
    cmd := exec.Command("arp", "-a", "-n")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse arp output
    // Example: hostname (192.168.1.1) at 00:11:22:33:44:55 on en0 ifscope [ethernet]
    lines := strings.Split(string(output), "\n")

    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || strings.HasPrefix(line, "?") {
            continue
        }

        entry := m.parseARPEntry(line, "en0") // Default interface
        if entry != nil {
            m.processARPEntry("en0", entry)
        }
    }
}

func (m *ARPCacheMonitor) checkLinuxARP() {
    // Use ip neigh for better output
    cmd := exec.Command("ip", "neigh", "show")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to arp
        cmd = exec.Command("arp", "-n")
        output, _ = cmd.Output()
    }

    lines := strings.Split(string(output), "\n")
    currentInterface := ""

    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        // Check for interface header in ip neigh output
        if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") {
            parts := strings.Fields(line)
            if len(parts) > 0 {
                currentInterface = parts[0]
            }
        }

        entry := m.parseIPNeighEntry(line, currentInterface)
        if entry != nil {
            m.processARPEntry(currentInterface, entry)
        }
    }
}

func (m *ARPCacheMonitor) parseARPEntry(line string, iface string) *ARPEntry {
    // Parse macOS arp output format
    // hostname (192.168.1.1) at 00:11:22:33:44:55 on en0 ifscope [ethernet]
    re := regexp.MustEach(`\(([0-9.]+)\)\s+at\s+([0-9a-fA-F:]+)`)
    matches := re.FindStringSubmatch(line)

    if len(matches) >= 3 {
        return &ARPEntry{
            IP:   matches[1],
            MAC:  strings.ToLower(matches[2]),
            State: "reachable",
        }
    }
    return nil
}

func (m *ARPCacheMonitor) parseIPNeighEntry(line string, iface string) *ARPEntry {
    // Parse ip neigh output format
    // 192.168.1.1 dev eth0 lladdr 00:11:22:33:44:55 REACHABLE
    parts := strings.Fields(line)
    if len(parts) < 6 {
        return nil
    }

    entry := &ARPEntry{
        IP:   parts[0],
        MAC:  parts[4],
    }

    // Parse state
    state := strings.ToLower(parts[5])
    switch state {
    case "reachable", "permanent", "noarp":
        entry.State = "reachable"
    case "stale", "delay":
        entry.State = "stale"
    case "failed", "none":
        entry.State = "failed"
    case "incomplete":
        entry.State = "incomplete"
    default:
        entry.State = "reachable"
    }

    return entry
}

func (m *ARPCacheMonitor) processARPEntry(iface string, entry *ARPEntry) {
    if !m.shouldWatchInterface(iface) {
        return
    }

    key := fmt.Sprintf("%s:%s", entry.IP, entry.MAC)

    // Check for duplicate IP (different MAC for same IP)
    existingMAC, exists := m.ipMacMap[entry.IP]
    if exists && existingMAC != entry.MAC {
        if m.config.SoundOnDuplicate && m.shouldAlert("duplicate:"+entry.IP, 5*time.Minute) {
            m.onDuplicateIP(entry.IP, existingMAC, entry.MAC)
        }
    }

    // Update cache
    m.ipMacMap[entry.IP] = entry.MAC
}

func (m *ARPCacheMonitor) shouldWatchInterface(iface string) bool {
    for _, intf := range m.config.WatchInterfaces {
        if intf == "*" || intf == iface {
            return true
        }
    }
    return false
}

func (m *ARPCacheMonitor) onDuplicateIP(ip string, oldMAC string, newMAC string) {
    sound := m.config.Sounds["duplicate"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ARPCacheMonitor) onMACChanged(ip string, oldMAC string, newMAC string) {
    if m.config.SoundOnChanged {
        sound := m.config.Sounds["changed"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ARPCacheMonitor) onARPSpoofingDetected(ip string) {
    if m.config.SoundOnSpoof {
        sound := m.config.Sounds["spoof"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *ARPCacheMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| arp | System Tool | Free | ARP cache viewer |
| ip | System Tool | Free | Network configuration |

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
| Linux | Supported | Uses ip neigh, arp |
