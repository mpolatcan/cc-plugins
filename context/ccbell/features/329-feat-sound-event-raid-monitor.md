# Feature: Sound Event RAID Monitor

Play sounds for RAID array status changes and rebuild events.

## Summary

Monitor RAID array status, rebuild progress, and disk events, playing sounds for RAID events.

## Motivation

- Array health awareness
- Rebuild completion feedback
- Disk failure alerts
- Redundancy status

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### RAID Events

| Event | Description | Example |
|-------|-------------|---------|
| Array Degraded | Disk failed | 1 disk missing |
| Array Rebuilding | Rebuild in progress | 50% complete |
| Array Healthy | Restored | Rebuild complete |
| Disk Added | New disk in array | /dev/sdd added |

### Configuration

```go
type RAIDMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchArrays      []string          `json:"watch_arrays"] // "md0", "md127"
    SoundOnDegraded  bool              `json:"sound_on_degraded"]
    SoundOnRebuild   bool              `json:"sound_on_rebuild"]
    SoundOnHealthy   bool              `json:"sound_on_healthy"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type RAIDEvent struct {
    Array      string
    Level      string // "0", "1", "5", "6", "10"
    State      string // "active", "degraded", "recovering", "clean"
    Disks      int
    TotalDisks int
    RebuildPct float64
    EventType  string
}
```

### Commands

```bash
/ccbell:raid status                   # Show RAID status
/ccbell:raid add md0                  # Add array to watch
/ccbell:raid remove md0
/ccbell:raid sound degraded <sound>
/ccbell:raid sound rebuild <sound>
/ccbell:raid test                     # Test RAID sounds
```

### Output

```
$ ccbell:raid status

=== Sound Event RAID Monitor ===

Status: Enabled
Degraded Sounds: Yes
Rebuild Sounds: Yes

Watched Arrays: 2

[1] md0 (RAID 5)
    State: DEGRADED
    Disks: 3/4
    Rebuild: --
    Status: WARNING
    Sound: bundled:raid-degraded

[2] md1 (RAID 1)
    State: RECOVERING
    Disks: 2/2
    Rebuild: 50%
    Status: REBUILDING
    Sound: bundled:raid-rebuild

Recent Events:
  [1] md0: Array Degraded (5 min ago)
       Disk /dev/sdb failed
  [2] md1: Array Rebuilding (1 hour ago)
       50% complete
  [3] md0: Disk Added (2 hours ago)
       /dev/sdd added to array

RAID Statistics:
  Healthy arrays: 1
  Degraded: 1
  Rebuilding: 1

Sound Settings:
  Degraded: bundled:raid-degraded
  Rebuild: bundled:raid-rebuild
  Healthy: bundled:raid-healthy

[Configure] [Add Array] [Test All]
```

---

## Audio Player Compatibility

RAID monitoring doesn't play sounds directly:
- Monitoring feature using mdadm
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### RAID Monitor

```go
type RAIDMonitor struct {
    config          *RAIDMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    raidState       map[string]*RAIDInfo
    lastEventTime   map[string]time.Time
}

type RAIDInfo struct {
    Array      string
    Level      string
    State      string
    Disks      int
    TotalDisks int
    RebuildPct float64
}

func (m *RAIDMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.raidState = make(map[string]*RAIDInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *RAIDMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotRAIDState()

    for {
        select {
        case <-ticker.C:
            m.checkRAIDState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *RAIDMonitor) snapshotRAIDState() {
    cmd := exec.Command("cat", "/proc/mdstat")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseMDStat(string(output))
}

func (m *RAIDMonitor) checkRAIDState() {
    cmd := exec.Command("cat", "/proc/mdstat")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseMDStat(string(output))
}

func (m *RAIDMonitor) parseMDStat(output string) {
    lines := strings.Split(output, "\n")
    currentArrays := make(map[string]*RAIDInfo)

    var currentArray string
    var level string
    var state string = "unknown"
    var disks int
    var totalDisks int
    var rebuildPct float64

    for _, line := range lines {
        if strings.HasPrefix(line, "md") {
            // New array
            if currentArray != "" {
                // Save previous array
                currentArrays[currentArray] = &RAIDInfo{
                    Array:      currentArray,
                    Level:      level,
                    State:      state,
                    Disks:      disks,
                    TotalDisks: totalDisks,
                    RebuildPct: rebuildPct,
                }
            }

            // Parse new array
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                currentArray = strings.TrimSuffix(parts[0], ":")
                level = parts[3]

                // Parse disk count
                re := regexp.MustCompile(`\[(\d+)/(\d+)\]`)
                match := re.FindStringSubmatch(line)
                if match != nil {
                    disks, _ = strconv.Atoi(match[1])
                    totalDisks, _ = strconv.Atoi(match[2])
                }

                // Check state
                if strings.Contains(line, "recovering") || strings.Contains(line, "resync") {
                    state = "recovering"
                    rebuildPct = m.parseRebuildProgress(line)
                } else if strings.Contains(line, "degraded") {
                    state = "degraded"
                } else if strings.Contains(line, "active") || strings.Contains(line, "clean") {
                    state = "active"
                }
            }
            continue
        }

        // Check for device details
        if currentArray != "" && strings.HasPrefix(line, "      ") {
            if strings.Contains(line, "active") {
                state = "active"
            } else if strings.Contains(line, "recovery") {
                state = "recovering"
            } else if strings.Contains(line, "degraded") {
                state = "degraded"
            }
        }
    }

    // Save last array
    if currentArray != "" {
        currentArrays[currentArray] = &RAIDInfo{
            Array:      currentArray,
            Level:      level,
            State:      state,
            Disks:      disks,
            TotalDisks: totalDisks,
            RebuildPct: rebuildPct,
        }
    }

    // Evaluate state changes
    for name, info := range currentArrays {
        if !m.shouldWatchArray(name) {
            continue
        }

        lastInfo := m.raidState[name]
        m.evaluateRAIDState(name, info, lastInfo)
    }

    m.raidState = currentArrays
}

func (m *RAIDMonitor) parseRebuildProgress(line string) float64 {
    // Look for percentage in recovery line
    re := regexp.MustCompile(`(\d+\.?\d*)%`)
    match := re.FindStringSubmatch(line)
    if match != nil {
        pct, _ := strconv.ParseFloat(match[1], 64)
        return pct
    }
    return 0
}

func (m *RAIDMonitor) evaluateRAIDState(name string, info *RAIDInfo, lastInfo *RAIDInfo) {
    if lastInfo == nil {
        return
    }

    // Check state changes
    if info.State != lastInfo.State {
        switch info.State {
        case "degraded":
            if info.Disks < info.TotalDisks {
                m.onArrayDegraded(name, info.Disks, info.TotalDisks)
            }
        case "recovering":
            if lastInfo.State != "recovering" {
                m.onRebuildStarted(name)
            }
            // Check if rebuild completed
            if info.RebuildPct >= 100 && lastInfo.RebuildPct < 100 {
                m.onRebuildComplete(name)
            }
        case "active":
            if lastInfo.State == "degraded" || lastInfo.State == "recovering" {
                m.onArrayHealthy(name)
            }
        }
    }
}

func (m *RAIDMonitor) shouldWatchArray(name string) bool {
    if len(m.config.WatchArrays) == 0 {
        return true
    }

    for _, arr := range m.config.WatchArrays {
        if arr == name {
            return true
        }
    }

    return false
}

func (m *RAIDMonitor) onArrayDegraded(name string, disks int, total int) {
    if !m.config.SoundOnDegraded {
        return
    }

    key := fmt.Sprintf("degraded:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["degraded"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *RAIDMonitor) onRebuildStarted(name string) {
    if !m.config.SoundOnRebuild {
        return
    }

    key := fmt.Sprintf("rebuild:%s:start", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["rebuild"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *RAIDMonitor) onRebuildComplete(name string) {
    if !m.config.SoundOnHealthy {
        return
    }

    key := fmt.Sprintf("rebuild:%s:complete", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["healthy"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *RAIDMonitor) onArrayHealthy(name string) {
    if !m.config.SoundOnHealthy {
        return
    }

    key := fmt.Sprintf("healthy:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["healthy"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *RAIDMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/mdstat | File | Free | RAID status |
| mdadm | System Tool | Free | RAID management |

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
| macOS | Not Supported | No native software RAID |
| Linux | Supported | Uses /proc/mdstat |
| Windows | Not Supported | ccbell only supports macOS/Linux |
