# Feature: Sound Event Process Monitor

Play sounds for process state changes, high CPU/memory usage, and process termination.

## Summary

Monitor system processes for state changes, resource usage thresholds, and unexpected termination, playing sounds for process events.

## Motivation

- Process awareness
- Resource alerting
- Service failure detection
- Performance monitoring
- Process termination alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Process Events

| Event | Description | Example |
|-------|-------------|---------|
| Process Started | New process started | nginx started |
| Process Terminated | Process ended | killed, exited |
| High CPU | CPU usage > threshold | > 80% |
| High Memory | Memory usage > threshold | > 80% |
| Zombie Process | Zombie detected | zombie |
| High Thread Count | Too many threads | > 1000 |

### Configuration

```go
type ProcessMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchProcesses   []string          `json:"watch_processes"` // process names or pids
    CPUThreshold     int               `json:"cpu_threshold"` // 80 default
    MemoryThreshold  int               `json:"memory_threshold"` // 80 default
    ThreadThreshold  int               `json:"thread_threshold"` // 1000 default
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnTerminate bool              `json:"sound_on_terminate"`
    SoundOnHighCPU   bool              `json:"sound_on_high_cpu"`
    SoundOnHighMem   bool              `json:"sound_on_high_mem"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:process status              # Show process status
/ccbell:process add nginx           # Add process to watch
/ccbell:process threshold cpu 80    # Set CPU threshold
/ccbell:process sound highcpu <sound>
/ccbell:process test                # Test process sounds
```

### Output

```
$ ccbell:process status

=== Sound Event Process Monitor ===

Status: Enabled
CPU Threshold: 80%
Memory Threshold: 80%

Watched Processes:

[1] nginx (pid: 1234)
    Status: RUNNING
    CPU: 15%
    Memory: 2.5 GB
    Threads: 12
    Sound: bundled:process-nginx

[2] postgres (pid: 5678)
    Status: RUNNING
    CPU: 5%
    Memory: 8.2 GB
    Threads: 45
    Sound: bundled:process-postgres

[3] node (pid: 9012) *** HIGH CPU *** *** WARNING ***
    Status: RUNNING
    CPU: 92% *** HIGH ***
    Memory: 4.1 GB
    Threads: 28
    Sound: bundled:process-node *** WARNING ***

Recent Events:

[1] node: High CPU (5 min ago)
       CPU usage 92% > 80% threshold
       Sound: bundled:process-highcpu
  [2] postgres: Process Started (1 hour ago)
       PID 5678 started
       Sound: bundled:process-start
  [3] nginx: High Memory (2 hours ago)
       Memory 3.2 GB > 80% threshold
       Sound: bundled:process-highmem

Process Statistics:
  Total Watched: 3
  Running: 3
  High CPU: 1
  High Memory: 0

Sound Settings:
  Start: bundled:process-start
  Terminate: bundled:process-terminate
  High CPU: bundled:process-highcpu
  High Memory: bundled:process-highmem

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds directly:
- Monitoring feature using ps, top
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Process Monitor

```go
type ProcessMonitor struct {
    config        *ProcessMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    processState  map[string]*ProcessInfo
    lastEventTime map[string]time.Time
}

type ProcessInfo struct {
    Name        string
    PID         int
    Status      string // "running", "zombie", "sleeping"
    CPUPercent  float64
    MemoryBytes int64
    Threads     int
    Started     time.Time
}

func (m *ProcessMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processState = make(map[string]*ProcessInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ProcessMonitor) monitor() {
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

func (m *ProcessMonitor) snapshotProcessState() {
    m.checkProcessState()
}

func (m *ProcessMonitor) checkProcessState() {
    for _, processName := range m.config.WatchProcesses {
        info := m.getProcessInfo(processName)
        if info != nil {
            m.processProcessStatus(info)
        }
    }
}

func (m *ProcessMonitor) getProcessInfo(processName string) *ProcessInfo {
    // Try to find by name first
    cmd := exec.Command("ps", "aux", "|", "grep", processName)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || strings.Contains(line, "grep") {
            continue
        }

        // Check if this is the process we're looking for
        fields := strings.Fields(line)
        if len(fields) < 11 {
            continue
        }

        procName := strings.TrimPrefix(fields[10], "[")
        procName = strings.TrimSuffix(procName, "]")

        if strings.Contains(fields[10], processName) || procName == processName {
            return m.parsePsOutput(line, processName)
        }
    }

    return nil
}

func (m *ProcessMonitor) parsePsOutput(line string, processName string) *ProcessInfo {
    fields := strings.Fields(line)
    if len(fields) < 11 {
        return nil
    }

    info := &ProcessInfo{
        Name: processName,
    }

    // Parse PID
    pid, _ := strconv.Atoi(fields[1])
    info.PID = pid

    // Parse CPU
    cpu, _ := strconv.ParseFloat(fields[2], 64)
    info.CPUPercent = cpu

    // Parse Memory
    mem, _ := strconv.ParseFloat(fields[3], 64)
    info.MemoryBytes = int64(mem * 1024 * 1024)

    // Parse Status
    status := fields[7]
    if status == "Z" {
        info.Status = "zombie"
    } else if status == "S" {
        info.Status = "sleeping"
    } else {
        info.Status = "running"
    }

    // Parse Threads (if available)
    if len(fields) > 13 {
        threads, _ := strconv.Atoi(fields[12])
        info.Threads = threads
    }

    return info
}

func (m *ProcessMonitor) processProcessStatus(info *ProcessInfo) {
    key := strconv.Itoa(info.PID)
    lastInfo := m.processState[key]

    if lastInfo == nil {
        m.processState[key] = info
        if m.config.SoundOnStart {
            m.onProcessStarted(info)
        }
        return
    }

    // Check for termination
    if lastInfo != nil && info.Status != lastInfo.Status {
        if info.Status != "running" && lastInfo.Status == "running" {
            if m.config.SoundOnTerminate {
                m.onProcessTerminated(info)
            }
        }
    }

    // Check for high CPU
    if info.CPUPercent >= float64(m.config.CPUThreshold) {
        if lastInfo == nil || info.CPUPercent > lastInfo.CPUPercent {
            if m.config.SoundOnHighCPU && m.shouldAlert(key+"cpu", 5*time.Minute) {
                m.onHighCPU(info)
            }
        }
    }

    // Check for high memory
    if info.MemoryBytes >= int64(m.config.MemoryThreshold)*1024*1024*10 {
        if m.config.SoundOnHighMem && m.shouldAlert(key+"mem", 5*time.Minute) {
            m.onHighMemory(info)
        }
    }

    m.processState[key] = info
}

func (m *ProcessMonitor) onProcessStarted(info *ProcessInfo) {
    key := fmt.Sprintf("start:%d", info.PID)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *ProcessMonitor) onProcessTerminated(info *ProcessInfo) {
    key := fmt.Sprintf("terminate:%s", info.Name)
    if m.shouldAlert(key, 2*time.Minute) {
        sound := m.config.Sounds["terminate"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessMonitor) onHighCPU(info *ProcessInfo) {
    sound := m.config.Sounds["high_cpu"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ProcessMonitor) onHighMemory(info *ProcessInfo) {
    sound := m.config.Sounds["high_mem"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ProcessMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| top | System Tool | Free | Resource monitoring |

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
| macOS | Supported | Uses ps, top |
| Linux | Supported | Uses ps, top |
