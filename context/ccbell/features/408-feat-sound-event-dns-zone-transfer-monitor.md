# Feature: Sound Event DNS Zone Transfer Monitor

Play sounds for DNS zone transfers, AXFR/IXFR events, and serial number changes.

## Summary

Monitor DNS zone transfers between primary and secondary servers, playing sounds for transfer events.

## Motivation

- DNS replication tracking
- Zone change awareness
- Replication delay alerts
- DNS consistency monitoring
- Master/slave sync feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### DNS Zone Transfer Events

| Event | Description | Example |
|-------|-------------|---------|
| AXFR Started | Zone transfer began | full transfer |
| AXFR Completed | Transfer finished | done |
| IXFR Started | Incremental transfer | delta sync |
| Serial Changed | Zone serial updated | 2026011401 |
| Zone Updated | Records modified | 5 changes |
| Transfer Failed | Transfer error | timeout |

### Configuration

```go
type DNSZoneTransferMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchZones        []string          `json:"watch_zones"` // "example.com", "*"
    PrimaryServers    []string          `json:"primary_servers"` // "ns1.example.com"
    SecondaryServers  []string          `json:"secondary_servers"` // "ns2.example.com"
    SoundOnTransfer   bool              `json:"sound_on_transfer"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:dnszone status                 # Show zone transfer status
/ccbell:dnszone add example.com        # Add zone to watch
/ccbell:dnszone remove example.com
/ccbell:dnszone sound transfer <sound>
/ccbell:dnszone sound complete <sound>
/ccbell:dnszone test                   # Test zone sounds
```

### Output

```
$ ccbell:dnszone status

=== Sound Event DNS Zone Transfer Monitor ===

Status: Enabled
Transfer Sounds: Yes
Complete Sounds: Yes
Fail Sounds: Yes

Watched Zones: 2
Watched Servers: 4

Zone Transfer Status:

[1] example.com (Primary: ns1.example.com)
    Serial: 2026011405
    Last Transfer: 2 hours ago
    Type: AXFR
    Records: 150
    Status: COMPLETED
    Sound: bundled:dnszone-example

[2] example.com (Secondary: ns2.example.com)
    Serial: 2026011405
    Last Sync: 2 hours ago
    Type: AXFR
    Status: IN SYNC
    Sound: bundled:dnszone-secondary

[3] sub.example.com (Primary: ns1.example.com)
    Serial: 2026011402
    Last Transfer: 5 min ago
    Type: IXFR
    Records: 10
    Status: COMPLETED
    Sound: bundled:dnszone-sub

[4] test.io (Primary: ns1.test.io)
    Serial: 2026010100
    Last Transfer: 1 day ago
    Type: NONE
    Status: STALE (out of sync)
    Sound: bundled:dnszone-test *** WARNING ***

Recent Events:
  [1] sub.example.com: Zone Transfer Completed (5 min ago)
       10 records transferred
  [2] test.io: Transfer Failed (1 hour ago)
       Connection timeout
  [3] example.com: Serial Changed (2 hours ago)
       2026011404 -> 2026011405

Zone Statistics:
  Total Zones: 4
  In Sync: 3
  Out of Sync: 1
  Transfers Today: 5

Sound Settings:
  Transfer: bundled:dnszone-transfer
  Complete: bundled:dnszone-complete
  Fail: bundled:dnszone-fail

[Configure] [Add Zone] [Test All]
```

---

## Audio Player Compatibility

Zone transfer monitoring doesn't play sounds directly:
- Monitoring feature using dig/dnssec-check
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### DNS Zone Transfer Monitor

```go
type DNSZoneTransferMonitor struct {
    config          *DNSZoneTransferMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    zoneState       map[string]*ZoneInfo
    lastEventTime   map[string]time.Time
}

type ZoneInfo struct {
    Name       string
    Server     string
    Serial     uint32
    Type       string // "AXFR", "IXFR", "NONE"
    Status     string // "in_sync", "transferring", "stale", "failed"
    Records    int
    LastCheck  time.Time
    LastTransfer time.Time
}

func (m *DNSZoneTransferMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.zoneState = make(map[string]*ZoneInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DNSZoneTransferMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotZoneState()

    for {
        select {
        case <-ticker.C:
            m.checkZoneState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSZoneTransferMonitor) snapshotZoneState() {
    m.checkZoneState()
}

func (m *DNSZoneTransferMonitor) checkZoneState() {
    for _, zone := range m.config.WatchZones {
        // Check primary servers
        for _, server := range m.config.PrimaryServers {
            m.checkZone(zone, server, true)
        }

        // Check secondary servers
        for _, server := range m.config.SecondaryServers {
            m.checkZone(zone, server, false)
        }
    }
}

func (m *DNSZoneTransferMonitor) checkZone(zone, server string, isPrimary bool) {
    id := fmt.Sprintf("%s@%s", zone, server)

    info := &ZoneInfo{
        Name:      zone,
        Server:    server,
        LastCheck: time.Now(),
    }

    // Get serial number using dig
    cmd := exec.Command("dig", "+short", "@"+server, zone, "SOA")
    output, err := cmd.Output()

    if err != nil {
        info.Status = "failed"
        m.processZoneStatus(id, info)
        return
    }

    // Parse SOA record
    // Parse: "ns1.example.com. hostmaster.example.com. 2026011405 3600 900 604800 86400"
    outputStr := strings.TrimSpace(string(output))
    parts := strings.Fields(outputStr)

    if len(parts) >= 3 {
        serial, _ := strconv.ParseUint(parts[2], 10, 32)
        info.Serial = uint32(serial)
    }

    // Check zone transfer capability
    m.checkZoneTransfer(zone, server, info)

    m.processZoneStatus(id, info)
}

func (m *DNSZoneTransferMonitor) checkZoneTransfer(zone, server string, info *ZoneInfo) {
    // Try zone transfer to detect AXFR/IXFR capability
    cmd := exec.Command("dig", "@"+server, zone, "AXFR")
    output, err := cmd.Output()

    if err != nil {
        // Transfer failed - might be blocked
        info.Type = "NONE"
        info.Status = "blocked"
        return
    }

    outputStr := string(output)

    // Count records in response
    lines := strings.Split(outputStr, "\n")
    recordCount := 0
    for _, line := range lines {
        if strings.HasPrefix(line, zone) || strings.HasPrefix(line, ";;" ) {
            continue
        }
        if strings.TrimSpace(line) != "" {
            recordCount++
        }
    }

    info.Records = recordCount

    // Detect transfer type based on record count
    if recordCount > 100 {
        info.Type = "AXFR"
    } else if recordCount > 0 {
        info.Type = "IXFR"
    }

    // Check sync status by comparing with last known state
    lastInfo := m.zoneState[fmt.Sprintf("%s@%s", zone, server)]
    if lastInfo != nil {
        if info.Serial != lastInfo.Serial {
            info.LastTransfer = time.Now()
            info.Status = "transferring"
        } else {
            info.Status = "in_sync"
        }
    } else {
        info.LastTransfer = time.Now()
        info.Status = "in_sync"
    }
}

func (m *DNSZoneTransferMonitor) processZoneStatus(id string, info *ZoneInfo) {
    lastInfo := m.zoneState[id]

    if lastInfo == nil {
        m.zoneState[id] = info
        return
    }

    // Check for serial changes
    if info.Serial != lastInfo.Serial {
        m.onSerialChanged(info)
    }

    // Check for transfer status changes
    if info.Status == "transferring" && lastInfo.Status != "transferring" {
        if m.config.SoundOnTransfer {
            m.onTransferStarted(info)
        }
    }

    if info.Status == "in_sync" && lastInfo.Status == "transferring" {
        if m.config.SoundOnComplete {
            m.onTransferComplete(info)
        }
    }

    if info.Status == "failed" && lastInfo.Status != "failed" {
        if m.config.SoundOnFail {
            m.onTransferFailed(info)
        }
    }

    m.zoneState[id] = info
}

func (m *DNSZoneTransferMonitor) onSerialChanged(info *ZoneInfo) {
    key := fmt.Sprintf("serial:%s", info.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["serial"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSZoneTransferMonitor) onTransferStarted(info *ZoneInfo) {
    if !m.config.SoundOnTransfer {
        return
    }

    key := fmt.Sprintf("transfer:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["transfer"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *DNSZoneTransferMonitor) onTransferComplete(info *ZoneInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSZoneTransferMonitor) onTransferFailed(info *ZoneInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", info.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DNSZoneTransferMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| dig | System Tool | Free | DNS query tool (bind-utils) |

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
| macOS | Supported | Uses dig (bind-tools) |
| Linux | Supported | Uses dig (dnsutils) |
