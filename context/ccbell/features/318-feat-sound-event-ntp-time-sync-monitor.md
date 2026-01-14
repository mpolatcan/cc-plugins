# Feature: Sound Event NTP Time Sync Monitor

Play sounds for NTP synchronization events and time drift alerts.

## Summary

Monitor NTP time synchronization status, stratum changes, and time drift, playing sounds for sync events.

## Motivation

- Time accuracy awareness
- Stratum change detection
- Drift alerts
- Sync status feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### NTP Events

| Event | Description | Example |
|-------|-------------|---------|
| Sync Complete | NTP synchronized | Offset < 1ms |
| Sync Lost | NTP disconnected | No sync |
| Stratum Change | Source changed | Stratum 2 -> 3 |
| Large Drift | Time drift detected | > 1s offset |

### Configuration

```go
type NTPMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    NTPTool         string            `json:"ntp_tool"` // "ntpq", "timedatectl", "systemsetup"
    DriftThreshold  float64           `json:"drift_threshold_sec"` // 1.0 default
    SoundOnSync     bool              `json:"sound_on_sync"]
    SoundOnLost     bool              `json:"sound_on_lost"]
    SoundOnDrift    bool              `json:"sound_on_drift"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 60 default
}

type NTPEvent struct {
    Server      string
    Stratum     int
    Offset      float64
    Delay       float64
    State       string // "synced", "unsync", "stratum_change"
}
```

### Commands

```bash
/ccbell:ntp status                    # Show NTP status
/ccbell:ntp tool ntpq                 # Set NTP tool
/ccbell:ntp drift 1.0                 # Set drift threshold
/ccbell:ntp sound sync <sound>
/ccbell:ntp sound lost <sound>
/ccbell:ntp test                      # Test NTP sounds
```

### Output

```
$ ccbell:ntp status

=== Sound Event NTP Time Sync Monitor ===

Status: Enabled
Drift Threshold: 1.0s
Tool: ntpq

Synchronized: Yes
Stratum: 2
Offset: 0.5ms
Delay: 10ms

Server: time.apple.com (17.253.16.253)

Recent Events:
  [1] Sync Complete (5 min ago)
       Offset: 0.5ms, Stratum: 2
  [2] Stratum Change (1 hour ago)
       2 -> 3
  [3] Sync Lost (2 hours ago)
       No sync for 5 min

NTP Statistics:
  Avg offset: 1.2ms
  Sync uptime: 23 hours

Sound Settings:
  Sync: bundled:ntp-sync
  Lost: bundled:ntp-lost
  Drift: bundled:ntp-drift

[Configure] [Set Tool] [Test All]
```

---

## Audio Player Compatibility

NTP monitoring doesn't play sounds directly:
- Monitoring feature using NTP tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### NTP Time Sync Monitor

```go
type NTPMonitor struct {
    config          *NTPMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    ntpState        *NTPState
    lastEventTime   map[string]time.Time
}

type NTPState struct {
    Synced     bool
    Server     string
    Stratum    int
    Offset     float64
}

func (m *NTPMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.ntpState = &NTPState{}
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
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinNTP()
    } else {
        m.snapshotLinuxNTP()
    }
}

func (m *NTPMonitor) snapshotDarwinNTP() {
    cmd := exec.Command("systemsetup", "-getnetworktimeserver")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to ntpq
        m.snapshotNTPQ()
        return
    }

    // Parse server
    server := ""
    if strings.Contains(string(output), "Network Time Server:") {
        parts := strings.Split(string(output), ":")
        if len(parts) >= 2 {
            server = strings.TrimSpace(parts[1])
        }
    }

    // Check sync status with sntp
    cmd = exec.Command("sntp", "-S", server)
    if err := cmd.Run(); err == nil {
        m.ntpState.Synced = true
    } else {
        m.ntpState.Synced = false
    }

    m.ntpState.Server = server
}

func (m *NTPMonitor) snapshotLinuxNTP() {
    switch m.config.NTPTool {
    case "ntpq":
        m.snapshotNTPQ()
    case "timedatectl":
        m.snapshotTimedatectl()
    default:
        m.snapshotNTPQ()
    }
}

func (m *NTPMonitor) snapshotNTPQ() {
    cmd := exec.Command("ntpq", "-p")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseNTPQOutput(string(output))
}

func (m *NTPMonitor) snapshotTimedatectl() {
    cmd := exec.Command("timedatectl", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseTimedatectlOutput(string(output))
}

func (m *NTPMonitor) checkNTPState() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinNTP()
    } else {
        m.checkLinuxNTP()
    }
}

func (m *NTPMonitor) checkDarwinNTP() {
    m.snapshotDarwinNTP()
}

func (m *NTPMonitor) checkLinuxNTP() {
    m.snapshotLinuxNTP()
}

func (m *NTPMonitor) parseNTPQOutput(output string) {
    lines := strings.Split(output, "\n")

    var currentStratum int
    var server string
    var offset float64

    for _, line := range lines {
        if strings.HasPrefix(line, "     ") || strings.HasPrefix(line, " ") {
            // Data line
            parts := strings.Fields(line)
            if len(parts) >= 8 {
                // Format: remote refid st t when poll reach delay offset jitter
                if parts[0] != "" && parts[0] != "*" && parts[0] != "+" {
                    continue
                }

                server = parts[0]
                stratum, _ := strconv.Atoi(parts[2])
                currentStratum = stratum

                offsetStr := parts[7]
                offset, _ = strconv.ParseFloat(offsetStr, 64)
            }
        }
    }

    m.evaluateNTPState(server, currentStratum, offset)
}

func (m *NTPMonitor) parseTimedatectlOutput(output string) {
    lines := strings.Split(output, "\n")

    synced := false
    stratum := 0
    var server string

    for _, line := range lines {
        if strings.Contains(line, "Network time on: yes") {
            synced = true
        } else if strings.Contains(line, "NTP synchronized: yes") {
            synced = true
        } else if strings.Contains(line, "Time zone:") {
            // Extract server if available
        }
    }

    m.evaluateNTPState(server, stratum, 0)
}

func (m *NTPMonitor) evaluateNTPState(server string, stratum int, offset float64) {
    // Check sync state change
    if m.ntpState.Synced && !m.checkNTPStatus() {
        // Lost sync
        m.onSyncLost()
        m.ntpState.Synced = false
    } else if !m.ntpState.Synced && m.checkNTPStatus() {
        // Sync restored
        m.onSyncComplete(offset, stratum)
        m.ntpState.Synced = true
    }

    // Check stratum change
    if stratum != m.ntpState.Stratum && stratum > 0 {
        m.onStratumChange(m.ntpState.Stratum, stratum)
        m.ntpState.Stratum = stratum
    }

    // Check drift
    if offset > m.config.DriftThreshold {
        m.onTimeDrift(offset)
    }

    m.ntpState.Server = server
    m.ntpState.Offset = offset
}

func (m *NTPMonitor) checkNTPStatus() bool {
    // Quick check if NTP is working
    cmd := exec.Command("ntpq", "-c", "rv", "loopfilter")
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    return strings.Contains(string(output), "offset")
}

func (m *NTPMonitor) onSyncComplete(offset float64, stratum int) {
    if !m.config.SoundOnSync {
        return
    }

    key := "sync:complete"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["sync"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NTPMonitor) onSyncLost() {
    if !m.config.SoundOnLost {
        return
    }

    key := "sync:lost"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["lost"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *NTPMonitor) onStratumChange(oldStratum int, newStratum int) {
    key := fmt.Sprintf("stratum:%d->%d", oldStratum, newStratum)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["stratum_change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NTPMonitor) onTimeDrift(offset float64) {
    if !m.config.SoundOnDrift {
        return
    }

    key := fmt.Sprintf("drift:%.2f", offset)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["drift"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
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
| ntpq | System Tool | Free | NTP query |
| timedatectl | System Tool | Free | systemd time management |
| systemsetup | System Tool | Free | macOS time setup |

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
| macOS | Supported | Uses systemsetup, sntp |
| Linux | Supported | Uses ntpq, timedatectl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
