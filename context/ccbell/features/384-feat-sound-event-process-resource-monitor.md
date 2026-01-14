# Feature: Sound Event Process Resource Monitor

Play sounds for process resource thresholds, memory leaks, and CPU spikes.

## Summary

Monitor specific processes for memory usage, CPU consumption, and resource thresholds, playing sounds for resource events.

## Motivation

- Resource leak detection
- Process performance alerts
- Memory pressure awareness
- CPU spike detection
- Service health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Process Resource Events

| Event | Description | Example |
|-------|-------------|---------|
| High Memory | Memory > threshold | > 1GB |
| CPU Spike | CPU > threshold | > 90% |
| Process Crashed | Exit unexpectedly | segfault |
| Process Slowed | Response time high | > 5s |
| Too Many Files | FDs > threshold | > 1024 |
| Zombies | Zombie processes | defunct |

### Configuration

```go
type ProcessResourceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchProcesses    []string          `json:"watch_processes"` // "nginx", "postgres", "*"
    MemoryThresholdMB int               `json:"memory_threshold_mb"` // 1024 default
    CPUThreshold      float64           `json:"cpu_threshold"` // 90.0 default
    FDThreshold       int               `json:"fd_threshold"` // 1024 default
    SoundOnHighMem    bool              `json:"sound_on_high_mem"`
    SoundOnHighCPU    bool              `json:"sound_on_high_cpu"`
    SoundOnCrash      bool              `json:"sound_on_crash"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:proc status                    # Show process status
/ccbell:proc add nginx                 # Add process to watch
/ccbell:proc remove nginx
/ccbell:proc memory 1024               # Set memory threshold
/ccbell:proc cpu 90                    # Set CPU threshold
/ccbell:proc sound high-mem <sound>
/ccbell:proc sound high-cpu <sound>
/ccbell:proc test                      # Test process sounds
```

### Output

```
$ ccbell:proc status

=== Sound Event Process Resource Monitor ===

Status: Enabled
Memory Threshold: 1024 MB
CPU Threshold: 90%
FD Threshold: 1024

Watched Processes: 4

Monitored Processes:

[1] nginx (PID: 1234)
    Memory: 256 MB
    CPU: 5%
    FDs: 128
    Restarts: 2
    Sound: bundled:proc-nginx

[2] postgres (PID: 5678)
    Memory: 2048 MB
    CPU: 15%
    FDs: 256
    Restarts: 0
    Sound: bundled:proc-postgres *** WARNING ***

[3] node (PID: 9012)
    Memory: 512 MB
    CPU: 85%
    FDs: 64
    Restarts: 1
    Sound: bundled:proc-node

[4] redis-server (PID: 3456)
    Memory: 128 MB
    CPU: 2%
    FDs: 32
    Restarts: 0
    Sound: bundled:proc-redis

Recent Events:
  [1] postgres: High Memory (5 min ago)
       2048 MB > 1024 MB threshold
  [2] node: High CPU (10 min ago)
       92% > 90% threshold
  [3] postgres: Memory Normalized (1 hour ago)
       Back to normal levels

Process Statistics:
  High Memory Alerts: 12
  High CPU Alerts: 8
  Crashes: 0

Sound Settings:
  High Memory: bundled:proc-high-mem
  High CPU: bundled:proc-high-cpu
  Crash: bundled:proc-crash

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds directly:
- Monitoring feature using ps/top/lsof
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
    processState    map[string]*ProcessInfo
    lastEventTime   map[string]time.Time
}

type ProcessInfo struct {
    Name       string
    PID        int
    MemoryMB   int
    CPU        float64
    FDs        int
    Status     string
    Restarts   int
    LastCheck  time.Time
}

func (m *ProcessResourceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processState = make(map[string]*ProcessInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ProcessResourceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkProcessResources()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ProcessResourceMonitor) checkProcessResources() {
    for _, procName := range m.config.WatchProcesses {
        pids := m.findProcessPIDs(procName)

        for _, pid := range pids {
            info := m.getProcessResourceInfo(pid, procName)
            if info == nil {
                // Process might have crashed
                m.onProcessCrashed(procName, pid)
                continue
            }

            lastInfo := m.processState[info.Name]
            if lastInfo == nil {
                m.processState[info.Name] = info
                continue
            }

            // Check thresholds
            m.checkMemoryThreshold(info, lastInfo)
            m.checkCPUThreshold(info, lastInfo)
            m.checkFDThreshold(info, lastInfo)

            m.processState[info.Name] = info
        }
    }
}

func (m *ProcessResourceMonitor) findProcessPIDs(name string) []int {
    var pids []int

    cmd := exec.Command("pgrep", "-x", name)
    output, err := cmd.Output()
    if err != nil {
        return pids
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        pid, _ := strconv.Atoi(line)
        pids = append(pids, pid)
    }

    return pids
}

func (m *ProcessResourceMonitor) getProcessResourceInfo(pid int, name string) *ProcessInfo {
    info := &ProcessInfo{
        Name:      name,
        PID:       pid,
        LastCheck: time.Now(),
    }

    // Get memory and CPU using ps
    cmd := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "pmem=,rss=,%cpu=")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    parts := strings.Fields(string(output))
    if len(parts) >= 3 {
        cpu, _ := strconv.ParseFloat(parts[0], 64)
        info.CPU = cpu

        rss, _ := strconv.ParseFloat(parts[1], 64)
        info.MemoryMB = int(rss / 1024) // Convert KB to MB
    }

    // Get file descriptor count
    fdCmd := exec.Command("ls", "/proc", strconv.Itoa(pid), "fd")
    fdOutput, _ := fdCmd.Output()
    info.FDs = len(strings.Split(string(fdOutput), "\n"))

    // Get process status
    statusCmd := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "state=")
    statusOutput, _ := statusCmd.Output()
    info.Status = strings.TrimSpace(string(statusOutput))

    return info
}

func (m *ProcessResourceMonitor) checkMemoryThreshold(info *ProcessInfo, lastInfo *ProcessInfo) {
    if info.MemoryMB >= m.config.MemoryThresholdMB {
        if lastInfo.MemoryMB < m.config.MemoryThresholdMB {
            if m.config.SoundOnHighMem {
                key := fmt.Sprintf("high_mem:%s", info.Name)
                if m.shouldAlert(key, 10*time.Minute) {
                    sound := m.config.Sounds["high_mem"]
                    if sound != "" {
                        m.player.Play(sound, 0.5)
                    }
                }
            }
        }
    }
}

func (m *ProcessResourceMonitor) checkCPUThreshold(info *ProcessInfo, lastInfo *ProcessInfo) {
    if info.CPU >= m.config.CPUThreshold {
        if lastInfo.CPU < m.config.CPUThreshold {
            if m.config.SoundOnHighCPU {
                key := fmt.Sprintf("high_cpu:%s", info.Name)
                if m.shouldAlert(key, 5*time.Minute) {
                    sound := m.config.Sounds["high_cpu"]
                    if sound != "" {
                        m.player.Play(sound, 0.5)
                    }
                }
            }
        }
    }
}

func (m *ProcessResourceMonitor) checkFDThreshold(info *ProcessInfo, lastInfo *ProcessInfo) {
    if info.FDs >= m.config.FDThreshold {
        key := fmt.Sprintf("high_fd:%s", info.Name)
        if m.shouldAlert(key, 15*time.Minute) {
            sound := m.config.Sounds["high_fd"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    }
}

func (m *ProcessResourceMonitor) onProcessCrashed(name string, pid int) {
    if !m.config.SoundOnCrash {
        return
    }

    lastInfo := m.processState[name]
    if lastInfo != nil {
        lastInfo.Restarts++
    }

    key := fmt.Sprintf("crash:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["crash"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }

    delete(m.processState, name)
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
| pgrep | System Tool | Free | Process listing |
| ps | System Tool | Free | Process status |
| ls | System Tool | Free | FD listing |

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
| macOS | Supported | Uses pgrep, ps |
| Linux | Supported | Uses pgrep, ps, /proc |
