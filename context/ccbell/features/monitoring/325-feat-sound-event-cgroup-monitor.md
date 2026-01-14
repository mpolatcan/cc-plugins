# Feature: Sound Event Cgroup Monitor

Play sounds for cgroup resource limit and event notifications.

## Summary

Monitor cgroup resource usage, limits, and events, playing sounds for cgroup events.

## Motivation

- Container resource awareness
- Limit violation alerts
- Resource throttling feedback
- Cgroup event monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Cgroup Events

| Event | Description | Example |
|-------|-------------|---------|
| Memory High | Memory limit approached | 90% of limit |
| Memory OOM | OOM in cgroup | Container killed |
| CPU Throttled | CPU throttled | throttling period |
| PIDs Limit | Process limit reached | max pids |

### Configuration

```go
type CgroupMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchCgroups       []string          `json:"watch_cgroups"] // "docker-abc123.scope"
    MemoryWarningPct   float64           `json:"memory_warning_pct"` // 80.0 default
    CPUThrottleThreshold float64         `json:"cpu_throttle_threshold"` // 0.5 default
    SoundOnHigh        bool              `json:"sound_on_high"]
    SoundOnOOM         bool              `json:"sound_on_oom"]
    SoundOnThrottle    bool              `json:"sound_on_throttle"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type CgroupEvent struct {
    Cgroup      string
    MemoryUsage int64
    MemoryLimit int64
    CPUThrottle float64
    PIDsCurrent int
    PIDsLimit   int
    EventType   string // "memory_high", "oom", "throttle", "pids_limit"
}
```

### Commands

```bash
/ccbell:cgroup status                 # Show cgroup status
/ccbell:cgroup add docker-abc         # Add cgroup to watch
/ccbell:cgroup remove docker-abc
/ccbell:cgroup warning 80             # Set warning threshold
/ccbell:cgroup sound oom <sound>
/ccbell:cgroup test                   # Test cgroup sounds
```

### Output

```
$ ccbell:cgroup status

=== Sound Event Cgroup Monitor ===

Status: Enabled
Memory Warning: 80%
CPU Throttle Threshold: 50%

Watched Cgroups: 2

[1] docker-abc123def.scope
    Memory: 512 MB / 1 GB (51%)
    CPU Throttle: 0%
    PIDs: 45 / 1000
    Status: OK
    Sound: bundled:stop

[2] system.slice
    Memory: 8 GB / 16 GB (50%)
    CPU Throttle: 25%
    PIDs: 234 / 1000
    Status: THROTTLING
    Sound: bundled:cgroup-throttle

Recent Events:
  [1] docker-abc123def.scope: Memory High (5 min ago)
       900 MB / 1 GB (90%)
  [2] system.slice: CPU Throttled (10 min ago)
       Throttled: 25% of period
  [3] docker-abc123def.scope: OOM (1 hour ago)
       Container killed by OOM

Cgroup Statistics:
  OOM events: 2
  Throttle events: 15

Sound Settings:
  High: bundled:cgroup-high
  OOM: bundled:cgroup-oom
  Throttle: bundled:cgroup-throttle

[Configure] [Add Cgroup] [Test All]
```

---

## Audio Player Compatibility

Cgroup monitoring doesn't play sounds directly:
- Monitoring feature using cgroup filesystem
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cgroup Monitor

```go
type CgroupMonitor struct {
    config             *CgroupMonitorConfig
    player             *audio.Player
    running            bool
    stopCh             chan struct{}
    cgroupState        map[string]*CgroupInfo
    lastEventTime      map[string]time.Time
}

type CgroupInfo struct {
    Cgroup       string
    MemoryUsage  int64
    MemoryLimit  int64
    CPUThrottle  float64
    PIDsCurrent  int
    PIDsLimit    int
}

func (m *CgroupMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cgroupState = make(map[string]*CgroupInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CgroupMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCgroupState()

    for {
        select {
        case <-ticker.C:
            m.checkCgroupState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CgroupMonitor) snapshotCgroupState() {
    // Find cgroups to watch
    cgroups := m.findCgroups()
    for _, cgroup := range cgroups {
        m.checkCgroup(cgroup)
    }
}

func (m *CgroupMonitor) findCgroups() []string {
    var cgroups []string

    // Check docker cgroups
    if runtime.GOOS == "linux" {
        // Look for docker cgroups
        dockerPath := "/sys/fs/cgroup"
        entries, err := os.ReadDir(dockerPath)
        if err == nil {
            for _, entry := range entries {
                if strings.HasPrefix(entry.Name(), "docker-") ||
                   strings.HasPrefix(entry.Name(), "system.slice") {
                    if m.shouldWatchCgroup(entry.Name()) {
                        cgroups = append(cgroups, filepath.Join(dockerPath, entry.Name()))
                    }
                }
            }
        }
    }

    return cgroups
}

func (m *CgroupMonitor) checkCgroupState() {
    cgroups := m.findCgroups()
    for _, cgroup := range cgroups {
        m.checkCgroup(cgroup)
    }
}

func (m *CgroupMonitor) checkCgroup(path string) {
    cgroupName := filepath.Base(path)

    // Check memory usage
    memoryUsage := m.readCgroupInt(path, "memory", "memory.usage_in_bytes")
    memoryLimit := m.readCgroupInt(path, "memory", "memory.limit_in_bytes")

    // Check CPU throttling
    cpuThrottle := m.readCPUThrottle(path)

    // Check PIDs
    pidsCurrent := m.readCgroupInt(path, "pids", "pids.current")
    pidsLimit := m.readCgroupInt(path, "pids", "pids.max")

    info := &CgroupInfo{
        Cgroup:       cgroupName,
        MemoryUsage:  memoryUsage,
        MemoryLimit:  memoryLimit,
        CPUThrottle:  cpuThrottle,
        PIDsCurrent:  int(pidsCurrent),
        PIDsLimit:    int(pidsLimit),
    }

    lastInfo := m.cgroupState[cgroupName]
    m.evaluateCgroupState(cgroupName, info, lastInfo)

    m.cgroupState[cgroupName] = info
}

func (m *CgroupMonitor) readCgroupInt(path string, subsystem string, file string) int64 {
    filePath := filepath.Join(path, subsystem, file)
    data, err := os.ReadFile(filePath)
    if err != nil {
        return 0
    }

    val, _ := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
    return val
}

func (m *CgroupMonitor) readCPUThrottle(path string) float64 {
    // Read throttling stats
    statPath := filepath.Join(path, "cpu", "cpu.stat")
    data, err := os.ReadFile(statPath)
    if err != nil {
        return 0
    }

    // Parse throttling: nr_throttled, throttled_time
    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "nr_throttled") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                throttled, _ := strconv.ParseInt(parts[1], 10, 64)
                return float64(throttled)
            }
        }
    }

    return 0
}

func (m *CgroupMonitor) evaluateCgroupState(cgroup string, info *CgroupInfo, lastInfo *CgroupInfo) {
    // Check memory high
    if info.MemoryLimit > 0 {
        memoryPct := float64(info.MemoryUsage) / float64(info.MemoryLimit) * 100

        if memoryPct >= m.config.MemoryWarningPct {
            if lastInfo == nil || float64(lastInfo.MemoryUsage)/float64(lastInfo.MemoryLimit)*100 < m.config.MemoryWarningPct {
                m.onMemoryHigh(cgroup, info.MemoryUsage, info.MemoryLimit, memoryPct)
            }
        }
    }

    // Check CPU throttling
    if info.CPUThrottle > 0 {
        if lastInfo == nil || lastInfo.CPUThrottle == 0 {
            m.onCPUThrottled(cgroup, info.CPUThrottle)
        }
    }

    // Check PIDs limit
    if info.PIDsLimit > 0 && info.PIDsCurrent >= info.PIDsLimit {
        if lastInfo == nil || lastInfo.PIDsCurrent < info.PIDsLimit {
            m.onPIDsLimit(cgroup, info.PIDsCurrent, info.PIDsLimit)
        }
    }
}

func (m *CgroupMonitor) shouldWatchCgroup(name string) bool {
    if len(m.config.WatchCgroups) == 0 {
        return true
    }

    for _, cgroup := range m.config.WatchCgroups {
        if strings.Contains(name, cgroup) {
            return true
        }
    }

    return false
}

func (m *CgroupMonitor) onMemoryHigh(cgroup string, usage int64, limit int64, percent float64) {
    if !m.config.SoundOnHigh {
        return
    }

    key := fmt.Sprintf("memory_high:%s", cgroup)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CgroupMonitor) onOOM(cgroup string) {
    if !m.config.SoundOnOOM {
        return
    }

    key := fmt.Sprintf("oom:%s", cgroup)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["oom"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *CgroupMonitor) onCPUThrottled(cgroup string, throttled float64) {
    if !m.config.SoundOnThrottle {
        return
    }

    if throttled < m.config.CPUThrottleThreshold {
        return
    }

    key := fmt.Sprintf("throttle:%s", cgroup)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["throttle"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CgroupMonitor) onPIDsLimit(cgroup string, current int, limit int) {
    key := fmt.Sprintf("pids:%s", cgroup)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["pids_limit"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CgroupMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /sys/fs/cgroup/*/memory.usage_in_bytes | File | Free | Memory usage |
| /sys/fs/cgroup/*/cpu/cpu.stat | File | Free | CPU throttling |
| /sys/fs/cgroup/*/pids/pids.current | File | Free | PIDs count |

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
| macOS | Not Supported | No cgroup support |
| Linux | Supported | Uses cgroup filesystem |
| Windows | Not Supported | ccbell only supports macOS/Linux |
