# Feature: Sound Event Process Resource Monitor

Play sounds for process resource usage threshold crossings.

## Summary

Monitor process CPU, memory, and I/O usage, playing sounds when processes exceed resource thresholds.

## Motivation

- Process resource awareness
- Resource hog detection
- Memory leak alerts
- CPU spike detection
- Process performance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Process Resource Events

| Event | Description | Example |
|-------|-------------|---------|
| High CPU | Process CPU > threshold | CPU > 90% |
| High Memory | Process memory > threshold | Memory > 80% |
| High IO | Process I/O > threshold | I/O > 10MB/s |
| Zombie Process | Zombie process detected | Defunct process |
| Process Started | New process started | Process spawned |
| Process Exited | Process exited | Process terminated |

### Configuration

```go
type ProcessResourceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchProcesses    []string          `json:"watch_processes"` // "postgres", "nginx", "*"
    CPUThreshold      float64           `json:"cpu_threshold"` // 90.0 default
    MemoryThreshold   float64           `json:"memory_threshold"` // 80.0 default
    IOThresholdMB     float64           `json:"io_threshold_mb"` // 10.0 default
    SoundOnCPU        bool              `json:"sound_on_cpu"`
    SoundOnMemory     bool              `json:"sound_on_memory"`
    SoundOnZombie     bool              `json:"sound_on_zombie"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type ProcessResourceEvent struct {
    PID         int
    Name        string
    Command     string
    CPUPercent  float64
    MemoryMB    float64
    IOMBps      float64
    Status      string // "running", "zombie", "sleeping"
    EventType   string // "high_cpu", "high_memory", "high_io", "zombie", "start", "exit"
}
```

### Commands

```bash
/ccbell:process status                # Show process resource status
/ccbell:process add postgres          # Add process to watch
/ccbell:process remove postgres
/ccbell:process cpu 90                # Set CPU threshold
/ccbell:process memory 80             # Set memory threshold
/ccbell:process test                  # Test process sounds
```

### Output

```
$ ccbell:process status

=== Sound Event Process Resource Monitor ===

Status: Enabled
CPU Threshold: 90%
Memory Threshold: 80%
IO Threshold: 10 MB/s
CPU Sounds: Yes
Memory Sounds: Yes
Zombie Sounds: Yes

Watched Processes: 3

[1] postgres (PID: 1234)
    CPU: 15.2%
    Memory: 2048 MB (8%)
    IO: 2.5 MB/s
    Status: RUNNING
    Sound: bundled:process-db

[2] nginx (PID: 5678)
    CPU: 5.1%
    Memory: 512 MB (2%)
    IO: 0.1 MB/s
    Status: RUNNING
    Sound: bundled:process-web

[3] chrome (PID: 9999)
    CPU: 95.5% *** HIGH ***
    Memory: 4096 MB (16%)
    IO: 15.2 MB/s *** HIGH ***
    Status: RUNNING
    Sound: bundled:process-browser

Recent Events:
  [1] chrome: High CPU (5 min ago)
       CPU: 95.5% > 90% threshold
  [2] chrome: High IO (10 min ago)
       IO: 15.2 MB/s > 10 MB/s threshold
  [3] postgres: Process Started (1 hour ago)
       Service started

Process Statistics:
  Monitored: 3 processes
  High CPU Events: 5
  High Memory: 0

Sound Settings:
  High CPU: bundled:process-cpu
  High Memory: bundled:process-memory
  Zombie: bundled:process-zombie

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds directly:
- Monitoring feature using ps
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Resource Monitor

```go
type ProcessResourceMonitor struct {
    config          *ProcessResourceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    processState    map[int]*ProcessInfo
    lastEventTime   map[string]time.Time
}

type ProcessInfo struct {
    PID         int
    Name        string
    Command     string
    CPUPercent  float64
    MemoryKB    int64
    MemoryMB    float64
    IOMBps      float64
    Status      string
    StartTime   time.Time
}

func (m *ProcessResourceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processState = make(map[int]*ProcessInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ProcessResourceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotProcessState()

    for {
        select {
        case <-ticker.C:
            m.checkProcessState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ProcessResourceMonitor) snapshotProcessState() {
    m.checkProcessState()
}

func (m *ProcessResourceMonitor) checkProcessState() {
    cmd := exec.Command("ps", "aux")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentPIDs := m.parsePSOutput(string(output))

    // Check for new processes
    for pid, info := range currentPIDs {
        if _, exists := m.processState[pid]; !exists {
            if m.shouldWatchProcess(info.Name) {
                m.processState[pid] = info
                m.onProcessStarted(info)
            }
        }
    }

    // Check for exited processes
    for pid, lastInfo := range m.processState {
        if _, exists := currentPIDs[pid]; !exists {
            delete(m.processState, pid)
            if m.shouldWatchProcess(lastInfo.Name) {
                m.onProcessExited(lastInfo)
            }
        }
    }

    // Check resource thresholds
    for pid, info := range currentPIDs {
        lastInfo := m.processState[pid]
        if lastInfo == nil {
            continue
        }

        info.StartTime = lastInfo.StartTime
        m.processState[pid] = info

        if m.shouldWatchProcess(info.Name) {
            m.evaluateResourceUsage(info, lastInfo)
        }
    }
}

func (m *ProcessResourceMonitor) parsePSOutput(output string) map[int]*ProcessInfo {
    processes := make(map[int]*ProcessInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "USER") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 11 {
            continue
        }

        user := parts[0]
        pid, _ := strconv.Atoi(parts[1])
        cpu, _ := strconv.ParseFloat(parts[2], 64)
        mem, _ := strconv.ParseFloat(parts[3], 64)
        vsz, _ := strconv.ParseInt(parts[4], 10, 64)
        rss, _ := strconv.ParseInt(parts[5], 10, 64)
        stat := parts[7]
        time := parts[9]
        command := strings.Join(parts[10:], " ")

        // Get process name from command
        name := filepath.Base(command)
        if idx := strings.Index(name, " "); idx != -1 {
            name = name[:idx]
        }

        processes[pid] = &ProcessInfo{
            PID:        pid,
            Name:       name,
            Command:    command,
            CPUPercent: cpu,
            MemoryKB:   rss,
            MemoryMB:   float64(rss) / 1024,
            Status:     stat,
            StartTime:  m.parseTime(time),
        }
    }

    return processes
}

func (m *ProcessResourceMonitor) parseTime(timeStr string) time.Time {
    // Parse ps time format (e.g., "14:23" or "01:23:45")
    now := time.Now()

    parts := strings.Split(timeStr, ":")
    if len(parts) == 2 {
        // MM:SS format
        min, _ := strconv.Atoi(parts[0])
        sec, _ := strconv.Atoi(parts[1])
        return now.Add(-time.Duration(min)*time.Minute - time.Duration(sec)*time.Second)
    } else if len(parts) == 3 {
        // HH:MM:SS format
        hours, _ := strconv.Atoi(parts[0])
        min, _ := strconv.Atoi(parts[1])
        sec, _ := strconv.Atoi(parts[2])
        return now.Add(-time.Duration(hours)*time.Hour - time.Duration(min)*time.Minute - time.Duration(sec)*time.Second)
    }

    return now
}

func (m *ProcessResourceMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, p := range m.config.WatchProcesses {
        if p == "*" || strings.Contains(name, p) {
            return true
        }
    }

    return false
}

func (m *ProcessResourceMonitor) evaluateResourceUsage(info *ProcessInfo, lastInfo *ProcessInfo) {
    // Check CPU threshold crossing
    if info.CPUPercent >= m.config.CPUThreshold &&
        lastInfo.CPUPercent < m.config.CPUThreshold {
        m.onHighCPU(info)
    }

    // Check memory threshold crossing
    if info.MemoryMB >= m.config.MemoryThreshold &&
        lastInfo.MemoryMB < m.config.MemoryThreshold {
        m.onHighMemory(info)
    }

    // Check for zombie processes
    if info.Status == "Z" && lastInfo.Status != "Z" {
        m.onZombieProcess(info)
    }
}

func (m *ProcessResourceMonitor) onHighCPU(info *ProcessInfo) {
    if !m.config.SoundOnCPU {
        return
    }

    key := fmt.Sprintf("cpu:%d", info.PID)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["cpu"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessResourceMonitor) onHighMemory(info *ProcessInfo) {
    if !m.config.SoundOnMemory {
        return
    }

    key := fmt.Sprintf("memory:%d", info.PID)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["memory"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessResourceMonitor) onZombieProcess(info *ProcessInfo) {
    if !m.config.SoundOnZombie {
        return
    }

    key := fmt.Sprintf("zombie:%d", info.PID)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["zombie"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *ProcessResourceMonitor) onProcessStarted(info *ProcessInfo) {
    // Optional: sound when watched process starts
}

func (m *ProcessResourceMonitor) onProcessExited(info *ProcessInfo) {
    // Optional: sound when watched process exits
}

func (m *ProcessResourceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ps | System Tool | Free | Process listing |

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
| macOS | Supported | Uses ps aux |
| Linux | Supported | Uses ps aux |
