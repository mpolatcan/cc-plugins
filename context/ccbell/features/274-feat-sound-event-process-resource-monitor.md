# Feature: Sound Event Process Resource Monitor

Play sounds for process resource usage thresholds.

## Summary

Monitor individual process resource usage (CPU, memory, file descriptors), playing sounds when processes exceed thresholds.

## Motivation

- Memory leak detection
- CPU spike alerts
- Resource exhaustion warnings
- Process health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Process Resource Events

| Event | Description | Example |
|-------|-------------|---------|
| High CPU | Process > 80% | npm build |
| High Memory | Process > 500MB | Memory leak |
| FD Limit | Too many files | > 1000 |
| Zombie | Process zombie | Defunct |
| Thread Limit | Too many threads | > 500 |

### Configuration

```go
type ProcessResourceMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WatchProcesses      []string          `json:"watch_processes"` // Process names
    CPUThreshold        float64           `json:"cpu_threshold_percent"` // 80 default
    MemoryThresholdMB   int64             `json:"memory_threshold_mb"` // 500 default
    FDThreshold         int               `json:"fd_threshold"` // 1000 default
    ThreadThreshold     int               `json:"thread_threshold"` // 500 default
    SoundOnHighCPU      bool              `json:"sound_on_high_cpu"`
    SoundOnHighMemory   bool              `json:"sound_on_high_memory"`
    SoundOnThreshold    bool              `json:"sound_on_threshold"]
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 10 default
}

type ProcessResourceEvent struct {
    ProcessName string
    PID         int
    CPUPercent  float64
    MemoryMB    int64
    FDCount     int
    ThreadCount int
    EventType   string // "high_cpu", "high_memory", "fd_limit", "thread_limit"
}
```

### Commands

```bash
/ccbell:proc-resource status             # Show resource status
/ccbell:proc-resource add "chrome"       # Add process to watch
/ccbell:proc-resource remove "chrome"
/ccbell:proc-resource sound high-cpu <sound>
/ccbell:proc-resource test               # Test proc sounds
```

### Output

```
$ ccbell:proc-resource status

=== Sound Event Process Resource Monitor ===

Status: Enabled
CPU Threshold: 80%
Memory Threshold: 500 MB

Watched Processes: 3

[1] chrome
    PID: 1234
    CPU: 45%
    Memory: 820 MB
    FDs: 234
    Threads: 45
    Status: HIGH MEMORY
    Sound: bundled:stop

[2] node
    PID: 5678
    CPU: 92%
    Memory: 450 MB
    FDs: 56
    Threads: 12
    Status: HIGH CPU
    Sound: bundled:stop

[3] postgres
    PID: 9012
    CPU: 5%
    Memory: 125 MB
    FDs: 89
    Threads: 23
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] chrome: High Memory (5 min ago)
       820 MB used
  [2] node: High CPU (10 min ago)
       92% CPU usage
  [3] postgres: FD Limit (1 hour ago)
       1200 file descriptors

Sound Settings:
  High CPU: bundled:stop
  High Memory: bundled:stop
  Threshold: bundled:stop

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process resource monitoring doesn't play sounds directly:
- Monitoring feature using process tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Resource Monitor

```go
type ProcessResourceMonitor struct {
    config            *ProcessResourceMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    processState      map[int]*ProcessResourceState
    lastAlertTime     map[string]time.Time
}

type ProcessResourceState struct {
    PID         int
    Name        string
    CPUPercent  float64
    MemoryMB    int64
    FDCount     int
    ThreadCount int
}
```

```go
func (m *ProcessResourceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processState = make(map[int]*ProcessResourceState)
    m.lastAlertTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ProcessResourceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkProcesses()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ProcessResourceMonitor) checkProcesses() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinProcesses()
    } else {
        m.checkLinuxProcesses()
    }
}

func (m *ProcessResourceMonitor) checkDarwinProcesses() {
    // Use ps to get process info
    cmd := exec.Command("ps", "-eo", "pid,comm,%cpu,%mem,fd_count,thcount")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "PID") {
            continue
        }

        info := m.parsePSLine(line)
        if info == nil {
            continue
        }

        // Check if we should watch this process
        if !m.shouldWatch(info.Name) {
            continue
        }

        m.evaluateProcess(info)
    }
}

func (m *ProcessResourceMonitor) checkLinuxProcesses() {
    // Use ps with appropriate flags
    cmd := exec.Command("ps", "-eo", "pid,comm,%cpu,%mem,lfd,nlwp")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "PID") {
            continue
        }

        info := m.parsePSLine(line)
        if info == nil {
            continue
        }

        if !m.shouldWatch(info.Name) {
            continue
        }

        m.evaluateProcess(info)
    }
}

func (m *ProcessResourceMonitor) parsePSLine(line string) *ProcessResourceState {
    parts := strings.Fields(line)
    if len(parts) < 6 {
        return nil
    }

    pid, err := strconv.Atoi(parts[0])
    if err != nil {
        return nil
    }

    name := parts[1]

    cpu, _ := strconv.ParseFloat(parts[2], 64)
    mem, _ := strconv.ParseFloat(parts[3], 64)
    fds, _ := strconv.Atoi(parts[4])
    threads, _ := strconv.Atoi(parts[5])

    // Convert memory to MB
    memMB := int64(mem * 10) // Approximate, ps shows % of total

    return &ProcessResourceState{
        PID:         pid,
        Name:        name,
        CPUPercent:  cpu,
        MemoryMB:    memMB,
        FDCount:     fds,
        ThreadCount: threads,
    }
}

func (m *ProcessResourceMonitor) shouldWatch(processName string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, watch := range m.config.WatchProcesses {
        if strings.Contains(strings.ToLower(processName), strings.ToLower(watch)) {
            return true
        }
    }

    return false
}

func (m *ProcessResourceMonitor) evaluateProcess(info *ProcessResourceState) {
    lastState := m.processState[info.PID]

    // Check for high CPU
    if info.CPUPercent >= m.config.CPUThreshold {
        if lastState == nil || lastState.CPUPercent < m.config.CPUThreshold {
            m.onHighCPU(info)
        }
    }

    // Check for high memory
    if info.MemoryMB >= m.config.MemoryThresholdMB {
        if lastState == nil || lastState.MemoryMB < m.config.MemoryThresholdMB {
            m.onHighMemory(info)
        }
    }

    // Check for FD limit
    if info.FDCount >= m.config.FDThreshold {
        if lastState == nil || lastState.FDCount < m.config.FDThreshold {
            m.onFDLimit(info)
        }
    }

    // Check for thread limit
    if info.ThreadCount >= m.config.ThreadThreshold {
        if lastState == nil || lastState.ThreadCount < m.config.ThreadThreshold {
            m.onThreadLimit(info)
        }
    }

    m.processState[info.PID] = info
}

func (m *ProcessResourceMonitor) onHighCPU(info *ProcessResourceState) {
    if !m.config.SoundOnHighCPU {
        return
    }

    key := fmt.Sprintf("high_cpu:%d", info.PID)
    if m.shouldAlert(key) {
        sound := m.config.Sounds["high_cpu"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessResourceMonitor) onHighMemory(info *ProcessResourceState) {
    if !m.config.SoundOnHighMemory {
        return
    }

    key := fmt.Sprintf("high_memory:%d", info.PID)
    if m.shouldAlert(key) {
        sound := m.config.Sounds["high_memory"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessResourceMonitor) onFDLimit(info *ProcessResourceState) {
    if !m.config.SoundOnThreshold {
        return
    }

    key := fmt.Sprintf("fd_limit:%d", info.PID)
    if m.shouldAlert(key) {
        sound := m.config.Sounds["fd_limit"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessResourceMonitor) onThreadLimit(info *ProcessResourceState) {
    if !m.config.SoundOnThreshold {
        return
    }

    key := fmt.Sprintf("thread_limit:%d", info.PID)
    if m.shouldAlert(key) {
        sound := m.config.Sounds["thread_limit"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessResourceMonitor) shouldAlert(key string) time.Time {
    lastAlert := m.lastAlertTime[key]
    // Only alert once per hour per process
    if time.Since(lastAlert) < 1*time.Hour {
        return false
    }
    m.lastAlertTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | System Tool | Free | Process status |
| exec | Go Stdlib | Free | Command execution |

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
| Linux | Supported | Uses ps command |
| Windows | Not Supported | ccbell only supports macOS/Linux |
