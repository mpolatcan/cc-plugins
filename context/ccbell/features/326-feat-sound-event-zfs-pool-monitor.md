# Feature: Sound Event ZFS Pool Monitor

Play sounds for ZFS pool status changes and error events.

## Summary

Monitor ZFS pool status, scrub completion, and error events, playing sounds for ZFS events.

## Motivation

- Pool health awareness
- Scrub completion feedback
- Error detection
- Storage reliability

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### ZFS Pool Events

| Event | Description | Example |
|-------|-------------|---------|
| Pool Degraded | Reduced redundancy | 1 disk failed |
| Pool Healthy | Restored to healthy | Resilver complete |
| Scrub Complete | Scrub finished | No errors |
| I/O Error | Disk error detected | checksum error |

### Configuration

```go
type ZFSMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchPools      []string          `json:"watch_pools"] // "tank", "data"
    SoundOnDegraded bool              `json:"sound_on_degraded"]
    SoundOnHealthy  bool              `json:"sound_on_healthy"]
    SoundOnScrub    bool              `json:"sound_on_scrub"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 60 default
}

type ZFSEvent struct {
    Pool      string
    State     string // "DEGRADED", "ONLINE", "OFFLINE"
    ScrubStatus string // "completed", "in_progress", "none"
    Errors    int
    EventType string
}
```

### Commands

```bash
/ccbell:zfs status                    # Show ZFS status
/ccbell:zfs add tank                  # Add pool to watch
/ccbell:zfs remove tank
/ccbell:zfs sound degraded <sound>
/ccbell:zfs sound scrub <sound>
/ccbell:zfs test                      # Test ZFS sounds
```

### Output

```
$ ccbell:zfs status

=== Sound Event ZFS Pool Monitor ===

Status: Enabled
Degraded Sounds: Yes
Scrub Sounds: Yes

Watched Pools: 2

[1] tank
    State: ONLINE
    Health: 100%
    Last Scrub: 2 hours ago
    Errors: 0
    Sound: bundled:stop

[2] data
    State: DEGRADED
    Health: 75%
    Last Scrub: 1 day ago
    Errors: 5
    Sound: bundled:zfs-degraded

Recent Events:
  [1] data: Pool Degraded (5 min ago)
       1 disk failed
  [2] tank: Scrub Complete (2 hours ago)
       Completed in 4h 30m, 0 errors
  [3] data: I/O Error (1 day ago)
       5 checksum errors

ZFS Statistics:
  Total pools: 2
  Degraded: 1
  Total errors: 5

Sound Settings:
  Degraded: bundled:zfs-degraded
  Healthy: bundled:zfs-healthy
  Scrub: bundled:zfs-scrub

[Configure] [Add Pool] [Test All]
```

---

## Audio Player Compatibility

ZFS monitoring doesn't play sounds directly:
- Monitoring feature using ZFS tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### ZFS Pool Monitor

```go
type ZFSMonitor struct {
    config        *ZFSMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    poolState     map[string]*ZPoolInfo
    lastEventTime map[string]time.Time
}

type ZPoolInfo struct {
    Pool      string
    State     string
    Health    int
    ScrubAge  time.Duration
    Errors    int
}

func (m *ZFSMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.poolState = make(map[string]*ZPoolInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ZFSMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotZPoolState()

    for {
        select {
        case <-ticker.C:
            m.checkZPoolState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ZFSMonitor) snapshotZPoolState() {
    if runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
        return
    }

    cmd := exec.Command("zpool", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseZPoolStatus(string(output))
}

func (m *ZFSMonitor) checkZPoolState() {
    cmd := exec.Command("zpool", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseZPoolStatus(string(output))
}

func (m *ZFSMonitor) parseZPoolStatus(output string) {
    lines := strings.Split(output, "\n")
    currentPools := make(map[string]*ZPoolInfo)

    var currentPool string
    var state string = "UNKNOWN"
    var errors int
    var scrubAge time.Duration

    for _, line := range lines {
        line = strings.TrimSpace(line)

        // Pool name line
        if strings.HasPrefix(line, "pool:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                currentPool = parts[1]
                state = "ONLINE" // Default
                errors = 0
            }
            continue
        }

        // State line
        if strings.Contains(line, "state:") {
            parts := strings.Fields(line)
            for _, part := range parts {
                if part == "ONLINE" || part == "DEGRADED" || part == "FAULTED" || part == "OFFLINE" {
                    state = part
                    break
                }
            }
            continue
        }

        // Errors line
        if strings.Contains(line, "errors:") {
            if strings.Contains(line, "No known data errors") {
                errors = 0
            } else {
                re := regexp.MustCompile(`(\d+)`)
                matches := re.FindAllStringSubmatch(line, -1)
                for _, match := range matches {
                    if n, err := strconv.Atoi(match[1]); err == nil {
                        errors = n
                        break
                    }
                }
            }
            continue
        }

        // Last scrub line
        if strings.Contains(line, "scan:") && currentPool != "" {
            if strings.Contains(line, "scrub") {
                // Parse scrub age
                if strings.Contains(line, "in progress") {
                    scrubAge = -1 // In progress
                } else if strings.Contains(line, "performed") {
                    // Estimate age
                    scrubAge = 24 * time.Hour
                }
            }
        }
    }

    // Update state for each pool
    for _, pool := range m.config.WatchPools {
        state := m.getPoolState(pool)
        info := &ZPoolInfo{
            Pool:     pool,
            State:    state,
            Errors:   m.getPoolErrors(pool),
            ScrubAge: scrubAge,
        }

        currentPools[pool] = info
        m.evaluatePoolState(pool, info)
    }

    m.poolState = currentPools
}

func (m *ZFSMonitor) getPoolState(pool string) string {
    cmd := exec.Command("zpool", "get", "health", pool)
    output, err := cmd.Output()
    if err != nil {
        return "UNKNOWN"
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, pool) {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                return parts[2]
            }
        }
    }
    return "UNKNOWN"
}

func (m *ZFSMonitor) getPoolErrors(pool string) int {
    cmd := exec.Command("zpool", "status", pool)
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    if strings.Contains(string(output), "No known data errors") {
        return 0
    }

    // Count errors
    return 0 // Simplified
}

func (m *ZFSMonitor) evaluatePoolState(pool string, info *ZPoolInfo) {
    lastInfo := m.poolState[pool]

    if lastInfo == nil {
        return
    }

    // Check state change
    if info.State != lastInfo.State {
        if info.State == "DEGRADED" || info.State == "FAULTED" {
            m.onPoolDegraded(pool, info.State)
        } else if info.State == "ONLINE" && (lastInfo.State == "DEGRADED" || lastInfo.State == "FAULTED") {
            m.onPoolHealthy(pool)
        }
    }

    // Check new errors
    if info.Errors > 0 && lastInfo.Errors == 0 {
        m.onIOError(pool, info.Errors)
    }
}

func (m *ZFSMonitor) shouldWatchPool(pool string) bool {
    if len(m.config.WatchPools) == 0 {
        return true
    }

    for _, p := range m.config.WatchPools {
        if p == pool {
            return true
        }
    }

    return false
}

func (m *ZFSMonitor) onPoolDegraded(pool string, state string) {
    if !m.config.SoundOnDegraded {
        return
    }

    key := fmt.Sprintf("degraded:%s", pool)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["degraded"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *ZFSMonitor) onPoolHealthy(pool string) {
    if !m.config.SoundOnHealthy {
        return
    }

    key := fmt.Sprintf("healthy:%s", pool)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["healthy"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ZFSMonitor) onIOError(pool string, count int) {
    key := fmt.Sprintf("error:%s", pool)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ZFSMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| zpool | System Tool | Free | ZFS pool management |
| zfs | System Tool | Free | ZFS file system |

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
| macOS | Supported | ZFS via macOS ZFS or plugins |
| Linux | Supported | ZFS on Linux |
| Windows | Not Supported | ccbell only supports macOS/Linux |
