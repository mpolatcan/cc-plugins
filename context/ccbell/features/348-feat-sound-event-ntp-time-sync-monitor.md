# Feature: Sound Event NTP Time Sync Monitor

Play sounds for NTP sync status changes and time drift events.

## Summary

Monitor NTP synchronization status, time drift, and stratum changes, playing sounds for time sync events.

## Motivation

- Time accuracy awareness
- Drift detection
- Sync status feedback
- Stratum change alerts
- Clock adjustment notifications

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
| Synced | NTP synchronized | Clock synced |
| Unsynchronized | NTP not synced | Clock unsynced |
| Time Drift | Large time difference | 5 second drift |
| Stratum Changed | Stratum level changed | Stratum 1 -> 2 |
| Offset High | Offset above threshold | 100ms offset |

### Configuration

```go
type NTPSyncMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Server            string            `json:"server"` // "pool.ntp.org"
    DriftThreshold    float64           `json:"drift_threshold_seconds"` // 1.0 default
    OffsetThreshold   float64           `json:"offset_threshold_ms"` // 100.0 default
    SoundOnSync       bool              `json:"sound_on_sync"`
    SoundOnUnsync     bool              `json:"sound_on_unsync"`
    SoundOnDrift      bool              `json:"sound_on_drift"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type NTPSyncEvent struct {
    Server      string
    Status      string // "synced", "unsynced", "stratum"
    Stratum     int
    Offset      float64 // milliseconds
    Drift       float64 // seconds
    EventType   string // "sync", "unsync", "drift", "stratum"
}
```

### Commands

```bash
/ccbell:ntp status                    # Show NTP status
/ccbell:ntp server pool.ntp.org       # Set NTP server
/ccbell:ntp drift 1.0                 # Set drift threshold
/ccbell:ntp sound sync <sound>
/ccbell:ntp sound drift <sound>
/ccbell:ntp test                      # Test NTP sounds
```

### Output

```
$ ccbell:ntp status

=== Sound Event NTP Time Sync Monitor ===

Status: Enabled
Drift Threshold: 1.0 seconds
Offset Threshold: 100 ms
Sync Sounds: Yes
Drift Sounds: Yes

NTP Status:
  Server: pool.ntp.org
  Status: SYNCHRONIZED
  Stratum: 2
  Offset: 2.5 ms
  Drift: 0.001 ppm
  Jitter: 0.5 ms
  Sound: bundled:ntp-sync

Time Sources:
  [1] 0.pool.ntp.org ( stratum 1 )
  [2] 1.pool.ntp.org ( stratum 1 )
  [3] 2.pool.ntp.org ( stratum 2 )

Recent Events:
  [1] NTP: Synchronized (5 min ago)
       Synced to stratum 1 server
  [2] NTP: Time Drift (1 hour ago)
       Drift: 0.5 seconds corrected
  [3] NTP: Stratum Changed (2 hours ago)
       Stratum: 3 -> 2

NTP Statistics:
  Avg Offset: 5.2 ms
  Max Drift: 1.2 seconds
  Sync Events: 15

Sound Settings:
  Sync: bundled:ntp-sync
  Unsync: bundled:ntp-unsync
  Drift: bundled:ntp-drift

[Configure] [Set Server] [Test All]
```

---

## Audio Player Compatibility

NTP monitoring doesn't play sounds directly:
- Monitoring feature using ntpq
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### NTP Time Sync Monitor

```go
type NTPSyncMonitor struct {
    config          *NTPSyncMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    syncState       *SyncInfo
    lastEventTime   map[string]time.Time
}

type SyncInfo struct {
    Server      string
    Status      string // "synced", "unsynced"
    Stratum     int
    Offset      float64
    Drift       float64
    Jitter      float64
    LastSync    time.Time
}

func (m *NTPSyncMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.syncState = &SyncInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NTPSyncMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSyncState()

    for {
        select {
        case <-ticker.C:
            m.checkSyncState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NTPSyncMonitor) snapshotSyncState() {
    m.checkSyncState()
}

func (m *NTPSyncMonitor) checkSyncState() {
    cmd := exec.Command("ntpq", "-p")
    output, err := cmd.Output()
    if err != nil {
        // Try timedatectl as fallback
        m.checkTimedatectl()
        return
    }

    m.parseNTPQOutput(string(output))
}

func (m *NTPSyncMonitor) parseNTPQOutput(output string) {
    lines := strings.Split(string(output), "\n")
    var newState SyncInfo

    for _, line := range lines {
        // Look for the active peer line (starts with * or +)
        if strings.HasPrefix(line, "*") || strings.HasPrefix(line, "+") {
            parts := strings.Fields(line)
            if len(parts) >= 10 {
                newState.Server = parts[0]

                // Parse offset
                offset, _ := strconv.ParseFloat(parts[8], 64)
                newState.Offset = offset

                // Parse jitter
                jitter, _ := strconv.ParseFloat(parts[9], 64)
                newState.Jitter = jitter
            }
        }
    }

    // Get detailed status
    cmd := exec.Command("ntpq", "-c", "rv")
    rvOutput, err := cmd.Output()
    if err == nil {
        // Parse status variables
        rvStr := string(rvOutput)
        if strings.Contains(rvStr, "sync_ntp") || strings.Contains(rvStr, "status=CONF") {
            newState.Status = "synced"
        } else {
            newState.Status = "unsynced"
        }
    }

    // Get stratum
    cmd = exec.Command("ntpq", "-c", "sysinfo")
    sysOutput, _ := cmd.Output()
    sysStr := string(sysOutput)
    re := regexp.MustCompile(`stratum\s+(\d+)`)
    match := re.FindStringSubmatch(sysStr)
    if match != nil {
        newState.Stratum, _ = strconv.Atoi(match[1])
    }

    m.evaluateSyncEvents(&newState)
}

func (m *NTPSyncMonitor) checkTimedatectl() {
    cmd := exec.Command("timedatectl", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    outputStr := string(output)
    var newState SyncInfo

    if strings.Contains(outputStr, "System clock synchronized: yes") {
        newState.Status = "synced"
    } else {
        newState.Status = "unsynced"
    }

    // Extract stratum if available
    re := regexp.MustCompile(`NTP service: (\w+)`)
    match := re.FindStringSubmatch(outputStr)
    if match != nil {
        newState.Server = match[1]
    }

    m.evaluateSyncEvents(&newState)
}

func (m *NTPSyncMonitor) evaluateSyncEvents(newState *SyncInfo) {
    lastState := m.syncState

    if lastState.Status != "" {
        // Check for sync status change
        if newState.Status == "synced" && lastState.Status != "synced" {
            m.onSynced(newState)
        } else if newState.Status != "synced" && lastState.Status == "synced" {
            m.onUnsynced(newState)
        }
    }

    // Check for drift
    if newState.Drift > m.config.DriftThreshold {
        m.onTimeDrift(newState)
    }

    // Check for high offset
    if newState.Offset > m.config.OffsetThreshold {
        m.onHighOffset(newState)
    }

    // Check stratum change
    if lastState.Stratum != 0 && newState.Stratum != lastState.Stratum {
        m.onStratumChanged(newState, lastState)
    }

    newState.LastSync = time.Now()
    m.syncState = newState
}

func (m *NTPSyncMonitor) onSynced(state *SyncInfo) {
    if !m.config.SoundOnSync {
        return
    }

    key := "sync"
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["sync"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NTPSyncMonitor) onUnsynced(state *SyncInfo) {
    if !m.config.SoundOnUnsync {
        return
    }

    key := "unsync"
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["unsync"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NTPSyncMonitor) onTimeDrift(state *SyncInfo) {
    if !m.config.SoundOnDrift {
        return
    }

    key := fmt.Sprintf("drift:%.2f", state.Drift)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["drift"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NTPSyncMonitor) onHighOffset(state *SyncInfo) {
    // Optional: alert for high offset
}

func (m *NTPSyncMonitor) onStratumChanged(newState *SyncInfo, lastState *SyncInfo) {
    // Optional: alert for stratum change
}

func (m *NTPSyncMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| macOS | Supported | Uses ntpq or sntp |
| Linux | Supported | Uses ntpq, timedatectl |
