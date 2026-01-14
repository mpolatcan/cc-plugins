# Feature: Sound Event Process Scheduling Monitor

Play sounds for process scheduling priority changes and CPU affinity modifications.

## Summary

Monitor process scheduling changes including nice values, RT priority, and CPU affinity, playing sounds for scheduling events.

## Motivation

- Priority change awareness
- Resource contention detection
- Performance tuning feedback
- Security monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Process Scheduling Events

| Event | Description | Example |
|-------|-------------|---------|
| Priority Changed | Nice value modified | nice -10 |
| RT Priority Set | Real-time priority set | chrt -f 99 |
| CPU Affinity Changed | CPU mask modified | taskset -c 0,1 |
| OOM Score Adjusted | OOM killer priority | /proc/pid/oom_score_adj |

### Configuration

```go
type ProcessSchedulingMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WatchProcesses      []string          `json:"watch_processes"]
    WatchPriorityChange bool              `json:"sound_on_priority_change"]
    WatchAffinityChange bool              `json:"sound_on_affinity_change"]
    WatchOOMScore       bool              `json:"sound_on_oom_score"]
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 30 default
}

type ProcessSchedulingEvent struct {
    ProcessName string
    PID         int
    OldNice     int
    NewNice     int
    OldAffinity string
    NewAffinity string
    OOMScore    int
    EventType   string // "priority", "affinity", "oom_score"
}
```

### Commands

```bash
/ccbell:sched status                  # Show scheduling status
/ccbell:sched add nginx               # Add process to watch
/ccbell:sched remove nginx
/ccbell:sched sound priority <sound>
/ccbell:sched sound affinity <sound>
/ccbell:sched test                    # Test scheduling sounds
```

### Output

```
$ ccbell:sched status

=== Sound Event Process Scheduling Monitor ===

Status: Enabled
Priority Sounds: Yes
Affinity Sounds: Yes

Watched Processes: 3

[1] nginx (PID: 1234)
    Nice: -10 (was 0)
    CPU Affinity: 0-3
    RT Priority: --
    Sound: bundled:sched-priority

[2] postgres (PID: 5678)
    Nice: 0
    CPU Affinity: 0-7
    RT Priority: --
    Sound: bundled:stop

[3] audio (PID: 9012)
    Nice: -20
    CPU Affinity: 0
    RT Priority: 80
    Sound: bundled:stop

Recent Events:
  [1] nginx: Priority Changed (5 min ago)
       Nice: 0 -> -10
  [2] audio: CPU Affinity Changed (1 hour ago)
       Affinity: 0-7 -> 0
  [3] postgres: Priority Changed (2 hours ago)
       Nice: 10 -> 0

Scheduling Statistics:
  Priority changes/hour: 5
  Affinity changes/hour: 2

Sound Settings:
  Priority: bundled:sched-priority
  Affinity: bundled:stop
  OOM Score: bundled:stop

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process scheduling monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Scheduling Monitor

```go
type ProcessSchedulingMonitor struct {
    config                 *ProcessSchedulingMonitorConfig
    player                 *audio.Player
    running                bool
    stopCh                 chan struct{}
    processSchedulingInfo  map[int]*SchedulingInfo
    lastEventTime          map[string]time.Time
}

type SchedulingInfo struct {
    PID           int
    ProcessName   string
    Nice          int
    RTPriority    int
    CPUAffinity   string
    OOMScore      int
}

func (m *ProcessSchedulingMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processSchedulingInfo = make(map[int]*SchedulingInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ProcessSchedulingMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSchedulingInfo()

    for {
        select {
        case <-ticker.C:
            m.checkSchedulingChanges()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ProcessSchedulingMonitor) snapshotSchedulingInfo() {
    // Get list of processes to watch
    pids := m.getWatchedPIDs()
    for _, pid := range pids {
        m.getProcessSchedulingInfo(pid)
    }
}

func (m *ProcessSchedulingMonitor) getWatchedPIDs() []int {
    var pids []int

    if len(m.config.WatchProcesses) == 0 {
        return pids
    }

    for _, name := range m.config.WatchProcesses {
        cmd := exec.Command("pgrep", "-x", name)
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        for _, line := range strings.Split(string(output), "\n") {
            if line == "" {
                continue
            }
            pid, err := strconv.Atoi(line)
            if err == nil {
                pids = append(pids, pid)
            }
        }
    }

    return pids
}

func (m *ProcessSchedulingMonitor) getProcessSchedulingInfo(pid int) *SchedulingInfo {
    // Get process name from /proc/pid/status
    statusFile := filepath.Join("/proc", strconv.Itoa(pid), "status")
    data, err := os.ReadFile(statusFile)
    if err != nil {
        return nil
    }

    processName := m.extractProcessName(string(data))

    // Get nice value
    nice := m.getProcessNice(pid)

    // Get CPU affinity
    affinity := m.getCPUAffinity(pid)

    // Get OOM score
    oomScore := m.getOOMScore(pid)

    return &SchedulingInfo{
        PID:           pid,
        ProcessName:   processName,
        Nice:          nice,
        CPUAffinity:   affinity,
        OOMScore:      oomScore,
    }
}

func (m *ProcessSchedulingMonitor) checkSchedulingChanges() {
    pids := m.getWatchedPIDs()
    for _, pid := range pids {
        info := m.getProcessSchedulingInfo(pid)
        if info == nil {
            continue
        }

        lastInfo := m.processSchedulingInfo[pid]
        if lastInfo == nil {
            m.processSchedulingInfo[pid] = info
            continue
        }

        // Check for nice value change
        if info.Nice != lastInfo.Nice {
            m.onPriorityChange(info, lastInfo)
        }

        // Check for CPU affinity change
        if info.CPUAffinity != lastInfo.CPUAffinity {
            m.onAffinityChange(info, lastInfo)
        }

        // Check for OOM score change
        if info.OOMScore != lastInfo.OOMScore {
            m.onOOMScoreChange(info, lastInfo)
        }

        m.processSchedulingInfo[pid] = info
    }
}

func (m *ProcessSchedulingMonitor) getProcessNice(pid int) int {
    cmd := exec.Command("ps", "-o", "nice=", "-p", strconv.Itoa(pid))
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    nice, _ := strconv.Atoi(strings.TrimSpace(string(output)))
    return nice
}

func (m *ProcessSchedulingMonitor) getCPUAffinity(pid int) string {
    affinityFile := filepath.Join("/proc", strconv.Itoa(pid), "status")
    data, err := os.ReadFile(affinityFile)
    if err != nil {
        return ""
    }

    // Parse Cpus_allowed field
    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Cpus_allowed_list:") {
            parts := strings.Split(line, ":")
            if len(parts) >= 2 {
                return strings.TrimSpace(parts[1])
            }
        }
    }

    return ""
}

func (m *ProcessSchedulingMonitor) getOOMScore(pid int) int {
    scoreFile := filepath.Join("/proc", strconv.Itoa(pid), "oom_score")
    data, err := os.ReadFile(scoreFile)
    if err != nil {
        return 0
    }

    score, _ := strconv.Atoi(strings.TrimSpace(string(data)))
    return score
}

func (m *ProcessSchedulingMonitor) extractProcessName(statusData string) string {
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

func (m *ProcessSchedulingMonitor) onPriorityChange(current *SchedulingInfo, last *SchedulingInfo) {
    if !m.config.WatchPriorityChange {
        return
    }

    key := fmt.Sprintf("priority:%d", current.PID)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["priority"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ProcessSchedulingMonitor) onAffinityChange(current *SchedulingInfo, last *SchedulingInfo) {
    if !m.config.WatchAffinityChange {
        return
    }

    key := fmt.Sprintf("affinity:%d", current.PID)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["affinity"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ProcessSchedulingMonitor) onOOMScoreChange(current *SchedulingInfo, last *SchedulingInfo) {
    if !m.config.WatchOOMScore {
        return
    }

    key := fmt.Sprintf("oom:%d", current.PID)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["oom_score"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ProcessSchedulingMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| pgrep | System Tool | Free | Find processes |
| ps | System Tool | Free | Process status |
| /proc/*/status | File | Free | Process info |

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
| macOS | Supported | Uses ps, pgrep |
| Linux | Supported | Uses /proc/*/status |
| Windows | Not Supported | ccbell only supports macOS/Linux |
