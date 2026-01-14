# Feature: Sound Event Process Exit Monitor

Play sounds for process exit events and termination reasons.

## Summary

Monitor process exits, crashes, and termination events, playing sounds for significant process terminations.

## Motivation

- Process crash alerts
- Exit code feedback
- Service failure detection
- Resource cleanup awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Process Exit Events

| Event | Description | Example |
|-------|-------------|---------|
| Process Exited | Normal exit | Exit 0 |
| Process Crashed | Abnormal exit | Exit 134 (SIGABRT) |
| Process Killed | Signal killed | SIGKILL |
| OOM Killed | Memory limit | Exit 137 (SIGKILL) |
| Core Dumped | Core file created | Crash with core |

### Configuration

```go
type ProcessExitMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchProcesses  []string          `json:"watch_processes"` // Process names
    WatchExitCodes  []int             `json:"watch_exit_codes"` // Exit codes to watch
    SoundOnExit     bool              `json:"sound_on_exit"]
    SoundOnCrash    bool              `json:"sound_on_crash"]
    SoundOnKilled   bool              `json:"sound_on_killed"]
    SoundOnOOM      bool              `json:"sound_on_oom"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 5 default
}

type ProcessExitEvent struct {
    ProcessName string
    PID         int
    ExitCode    int
    Signal      string
    Reason      string // "exited", "crashed", "killed", "oom"
    Duration    time.Duration
}
```

### Commands

```bash
/ccbell:exit status                   # Show exit monitor status
/ccbell:exit add "nginx"              # Add process to watch
/ccbell:exit remove "nginx"
/ccbell:exit sound crash <sound>
/ccbell:exit sound oom <sound>
/ccbell:exit test                     # Test exit sounds
```

### Output

```
$ ccbell:exit status

=== Sound Event Process Exit Monitor ===

Status: Enabled
Crash Sounds: Yes
OOM Sounds: Yes

Watched Processes: 3

[1] nginx
    Last Exit: 2 hours ago
    Exit Code: 0 (Normal)
    Uptime: 5 days
    Sound: bundled:stop

[2] postgres
    Last Exit: 5 days ago
    Exit Code: 1 (Error)
    Uptime: 30 days
    Sound: bundled:stop

[3] worker
    Last Exit: 30 min ago
    Exit Code: 137 (OOM Killed)
    Uptime: 2 hours
    Reason: Memory exceeded
    Sound: bundled:exit-oom

Recent Exits:

[1] worker: OOM Killed (30 min ago)
       Exit code: 137 (SIGKILL)
       Memory: 512MB limit, used 518MB
       Duration: 2 hours

[2] nginx: Exited (2 hours ago)
       Exit code: 0 (Normal)
       Duration: 5 days

[3] postgres: Error (3 hours ago)
       Exit code: 1
       Error: Connection refused
       Duration: 30 days

Statistics Today:
  Normal Exits: 5
  Crashes: 1
  OOM Kills: 1
  Other: 2

Sound Settings:
  Crash: bundled:stop
  OOM: bundled:stop
  Killed: bundled:stop

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Process exit monitoring doesn't play sounds directly:
- Monitoring feature using process tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Process Exit Monitor

```go
type ProcessExitMonitor struct {
    config           *ProcessExitMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    activeProcesses  map[int]*ProcessInfo
    exitedProcesses  []*ProcessExitEvent
}

type ProcessInfo struct {
    PID        int
    Name       string
    StartTime  time.Time
}
```

```go
func (m *ProcessExitMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeProcesses = make(map[int]*ProcessInfo)
    m.exitedProcesses = make([]*ProcessExitEvent, 0)
    go m.monitor()
}

func (m *ProcessExitMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial process scan
    m.scanProcesses()

    for {
        select {
        case <-ticker.C:
            m.checkProcessExits()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ProcessExitMonitor) scanProcesses() {
    cmd := exec.Command("ps", "-eo", "pid,comm,etime")
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
        if !m.shouldWatchProcess(info.Name) {
            continue
        }

        m.activeProcesses[info.PID] = info
    }
}

func (m *ProcessExitMonitor) checkProcessExits() {
    // Re-scan processes
    currentPIDs := make(map[int]bool)

    cmd := exec.Command("ps", "-eo", "pid,comm,etime")
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
        if !m.shouldWatchProcess(info.Name) {
            continue
        }

        currentPIDs[info.PID] = true
        m.activeProcesses[info.PID] = info
    }

    // Check for exited processes
    for pid, info := range m.activeProcesses {
        if !currentPIDs[pid] {
            // Process has exited
            delete(m.activeProcesses, pid)
            m.onProcessExited(pid, info)
        }
    }
}

func (m *ProcessExitMonitor) parsePSLine(line string) *ProcessInfo {
    parts := strings.Fields(line)
    if len(parts) < 3 {
        return nil
    }

    pid, err := strconv.Atoi(parts[0])
    if err != nil {
        return nil
    }

    name := parts[1]
    elapsed := m.parseElapsedTime(parts[2])

    return &ProcessInfo{
        PID:       pid,
        Name:      name,
        StartTime: time.Now().Add(-elapsed),
    }
}

func (m *ProcessExitMonitor) parseElapsedTime(etime string) time.Duration {
    // Parse elapsed time format
    parts := strings.Split(etime, "-")
    var duration time.Duration

    if len(parts) == 2 {
        // "dd-hh:mm:ss"
        if days, err := strconv.Atoi(parts[0]); err == nil {
            duration += time.Duration(days) * 24 * time.Hour
        }
        etime = parts[1]
    }

    timeParts := strings.Split(etime, ":")
    if len(timeParts) == 3 {
        if h, err := strconv.Atoi(timeParts[0]); err == nil {
            duration += time.Duration(h) * time.Hour
        }
        if m, err := strconv.Atoi(timeParts[1]); err == nil {
            duration += time.Duration(m) * time.Minute
        }
        if s, err := strconv.Atoi(timeParts[2]); err == nil {
            duration += time.Duration(s) * time.Second
        }
    }

    return duration
}

func (m *ProcessExitMonitor) shouldWatchProcess(name string) bool {
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

func (m *ProcessExitMonitor) onProcessExited(pid int, info *ProcessInfo) {
    // Get exit information from system log or accounting
    exitEvent := m.getExitInfo(info)

    // Determine reason based on exit code
    reason := m.determineExitReason(exitEvent.ExitCode)
    exitEvent.Reason = reason
    exitEvent.ProcessName = info.Name
    exitEvent.Duration = time.Since(info.StartTime)

    m.exitedProcesses = append(m.exitedProcesses, exitEvent)

    // Keep only recent exits
    if len(m.exitedProcesses) > 100 {
        m.exitedProcesses = m.exitedProcesses[len(m.exitedProcesses)-100:]
    }

    // Play appropriate sound
    m.playExitSound(exitEvent)
}

func (m *ProcessExitMonitor) getExitInfo(info *ProcessInfo) *ProcessExitEvent {
    event := &ProcessExitEvent{
        PID:         info.PID,
        ExitCode:    0,
    }

    // Try to get exit code from wait status (limited from Go)
    // In practice, this would need to be captured from process.Wait

    return event
}

func (m *ProcessExitMonitor) determineExitReason(exitCode int) string {
    switch exitCode {
    case 0:
        return "exited"
    case 137:
        return "oom"
    case 139:
        return "crashed" // SIGSEGV
    case 134:
        return "crashed" // SIGABRT
    case 143:
        return "killed" // SIGTERM
    default:
        if exitCode > 128 {
            // Exit code - 128 = signal number
            signalNum := exitCode - 128
            switch signalNum {
            case 9:
                return "killed" // SIGKILL
            case 15:
                return "killed" // SIGTERM
            default:
                return "killed"
            }
        }
        return "exited"
    }
}

func (m *ProcessExitMonitor) playExitSound(event *ProcessExitEvent) {
    switch event.Reason {
    case "exited":
        if m.config.SoundOnExit {
            sound := m.config.Sounds["exited"]
            if sound != "" {
                m.player.Play(sound, 0.4)
            }
        }
    case "crashed":
        if m.config.SoundOnCrash {
            sound := m.config.Sounds["crashed"]
            if sound != "" {
                m.player.Play(sound, 0.6)
            }
        }
    case "killed":
        if m.config.SoundOnKilled {
            sound := m.config.Sounds["killed"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    case "oom":
        if m.config.SoundOnOOM {
            sound := m.config.Sounds["oom"]
            if sound != "" {
                m.player.Play(sound, 0.7)
            }
        }
    }
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
