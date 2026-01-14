# Feature: Sound Event OOM Killer Monitor

Play sounds for OOM killer invocation and memory pressure events.

## Summary

Monitor OOM killer events, process terminations, and memory pressure, playing sounds for OOM events.

## Motivation

- OOM detection
- Process termination alerts
- Memory pressure awareness
- Stability monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### OOM Killer Events

| Event | Description | Example |
|-------|-------------|---------|
| OOM Invoked | OOM killer triggered | chrome killed |
| OOM Score | Process marked for kill | oom_score_adj |
| Memory Critical | Critical memory pressure | < 5% free |
| Process Killed | Process terminated by OOM | Exit code 137 |

### Configuration

```go
type OOMKillerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchProcesses    []string          `json:"watch_processes"] // "chrome", "postgres"
    SoundOnKill       bool              `json:"sound_on_kill"]
    SoundOnScore      bool              `json:"sound_on_score"]
    SoundOnPressure   bool              `json:"sound_on_pressure"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type OOMKillerEvent struct {
    ProcessName string
    PID         int
    OOMScore    int
    MemoryUsed  int64
    EventType   string // "kill", "score", "pressure"
}
```

### Commands

```bash
/ccbell:oom status                    # Show OOM monitor status
/ccbell:oom add chrome                # Add process to watch
/ccbell:oom remove chrome
/ccbell:oom sound kill <sound>
/ccbell:oom sound score <sound>
/ccbell:oom test                      # Test OOM sounds
```

### Output

```
$ ccbell:oom status

=== Sound Event OOM Killer Monitor ===

Status: Enabled
Kill Sounds: Yes
Score Sounds: Yes

Watched Processes: 2

[1] chrome (PID: 1234)
    OOM Score: 500
    Memory: 4 GB
    Status: AT RISK
    Sound: bundled:oom-score

[2] postgres (PID: 5678)
    OOM Score: 100
    Memory: 2 GB
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] chrome: OOM Score High (5 min ago)
       Score: 500
  [2] java: OOM Killed (10 min ago)
       PID: 9012, Memory: 1 GB
  [3] node: Memory Critical (1 hour ago)
       System at 2% free memory

OOM Statistics:
  Processes killed: 5
  High score alerts: 10

Sound Settings:
  Kill: bundled:oom-kill
  Score: bundled:oom-score
  Pressure: bundled:oom-pressure

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

OOM killer monitoring doesn't play sounds directly:
- Monitoring feature using system logs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### OOM Killer Monitor

```go
type OOMKillerMonitor struct {
    config          *OOMKillerMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    processOOMScore map[int]int
    lastEventTime   map[string]time.Time
}

func (m *OOMKillerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processOOMScore = make(map[int]int)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *OOMKillerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotOOMState()

    for {
        select {
        case <-ticker.C:
            m.checkOOMEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *OOMKillerMonitor) snapshotOOMState() {
    // Check kernel logs for OOM events
    m.checkOOMEvents()
}

func (m *OOMKillerMonitor) checkOOMEvents() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinOOM()
    } else {
        m.checkLinuxOOM()
    }
}

func (m *OOMKillerMonitor) checkDarwinOOM() {
    // Check system log for memory pressure warnings
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'kernel' && eventMessage CONTAINS 'memory'",
        "--last", "10m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLogOutput(string(output))
}

func (m *OOMKillerMonitor) checkLinuxOOM() {
    // Check kernel logs for OOM events
    m.checkKernelOOM()

    // Check for new OOM score changes
    m.checkOOMScores()
}

func (m *OOMKillerMonitor) checkKernelOOM() {
    // Read from /var/log or use journalctl
    var logData []byte
    var err error

    // Try journalctl first (systemd)
    cmd := exec.Command("journalctl", "-k", "--since", "10 minutes ago", "--no-pager")
    logData, err = cmd.Output()
    if err != nil {
        // Fallback to dmesg
        cmd = exec.Command("dmesg")
        logData, err = cmd.Output()
        if err != nil {
            return
        }
    }

    m.parseKernelLog(string(logData))
}

func (m *OOMKillerMonitor) checkOOMScores() {
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

        // Read oom_score
        scoreFile := filepath.Join("/proc", entry.Name(), "oom_score")
        data, err := os.ReadFile(scoreFile)
        if err != nil {
            continue
        }

        score, _ := strconv.Atoi(strings.TrimSpace(string(data)))

        // Get process name
        statusFile := filepath.Join("/proc", entry.Name(), "status")
        statusData, _ := os.ReadFile(statusFile)
        processName := m.extractProcessName(string(statusData))

        if m.shouldWatchProcess(processName) {
            m.evaluateOOMScore(pid, processName, score)
        }
    }
}

func (m *OOMKillerMonitor) parseKernelLog(log string) {
    lines := strings.Split(log, "\n")
    recentTime := time.Now().Add(-10 * time.Minute)

    for _, line := range lines {
        if !strings.Contains(strings.ToLower(line), "oom") {
            continue
        }

        if strings.Contains(strings.ToLower(line), "killed process") ||
           strings.Contains(strings.ToLower(line), "out of memory") ||
           strings.Contains(strings.ToLower(line), "oom-killer") {

            event := m.parseOOMEvent(line)
            if event != nil {
                m.onProcessKilled(event)
            }
        }
    }
}

func (m *OOMKillerMonitor) parseLogOutput(log string) {
    lines := strings.Split(log, "\n")
    for _, line := range lines {
        if strings.Contains(strings.ToLower(line), "memory pressure") {
            m.onMemoryPressure()
        }
    }
}

func (m *OOMKillerMonitor) parseOOMEvent(line string) *OOMKillerEvent {
    event := &OOMKillerEvent{}

    // Parse: "Out of memory: Kill process 1234 (chrome) score 500 or sacrifice child"
    re := regexp.MustCompile(`Kill process (\d+) \(([^)]+)\)`)
    if match := re.FindStringSubmatch(line); match != nil {
        pid, _ := strconv.Atoi(match[1])
        event.PID = pid
        event.ProcessName = match[2]
        event.EventType = "kill"
    }

    return event
}

func (m *OOMKillerMonitor) evaluateOOMScore(pid int, processName string, score int) {
    lastScore := m.processOOMScore[pid]

    if lastScore == 0 {
        m.processOOMScore[pid] = score
        return
    }

    // Check if score increased significantly
    if score > 500 && lastScore < 500 {
        m.onHighOOMScore(processName, pid, score)
    }

    m.processOOMScore[pid] = score
}

func (m *OOMKillerMonitor) extractProcessName(statusData string) string {
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

func (m *OOMKillerMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, process := range m.config.WatchProcesses {
        if name == process {
            return true
        }
    }

    return false
}

func (m *OOMKillerMonitor) onProcessKilled(event *OOMKillerEvent) {
    if !m.config.SoundOnKill {
        return
    }

    if !m.shouldWatchProcess(event.ProcessName) {
        return
    }

    key := fmt.Sprintf("kill:%s:%d", event.ProcessName, event.PID)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["kill"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *OOMKillerMonitor) onHighOOMScore(processName string, pid int, score int) {
    if !m.config.SoundOnScore {
        return
    }

    if !m.shouldWatchProcess(processName) {
        return
    }

    key := fmt.Sprintf("score:%s:%d", processName, pid)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["score"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *OOMKillerMonitor) onMemoryPressure() {
    if !m.config.SoundOnPressure {
        return
    }

    key := "pressure"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["pressure"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *OOMKillerMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| journalctl | System Tool | Free | Linux journal |
| dmesg | System Tool | Free | Kernel messages |
| log | System Tool | Free | macOS logging |

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
| macOS | Supported | Uses log command |
| Linux | Supported | Uses journalctl, dmesg |
| Windows | Not Supported | ccbell only supports macOS/Linux |
