# Feature: Sound Event Thread Monitor

Play sounds for thread creation and thread count events.

## Summary

Monitor thread creation, thread count changes, and thread limits, playing sounds for thread events.

## Motivation

- Thread leak detection
- Concurrency alerts
- Resource exhaustion warnings
- Performance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Thread Events

| Event | Description | Example |
|-------|-------------|---------|
| Thread Created | New thread | pthread_create |
| Thread Count High | Many threads | > 100 |
| Thread Limit | At max threads | 4096/4096 |
| Thread Leak | Increasing count | Leak detected |

### Configuration

```go
type ThreadMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchProcesses    []string          `json:"watch_processes"]
    WarningThreshold  int               `json:"warning_threshold"` // 100 default
    CriticalThreshold int               `json:"critical_threshold"` // 500 default
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnCritical   bool              `json:"sound_on_critical"]
    SoundOnCreate     bool              `json:"sound_on_create"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type ThreadEvent struct {
    ProcessName string
    PID         int
    ThreadCount int
    Limit       int
    UsagePercent float64
    EventType   string // "warning", "critical", "create", "leak"
}
```

### Commands

```bash
/ccbell:thread status                 # Show thread status
/ccbell:thread add java               # Add process to watch
/ccbell:thread remove java
/ccbell:thread warning 100            # Set warning threshold
/ccbell:thread sound warning <sound>
/ccbell:thread test                  # Test thread sounds
```

### Output

```
$ ccbell:thread status

=== Sound Event Thread Monitor ===

Status: Enabled
Warning: 100
Critical: 500

Watched Processes: 3

[1] java (PID: 1234)
    Threads: 245
    Limit: 4096
    Usage: 6%
    Status: OK
    Sound: bundled:stop

[2] chrome (PID: 5678)
    Threads: 89
    Limit: 2048
    Usage: 4%
    Status: OK
    Sound: bundled:stop

[3] node (PID: 9012)
    Threads: 156
    Limit: 1024
    Usage: 15%
    Status: WARNING
    Sound: bundled:thread-warning

Recent Events:
  [1] java: Thread Created (5 sec ago)
       244 -> 245 threads
  [2] node: Warning (10 min ago)
       102 threads (10%)
  [3] chrome: Thread Leak (1 hour ago)
       45 -> 89 threads

Thread Statistics (Last Hour):
  - java: +12 threads
  - chrome: +44 threads
  - node: +56 threads

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Create: bundled:stop
  Leak: bundled:stop

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Thread monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Thread Monitor

```go
type ThreadMonitor struct {
    config           *ThreadMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    processThreads   map[int]int
    threadHistory    map[int][]int // PID -> recent thread counts
    lastWarningTime  map[string]time.Time
}

func (m *ThreadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processThreads = make(map[int]int)
    m.threadHistory = make(map[int][]int)
    m.lastWarningTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ThreadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkThreads()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ThreadMonitor) checkThreads() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinThreads()
    } else {
        m.checkLinuxThreads()
    }
}

func (m *ThreadMonitor) checkDarwinThreads() {
    // Use ps to get thread counts
    cmd := exec.Command("ps", "-eo", "pid,comm,thcount")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePSOutput(string(output))
}

func (m *ThreadMonitor) checkLinuxThreads() {
    // Read from /proc/*/task for each process
    entries, err := os.ReadDir("/proc")
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        pid, err := strconv.Atoi(entry.Name())
        if err != nil {
            continue
        }

        // Get process name
        statusFile := filepath.Join("/proc", entry.Name(), "status")
        data, err := os.ReadFile(statusFile)
        if err != nil {
            continue
        }

        processName := m.extractProcessName(string(data))
        if !m.shouldWatchProcess(processName) {
            continue
        }

        // Count threads (number of task directories)
        taskPath := filepath.Join("/proc", entry.Name(), "task")
        tasks, err := os.ReadDir(taskPath)
        if err != nil {
            continue
        }

        m.evaluateThreadCount(pid, processName, len(tasks))
    }
}

func (m *ThreadMonitor) parsePSOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "PID") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        pid, _ := strconv.Atoi(parts[0])
        processName := parts[1]
        threadCount, _ := strconv.Atoi(parts[2])

        m.evaluateThreadCount(pid, processName, threadCount)
    }
}

func (m *ThreadMonitor) extractProcessName(statusData string) string {
    lines := strings.Split(statusData, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Name:") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) >= 2 {
                return strings.TrimSpace(parts[1])
            }
        }
    }
    return ""
}

func (m *ThreadMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, watch := range m.config.WatchProcesses {
        if strings.Contains(strings.ToLower(name), strings.ToLower(watch)) {
            return true
        }
    }

    return false
}

func (m *ThreadMonitor) evaluateThreadCount(pid int, name string, count int) {
    lastCount := m.processThreads[pid]
    m.processThreads[pid] = count

    // Get system thread limit
    limit := m.getThreadLimit()
    usagePercent := float64(count) / float64(limit) * 100

    // Update history for leak detection
    history := m.threadHistory[pid]
    history = append(history, count)
    if len(history) > 10 {
        history = history[len(history)-10:]
    }
    m.threadHistory[pid] = history

    // Check for thread leak
    if len(history) >= 5 {
        increasing := true
        for i := 1; i < len(history); i++ {
            if history[i] <= history[i-1] {
                increasing = false
                break
            }
        }
        if increasing && count > m.config.WarningThreshold {
            m.onThreadLeakDetected(name, pid, count)
        }
    }

    // Check thresholds
    if count >= m.config.CriticalThreshold {
        m.onThreadCritical(name, pid, count, limit, usagePercent)
    } else if count >= m.config.WarningThreshold {
        if lastCount < m.config.WarningThreshold {
            m.onThreadWarning(name, pid, count, limit, usagePercent)
        }
    }

    // Check for thread creation
    if count > lastCount && m.config.SoundOnCreate {
        m.onThreadCreated(name, pid, lastCount, count)
    }
}

func (m *ThreadMonitor) getThreadLimit() int {
    // Get NPROC limit
    cmd := exec.Command("ulimit", "-u")
    output, err := cmd.Output()
    if err == nil {
        if limit, err := strconv.Atoi(strings.TrimSpace(string(output))); err == nil {
            return limit
        }
    }

    // Default
    return 1024
}

func (m *ThreadMonitor) onThreadWarning(name string, pid int, count int, limit int, percent float64) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%d", pid)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ThreadMonitor) onThreadCritical(name string, pid int, count int, limit int, percent float64) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("critical:%d", pid)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *ThreadMonitor) onThreadCreated(name string, pid int, oldCount int, newCount int) {
    if !m.config.SoundOnCreate {
        return
    }

    // Only alert on significant thread creation bursts
    if newCount-oldCount < 5 {
        return
    }

    sound := m.config.Sounds["create"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ThreadMonitor) onThreadLeakDetected(name string, pid int, count int) {
    sound := m.config.Sounds["leak"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *ThreadMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastWarningTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastWarningTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | System Tool | Free | Process status |
| ulimit | System Tool | Free | Resource limits |
| /proc/*/task | File | Free | Linux thread listing |

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
| macOS | Supported | Uses ps command |
| Linux | Supported | Uses /proc/*/task |
| Windows | Not Supported | ccbell only supports macOS/Linux |
