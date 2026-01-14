# Feature: Sound Event NTP Monitor

Play sounds for NTP synchronization status, stratum changes, and offset alerts.

## Summary

Monitor NTP daemon (ntpd, chronyd, systemd-timesyncd) for synchronization status, stratum levels, and time offset events, playing sounds for NTP events.

## Motivation

- Time awareness
- Sync status
- Stratum monitoring
- Offset detection
- Clock drift alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### NTP Events

| Event | Description | Example |
|-------|-------------|---------|
| Sync Lost | NTP disconnected | no sync |
| Sync Restored | NTP connected | synced |
| Stratum Change | Stratum changed | stratum 2->3 |
| High Offset | Clock offset high | > 100ms |
| Offset Normal | Offset within range | < 10ms |
| Server Unreachable | NTP server down | timeout |

### Configuration

```go
type NTPMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchDaemon      string            `json:"watch_daemon"` // "ntpd", "chronyd", "timesyncd", "all"
    OffsetThreshold  float64           `json:"offset_threshold_ms"` // 100 default
    StratumWarning   int               `json:"stratum_warning"` // 4 default
    SoundOnSync      bool              `json:"sound_on_sync"`
    SoundOnUnsync    bool              `json:"sound_on_unsync"`
    SoundOnOffset    bool              `json:"sound_on_offset"`
    SoundOnStratum   bool              `json:"sound_on_stratum"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:ntp status                  # Show NTP status
/ccbell:ntp add chronyd             # Add NTP daemon to watch
/ccbell:ntp offset 100              # Set offset threshold
/ccbell:ntp sound sync <sound>
/ccbell:ntp test                    # Test NTP sounds
```

### Output

```
$ ccbell:ntp status

=== Sound Event NTP Monitor ===

Status: Enabled
Watch Daemon: all
Offset Threshold: 100ms
Stratum Warning: 4

NTP Status:

[1] chronyd (active)
    Status: SYNCED
    Stratum: 2
    Offset: +5.2ms
    Jitter: 0.5ms
    Servers: 4
    Last Sync: 5 min ago
    Sound: bundled:ntp-chrony

[2] systemd-timesyncd (inactive)
    Status: NOT SYNCED *** DOWN ***
    Stratum: -
    Last Error: No servers
    Sound: bundled:ntp-timesync *** FAILED ***

Recent Events:

[1] chronyd: Stratum Change (5 min ago)
       Stratum 3 -> 2
       Sound: bundled:ntp-stratum
  [2] systemd-timesyncd: Sync Lost (10 min ago)
       No NTP servers configured
       Sound: bundled:ntp-unsync
  [3] chronyd: High Offset (1 hour ago)
       +150ms > 100ms threshold
       Sound: bundled:ntp-offset

NTP Statistics:
  Total Daemons: 2
  Synced: 1
  Not Synced: 1
  Avg Offset: 5ms

Sound Settings:
  Sync: bundled:ntp-sync
  Unsync: bundled:ntp-unsync
  Offset: bundled:ntp-offset
  Stratum: bundled:ntp-stratum

[Configure] [Add Daemon] [Test All]
```

---

## Audio Player Compatibility

NTP monitoring doesn't play sounds directly:
- Monitoring feature using ntpq, chronyc, timedatectl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### NTP Monitor

```go
type NTPMonitor struct {
    config        *NTPMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    ntpState      map[string]*NTPInfo
    lastEventTime map[string]time.Time
}

type NTPInfo struct {
    Daemon     string // "ntpd", "chronyd", "timesyncd"
    Status     string // "synced", "unsynced", "unknown"
    Stratum    int
    Offset     float64 // milliseconds
    Jitter     float64
    Servers    int
    LastSync   time.Time
    LastError  string
}

func (m *NTPMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.ntpState = make(map[string]*NTPInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NTPMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotNTPState()

    for {
        select {
        case <-ticker.C:
            m.checkNTPState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NTPMonitor) snapshotNTPState() {
    m.checkNTPState()
}

func (m *NTPMonitor) checkNTPState() {
    // Check chronyd
    m.checkChronyd()

    // Check ntpd
    m.checkNtpd()

    // Check systemd-timesyncd
    m.checkSystemdTimesyncd()
}

func (m *NTPMonitor) checkChronyd() {
    // Check if chronyd is running
    cmd := exec.Command("pgrep", "-x", "chronyd")
    if err := cmd.Run(); err != nil {
        // Create inactive state
        info := &NTPInfo{
            Daemon: "chronyd",
            Status: "unknown",
        }
        m.processNTPStatus(info)
        return
    }

    info := &NTPInfo{
        Daemon: "chronyd",
    }

    // Get tracking information
    cmd = exec.Command("chronyc", "tracking")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "unknown"
        m.processNTPStatus(info)
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.HasPrefix(line, "Stratum") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                info.Stratum, _ = strconv.Atoi(parts[2])
            }
        }
        if strings.HasPrefix(line, "Leap status") {
            if strings.Contains(line, "Normal") {
                info.Status = "synced"
            } else {
                info.Status = "unsynced"
            }
        }
        if strings.HasPrefix(line, "Root delay") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                delay, _ := strconv.ParseFloat(parts[2], 64)
                info.Offset = delay * 1000 / 2 // Approximate
            }
        }
    }

    // Get activity count
    cmd = exec.Command("chronyc", "activity")
    activityOutput, _ := cmd.Output()
    if strings.Contains(string(activityOutput), "0 clients") {
        info.Servers = 0
    } else {
        info.Servers = 1
    }

    info.LastSync = time.Now()
    m.processNTPStatus(info)
}

func (m *NTPMonitor) checkNtpd() {
    // Check if ntpd is running
    cmd := exec.Command("pgrep", "-x", "ntpd")
    if err := cmd.Run(); err != nil {
        info := &NTPInfo{
            Daemon: "ntpd",
            Status: "unknown",
        }
        m.processNTPStatus(info)
        return
    }

    info := &NTPInfo{
        Daemon: "ntpd",
    }

    // Get peer status
    cmd = exec.Command("ntpq", "-p")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "unknown"
        m.processNTPStatus(info)
        return
    }

    lines := strings.Split(string(output), "\n")
    syncedPeers := 0

    for _, line := range lines {
        if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
            if strings.Contains(line, "*") || strings.Contains(line, "+") {
                syncedPeers++
            }
        }
    }

    info.Servers = syncedPeers

    if syncedPeers > 0 {
        info.Status = "synced"
    } else {
        info.Status = "unsynced"
    }

    // Get stratum
    cmd = exec.Command("ntpq", "-c", "rv")
    rvOutput, _ := cmd.Output()
    stratumRe := regexp.MustEach(`stratum=(\d+)`)
    stratumMatches := stratumRe.FindStringSubmatch(string(rvOutput))
    if len(stratumMatches) >= 2 {
        info.Stratum, _ = strconv.Atoi(stratumMatches[1])
    }

    m.processNTPStatus(info)
}

func (m *NTPMonitor) checkSystemdTimesyncd() {
    // Check if systemd-timesyncd is active
    cmd := exec.Command("timedatectl", "status")
    output, err := cmd.Output()
    if err != nil {
        info := &NTPInfo{
            Daemon: "systemd-timesyncd",
            Status: "unknown",
        }
        m.processNTPStatus(info)
        return
    }

    info := &NTPInfo{
        Daemon: "systemd-timesyncd",
    }

    outputStr := string(output)

    if strings.Contains(outputStr, "NTP service: active") {
        info.Status = "synced"
    } else if strings.Contains(outputStr, "NTP service: inactive") {
        info.Status = "unsynced"
    }

    // Get stratum (if available)
    stratumRe := regexp.MustEach(`Stratum:\s*(\d+)`)
    stratumMatches := stratumRe.FindStringSubmatch(outputStr)
    if len(stratumMatches) >= 2 {
        info.Stratum, _ = strconv.Atoi(stratumMatches[1])
    }

    // Get offset
    offsetRe := regexp.MustEach(`Time:.*([+-]\d+\.\d+)s`)
    offsetMatches := offsetRe.FindStringSubmatch(outputStr)
    if len(offsetMatches) >= 2 {
        info.Offset, _ = strconv.ParseFloat(offsetMatches[1], 64) * 1000
    }

    m.processNTPStatus(info)
}

func (m *NTPMonitor) processNTPStatus(info *NTPInfo) {
    lastInfo := m.ntpState[info.Daemon]

    if lastInfo == nil {
        m.ntpState[info.Daemon] = info

        if info.Status == "synced" && m.config.SoundOnSync {
            m.onNTPSynced(info)
        } else if info.Status == "unsynced" && m.config.SoundOnUnsync {
            m.onNTPUnsynced(info)
        }
        return
    }

    // Check for sync status changes
    if info.Status != lastInfo.Status {
        if info.Status == "synced" && lastInfo.Status == "unsynced" {
            if m.config.SoundOnSync && m.shouldAlert(info.Daemon+"sync", 5*time.Minute) {
                m.onNTPSynced(info)
            }
        } else if info.Status == "unsynced" && lastInfo.Status == "synced" {
            if m.config.SoundOnUnsync && m.shouldAlert(info.Daemon+"unsync", 2*time.Minute) {
                m.onNTPUnsynced(info)
            }
        }
    }

    // Check for stratum changes
    if info.Stratum != lastInfo.Stratum && info.Stratum >= m.config.StratumWarning {
        if m.config.SoundOnStratum && m.shouldAlert(info.Daemon+"stratum", 10*time.Minute) {
            m.onStratumChange(info, lastInfo.Stratum)
        }
    }

    // Check for high offset
    if info.Offset > m.config.OffsetThreshold && lastInfo.Offset <= m.config.OffsetThreshold {
        if m.config.SoundOnOffset && m.shouldAlert(info.Daemon+"offset", 5*time.Minute) {
            m.onHighOffset(info)
        }
    } else if info.Offset < m.config.OffsetThreshold && lastInfo.Offset > m.config.OffsetThreshold {
        m.onOffsetNormal(info)
    }

    m.ntpState[info.Daemon] = info
}

func (m *NTPMonitor) onNTPSynced(info *NTPInfo) {
    key := fmt.Sprintf("sync:%s", info.Daemon)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["sync"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NTPMonitor) onNTPUnsynced(info *NTPInfo) {
    key := fmt.Sprintf("unsync:%s", info.Daemon)
    if m.shouldAlert(key, 2*time.Minute) {
        sound := m.config.Sounds["unsync"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NTPMonitor) onStratumChange(info *NTPInfo, oldStratum int) {
    sound := m.config.Sounds["stratum"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *NTPMonitor) onHighOffset(info *NTPInfo) {
    key := fmt.Sprintf("offset:%s", info.Daemon)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["offset"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NTPMonitor) onOffsetNormal(info *NTPInfo) {
    sound := m.config.Sounds["normal"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *NTPMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| chronyc | System Tool | Free | chrony control |
| ntpq | System Tool | Free | NTP query |
| timedatectl | System Tool | Free | systemd time control |

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
| macOS | Supported | Uses ntpq, sntp |
| Linux | Supported | Uses chronyc, ntpq, timedatectl |
