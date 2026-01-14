# Feature: Sound Event Process Monitor

Play sounds when processes start or stop.

## Summary

Play different sounds based on process state changes.

## Motivation

- Build completion
- Server start/stop
- Background task alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Process Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Started | Process started | npm start |
| Stopped | Process stopped | Server died |
| Completed | Process finished | Build done |
| High CPU | CPU spike detected | Compilation |
| Memory High | Memory threshold | Memory leak |

### Configuration

```go
type ProcessMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 5 default
    Triggers      []*ProcessTrigger `json:"triggers"`
}

type ProcessTrigger struct {
    ID          string  `json:"id"`
    Name        string  `json:"name"` // Process name or pattern
    ExactMatch  bool    `json:"exact_match"`
    Type        string  `json:"type"` // "started", "stopped", "completed", "cpu_high", "memory_high"
    CPUThreshold float64 `json:"cpu_threshold,omitempty"` // 0-100
    MemoryThreshold int `json:"memory_threshold_mb,omitempty"` // MB
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume,omitempty"`
    Enabled     bool    `json:"enabled"`
}

type ProcessState struct {
    PID         int
    Name        string
    CPU         float64
    Memory      int // MB
    Status      string // "running", "sleeping", "zombie"
    StartTime   time.Time
}
```

### Commands

```bash
/ccbell:process list                # List monitored processes
/ccbell:process add "npm" --sound bundled:stop
/ccbell:process add "server" --started <sound> --stopped <sound>
/ccbell:process add "build" --completed <sound>
/ccbell:process add "cpu_hog" --cpu_threshold 80
/ccbell:process remove <id>         # Remove monitor
/ccbell:process status              # Show process status
/ccbell:process test                # Test process sounds
```

### Output

```
$ ccbell:process status

=== Sound Event Process Monitor ===

Status: Enabled
Check Interval: 5s

Monitored Processes: 4

[1] npm
    PID: 12345
    Status: Running
    CPU: 5%
    Memory: 45MB
    Sound: bundled:stop
    [Edit] [Disable] [Delete]

[2] server
    PID: 12350
    Status: Running
    CPU: 12%
    Memory: 120MB
    Started Sound: bundled:stop
    Stopped Sound: bundled:stop
    [Edit] [Disable] [Delete]

[3] build
    PID: -
    Status: Not Running
    Last Run: 2 hours ago
    Completed Sound: bundled:stop
    [Edit] [Disable] [Delete]

[4] cpu_hog
    Pattern: *
    CPU Threshold: 80%
    Last Triggered: 5 min ago
    Sound: bundled:stop
    [Edit] [Disable] [Delete]

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Process monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Process Monitor

```go
type ProcessMonitor struct {
    config   *ProcessMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastState map[string]*ProcessState
    mutex    sync.Mutex
}

func (m *ProcessMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastState = make(map[string]*ProcessState)
    go m.monitor()
}

func (m *ProcessMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
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
    processes, err := m.getProcesses()
    if err != nil {
        log.Debug("Failed to get processes: %v", err)
        return
    }

    currentState := make(map[string]*ProcessState)
    for _, p := range processes {
        currentState[p.Name] = p
    }

    for _, trigger := range m.config.Triggers {
        if !trigger.Enabled {
            continue
        }

        m.checkTrigger(trigger, currentState, m.lastState)
    }

    m.lastState = currentState
}

func (m *ProcessMonitor) getProcesses() ([]*ProcessState, error) {
    // macOS: ps aux
    cmd := exec.Command("ps", "aux")
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    var processes []*ProcessState
    lines := strings.Split(string(output), "\n")[1:] // Skip header

    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 11 {
            continue
        }

        cpu, _ := strconv.ParseFloat(parts[2], 64)
        mem, _ := strconv.ParseFloat(parts[3], 64)
        pid, _ := strconv.Atoi(parts[1])

        processes = append(processes, &ProcessState{
            PID:    pid,
            Name:   parts[10],
            CPU:    cpu,
            Memory: int(mem),
            Status: parts[7],
        })
    }

    return processes, nil
}

func (m *ProcessMonitor) checkTrigger(trigger *ProcessTrigger, current, last map[string]*ProcessState) {
    for _, p := range current {
        if !m.matchesProcess(trigger, p.Name) {
            continue
        }

        lastP := last[p.Name]

        // Process started
        if trigger.Type == "started" && lastP == nil {
            m.playProcessEvent(trigger, "started")
        }

        // Process stopped
        if trigger.Type == "stopped" && lastP != nil && p.Status == "" {
            m.playProcessEvent(trigger, "stopped")
        }

        // CPU high
        if trigger.Type == "cpu_high" && p.CPU >= trigger.CPUThreshold {
            if lastP == nil || lastP.CPU < trigger.CPUThreshold {
                m.playProcessEvent(trigger, "cpu_high")
            }
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | System Tool | Free | Process list |
| top | System Tool | Free | Process monitoring |
| lsof | System Tool | Free | Open files/processes |

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
| macOS | ✅ Supported | Uses ps/top |
| Linux | ✅ Supported | Uses ps/top |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
