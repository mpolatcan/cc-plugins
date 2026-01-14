# Feature: Sound Event Process Monitor

Play sounds for process lifecycle events, high CPU usage, and memory consumption.

## Summary

Monitor running processes for startup, termination, high resource usage, and zombie states, playing sounds for process events.

## Motivation

- Process awareness
- Resource monitoring
- Zombie process alerts
- High CPU detection
- Service status tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Process Events

| Event | Description | Example |
|-------|-------------|---------|
| Process Started | New process | nginx started |
| Process Ended | Process exited | exit code 0 |
| High CPU | CPU > threshold | > 80% |
| High Memory | MEM > threshold | > 1GB |
| Zombie Process | Defunct process | zombie |
| OOM Killed | OOM killer | killed |

### Configuration

```go
type ProcessMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchProcesses    []string          `json:"watch_processes"` // "nginx", "postgres", "*"
    CPUThreshold      float64           `json:"cpu_threshold"` // 80.0 default
    MemoryThreshold   int               `json:"memory_threshold_mb"` // 1000 default
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnEnd        bool              `json:"sound_on_end"`
    SoundOnHighCPU    bool              `json:"sound_on_high_cpu"`
    SoundOnHighMem    bool              `json:"sound_on_high_mem"`
    SoundOnZombie     bool              `json:"sound_on_zombie"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:process status               # Show process status
/ccbell:process add nginx            # Add process to watch
/ccbell:process remove nginx
/ccbell:process cpu 80               # Set CPU threshold
/ccbell:process sound start <sound>
/ccbell:process test                 # Test process sounds
```

### Output

```
$ ccbell:process status

=== Sound Event Process Monitor ===

Status: Enabled
CPU Threshold: 80%
Memory Threshold: 1000 MB

Watched Processes:

[1] nginx
    PID: 1234
    Status: RUNNING
    CPU: 2.5%
    Memory: 150 MB
    Started: 2 days ago
    Sound: bundled:process-nginx

[2] postgres
    PID: 2345
    Status: RUNNING
    CPU: 5.0%
    Memory: 4.2 GB
    Started: 1 week ago
    Sound: bundled:process-postgres

[3] redis-server
    PID: 3456
    Status: RUNNING
    CPU: 1.2%
    Memory: 45 MB
    Started: 3 days ago
    Sound: bundled:process-redis

[4] dockerd
    PID: 4567
    Status: RUNNING
    CPU: 15.0%
    Memory: 800 MB
    Started: 2 days ago
    Sound: bundled:process-docker

Top Resource Consumers:

  1. postgres (CPU: 5.0%, MEM: 4.2 GB)
  2. dockerd (CPU: 15.0%, MEM: 800 MB)
  3. chrome (CPU: 45.0%, MEM: 2.1 GB)

Recent Process Events:
  [1] dockerd: Process Started (2 days ago)
       PID 4567
       Sound: bundled:process-start
  [2] postgres: Process Started (1 week ago)
       PID 2345
       Sound: bundled:process-start
  [3] nginx: Process Ended (3 days ago)
       Exit code: 0

Process Statistics:
  Watched: 4
  Running: 4
  Zombie: 0
  High CPU: 0

Sound Settings:
  Start: bundled:process-start
  End: bundled:process-end
  High CPU: bundled:process-high-cpu
  High Mem: bundled:process-high-mem

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds directly:
- Monitoring feature using ps/top
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Monitor

```go
type ProcessMonitor struct {
    config          *ProcessMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    processState    map[string]*ProcessInfo
    lastEventTime   map[string]time.Time
}

type ProcessInfo struct {
    PID         int
    Name        string
    Command     string
    Status      string // "running", "zombie", "sleeping", "unknown"
    CPU         float64
    Memory      int64 // bytes
    Started     time.Time
    LastCPU     float64
    LastMemory  int64
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
    processes := m.listProcesses()

    // Build current process map
    currentProcs := make(map[string]*ProcessInfo)

    for _, proc := range processes {
        if !m.shouldWatchProcess(proc.Name) {
            continue
        }

        key := fmt.Sprintf("%d", proc.PID)
        currentProcs[key] = proc

        // Check for new processes
        if _, exists := m.processState[key]; !exists {
            m.onProcessStarted(proc)
        }

        // Check for resource threshold breaches
        m.checkResourceThresholds(proc)
    }

    // Check for ended processes
    for key, lastProc := range m.processState {
        if _, exists := currentProcs[key]; !exists {
            m.onProcessEnded(lastProc)
        }
    }

    m.processState = currentProcs
}

func (m *ProcessMonitor) listProcesses() []*ProcessInfo {
    var processes []*ProcessInfo

    cmd := exec.Command("ps", "aux")
    output, err := cmd.Output()
    if err != nil {
        return processes
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "USER") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 11 {
            continue
        }

        // Parse ps aux output
        // USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
        cpu, _ := strconv.ParseFloat(parts[2], 64)
        mem, _ := strconv.ParseFloat(parts[3], 64)
        pid, _ := strconv.Atoi(parts[1])

        // Get command (rest of the line)
        command := strings.Join(parts[10:], " ")
        name := m.extractProcessName(command)

        // Get memory in bytes
        rss, _ := strconv.ParseInt(parts[5], 10, 64)
        memory := rss * 1024 // RSS is in KB

        // Parse start time
        startTime := m.parseStartTime(parts[9], parts[10])

        // Determine status
        status := "running"
        if strings.Contains(parts[7], "Z") {
            status = "zombie"
        } else if strings.Contains(parts[7], "S") {
            status = "sleeping"
        }

        proc := &ProcessInfo{
            PID:     pid,
            Name:    name,
            Command: command,
            Status:  status,
            CPU:     cpu,
            Memory:  memory,
            Started: startTime,
        }

        processes = append(processes, proc)
    }

    return processes
}

func (m *ProcessMonitor) extractProcessName(command string) string {
    // Extract process name from command
    parts := strings.Fields(command)
    if len(parts) == 0 {
        return "unknown"
    }

    baseCmd := filepath.Base(parts[0])

    // Handle common patterns
    if baseCmd == "python" || baseCmd == "python3" {
        if len(parts) >= 2 {
            script := filepath.Base(parts[1])
            return script
        }
    }

    // Remove arguments starting with -
    for _, part := range parts {
        if !strings.HasPrefix(part, "-") && !strings.HasPrefix(part, "/") {
            return filepath.Base(part)
        }
    }

    return baseCmd
}

func (m *ProcessMonitor) parseStartTime(datePart, timePart string) time.Time {
    now := time.Now()

    // Parse "Jan14" or "14:00" format
    if len(datePart) >= 5 {
        if _, err := time.Parse("Jan02", datePart); err == nil {
            // Format: MMMDD (e.g., Jan14)
            parsed, _ := time.Parse("2006-Jan02", now.Format("2006")+"-"+datePart)
            return parsed
        }
    }

    // Format: HH:MM (e.g., 14:30)
    if strings.Contains(timePart, ":") {
        parsed, _ := time.Parse("15:04", timePart)
        return time.Date(now.Year(), now.Month(), now.Day(),
            parsed.Hour(), parsed.Minute(), 0, 0, now.Location())
    }

    return now
}

func (m *ProcessMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, p := range m.config.WatchProcesses {
        if p == "*" || name == p || strings.Contains(strings.ToLower(name), strings.ToLower(p)) {
            return true
        }
    }

    return false
}

func (m *ProcessMonitor) checkResourceThresholds(proc *ProcessInfo) {
    // Check CPU threshold
    if proc.CPU >= m.config.CPUThreshold {
        if m.config.SoundOnHighCPU {
            m.onHighCPU(proc)
        }
    }

    // Check memory threshold (convert MB to bytes)
    memMB := proc.Memory / (1024 * 1024)
    if int(memMB) >= m.config.MemoryThreshold {
        if m.config.SoundOnHighMem {
            m.onHighMemory(proc)
        }
    }

    // Check for zombie
    if proc.Status == "zombie" {
        if m.config.SoundOnZombie {
            m.onZombieProcess(proc)
        }
    }
}

func (m *ProcessMonitor) onProcessStarted(proc *ProcessInfo) {
    key := fmt.Sprintf("start:%s:%d", proc.Name, proc.PID)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *ProcessMonitor) onProcessEnded(proc *ProcessInfo) {
    if m.config.SoundOnEnd {
        key := fmt.Sprintf("end:%s", proc.Name)
        if m.shouldAlert(key, 1*time.Minute) {
            sound := m.config.Sounds["end"]
            if sound != "" {
                m.player.Play(sound, 0.3)
            }
        }
    }
}

func (m *ProcessMonitor) onHighCPU(proc *ProcessInfo) {
    key := fmt.Sprintf("highcpu:%s:%d", proc.Name, proc.PID)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["high_cpu"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ProcessMonitor) onHighMemory(proc *ProcessInfo) {
    key := fmt.Sprintf("highmem:%s:%d", proc.Name, proc.PID)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["high_mem"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ProcessMonitor) onZombieProcess(proc *ProcessInfo) {
    key := fmt.Sprintf("zombie:%s:%d", proc.Name, proc.PID)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["zombie"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
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
| ps | System Tool | Free | Process status |

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
| macOS | Supported | Uses ps |
| Linux | Supported | Uses ps |
