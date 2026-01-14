# Feature: Sound Event Process Monitor

Play sounds for process and service events.

## Summary

Monitor specific processes and services, playing sounds when they start, stop, crash, or exceed resource thresholds.

## Motivation

- Service monitoring awareness
- Process crash detection
- Resource usage alerts
- Background task completion

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Process Events

| Event | Description | Example |
|-------|-------------|---------|
| Process Started | Process began running | `dockerd` started |
| Process Stopped | Process ended | `nginx` stopped |
| Process Crashed | Process exited with error | Exit code > 0 |
| High CPU | Process using too much CPU | > 90% CPU |
| High Memory | Process using too much RAM | > 4GB RAM |

### Configuration

```go
type ProcessMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchProcesses []*ProcessWatch `json:"watch_processes"`
    PollInterval  int               `json:"poll_interval_sec"` // 10 default
    Sounds        map[string]string `json:"sounds"`
}

type ProcessWatch struct {
    Name       string  `json:"name"` // "nginx", "docker"
    Command    string  `json:"command,omitempty"` // Match by command
    Sound      string  `json:"sound"`
    Enabled    bool    `json:"enabled"`
    MaxCPU     float64 `json:"max_cpu"` // 0 = no limit
    MaxMemory  uint64  `json:"max_memory"` // 0 = no limit
}

type ProcessStatus struct {
    PID        int
    Name       string
    CPU        float64
    Memory     uint64
    Running    bool
    ExitCode   int
}
```

### Commands

```bash
/ccbell:process status            # Show process status
/ccbell:process add nginx         # Add process to watch
/ccbell:process remove nginx      # Remove process
/ccbell:process sound started <sound>
/ccbell:process sound stopped <sound>
/ccbell:process sound crashed <sound>
/ccbell:process test              # Test process sounds
```

### Output

```
$ ccbell:process status

=== Sound Event Process Monitor ===

Status: Enabled
Poll Interval: 10s

Watched Processes: 4

[1] nginx
    PID: 12345
    Status: Running
    CPU: 2.5%
    Memory: 128 MB
    Sound: bundled:stop
    [Edit] [Remove]

[2] dockerd
    PID: 12346
    Status: Running
    CPU: 15.0%
    Memory: 512 MB
    Sound: bundled:stop
    [Edit] [Remove]

[3] postgresql
    PID: -
    Status: Stopped
    Last Exit: 1
    Sound: bundled:stop
    [Edit] [Remove]

[4] redis-server
    PID: 12347
    Status: Running
    CPU: 0.5%
    Memory: 64 MB
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] nginx: Started (5 min ago)
  [2] postgresql: Crashed (1 hour ago)
  [3] redis-server: Started (2 hours ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Monitor

```go
type ProcessMonitor struct {
    config      *ProcessMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    lastPIDs    map[string]int
    lastCPU     map[string]float64
    lastMemory  map[string]uint64
}

func (m *ProcessMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastPIDs = make(map[string]int)
    m.lastCPU = make(map[string]float64)
    m.lastMemory = make(map[string]uint64)
    go m.monitor()
}

func (m *ProcessMonitor) monitor() {
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

func (m *ProcessMonitor) checkProcesses() {
    for _, watch := range m.config.WatchProcesses {
        if !watch.Enabled {
            continue
        }

        status := m.getProcessStatus(watch)
        m.evaluateProcess(watch, status)
    }
}

func (m *ProcessMonitor) getProcessStatus(watch *ProcessWatch) *ProcessStatus {
    status := &ProcessStatus{Name: watch.Name}

    if runtime.GOOS == "darwin" {
        return m.getMacOSProcessStatus(watch, status)
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxProcessStatus(watch, status)
    }

    return status
}

func (m *ProcessMonitor) getMacOSProcessStatus(watch *ProcessWatch, status *ProcessStatus) *ProcessStatus {
    // macOS: ps command
    cmd := exec.Command("ps", "ax", "-o", "pid=,comm=,cpu=,rss=")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        pid, _ := strconv.Atoi(parts[0])
        cpu, _ := strconv.ParseFloat(parts[2], 64)
        rss, _ := strconv.ParseUint(parts[3], 10, 64) * 1024 // KB to bytes

        // Check if process matches
        if parts[1] == watch.Name || strings.Contains(parts[1], watch.Name) {
            status.PID = pid
            status.CPU = cpu
            status.Memory = rss
            status.Running = true
            return status
        }
    }

    status.Running = false
    return status
}

func (m *ProcessMonitor) getLinuxProcessStatus(watch *ProcessWatch, status *ProcessStatus) *ProcessStatus {
    // Linux: ps command with options
    cmd := exec.Command("ps", "ax", "-o", "pid=,comm=,cpu=,rss=")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        pid, _ := strconv.Atoi(parts[0])
        cpu, _ := strconv.ParseFloat(parts[2], 64)
        rss, _ := strconv.ParseUint(parts[3], 10, 64) * 1024

        if parts[1] == watch.Name || strings.Contains(parts[1], watch.Name) {
            status.PID = pid
            status.CPU = cpu
            status.Memory = rss
            status.Running = true
            return status
        }
    }

    status.Running = false
    return status
}

func (m *ProcessMonitor) evaluateProcess(watch *ProcessWatch, status *ProcessStatus) {
    lastPID := m.lastPIDs[watch.Name]
    m.lastPIDs[watch.Name] = status.PID

    // Check if process started
    if status.Running && lastPID == 0 {
        m.playSound(watch, "started")
        m.lastCPU[watch.Name] = 0
        m.lastMemory[watch.Name] = 0
    }

    // Check if process stopped
    if !status.Running && lastPID != 0 {
        m.playSound(watch, "stopped")
    }

    // Check resource thresholds
    if status.Running {
        // High CPU check
        if watch.MaxCPU > 0 && status.CPU > watch.MaxCPU {
            if m.lastCPU[watch.Name] <= watch.MaxCPU {
                m.playSound(watch, "high_cpu")
            }
        }

        // High memory check
        if watch.MaxMemory > 0 && status.Memory > watch.MaxMemory {
            if m.lastMemory[watch.Name] <= watch.MaxMemory {
                m.playSound(watch, "high_memory")
            }
        }
    }

    // Update last resource usage
    m.lastCPU[watch.Name] = status.CPU
    m.lastMemory[watch.Name] = status.Memory
}

func (m *ProcessMonitor) playSound(watch *ProcessWatch, event string) {
    sound := watch.Sound
    if sound == "" {
        sound = m.config.Sounds[event]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | System Tool | Free | Process listing |
| netstat | System Tool | Free | Network processes |

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
