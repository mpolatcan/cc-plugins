# Feature: Sound Event Terminal Monitor

Play sounds for terminal activity and command execution.

## Summary

Monitor terminal sessions, command execution, and shell activity, playing sounds for terminal events.

## Motivation

- Command completion feedback
- Long-running task alerts
- Error detection
- Terminal focus awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Terminal Events

| Event | Description | Example |
|-------|-------------|---------|
| Command Started | Command execution began | make build |
| Command Finished | Command completed | Exit code 0 |
| Command Failed | Command errored | Exit code > 0 |
| Long Command | Long-running command | > 1 min |
| Terminal Focus | Terminal gained focus | Clicked on iTerm |
| Background Task | Background job started | & job |

### Configuration

```go
type TerminalMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchShells      []string          `json:"watch_shells"` // "bash", "zsh", "fish"
    SoundOnCommand   bool              `json:"sound_on_command"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    LongThreshold    time.Duration     `json:"long_threshold"` // 1 min default
    ExcludeCommands  []string          `json:"exclude_commands"` // Commands to skip
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type TerminalEvent struct {
    Shell    string
    Command  string
    EventType string // "started", "finished", "failed", "long_running"
    ExitCode int
    Duration time.Duration
}
```

### Commands

```bash
/ccbell:terminal status           # Show terminal status
/ccbell:terminal add zsh          # Add shell to watch
/ccbell:terminal sound command <sound>
/ccbell:terminal sound failed <sound>
/ccbell:terminal test             # Test terminal sounds
```

### Output

```
$ ccbell:terminal status

=== Sound Event Terminal Monitor ===

Status: Enabled
Command Sounds: Yes
Fail Sounds: Yes

Active Shells: 3

[1] zsh (iTerm2)
    Current Command: git status
    Running for: 5 sec
    Sound: bundled:stop

[2] bash (Terminal)
    Idle
    Last Command: make build (completed)
    Duration: 2 min
    Sound: bundled:stop

[3] fish (Alacritty)
    Current Command: docker-compose up
    Running for: 45 min (Long Running!)
    Sound: bundled:stop

Watched Shells: 3
  zsh, bash, fish

Recent Events:
  [1] bash: make build completed (2 min ago)
  [2] fish: docker-compose up started (45 min ago)
  [3] zsh: git push failed (1 hour ago)

Sound Settings:
  Command Complete: bundled:stop
  Command Failed: bundled:stop
  Long Running: bundled:stop

[Configure] [Add Shell] [Test All]
```

---

## Audio Player Compatibility

Terminal monitoring doesn't play sounds directly:
- Monitoring feature using process and job control
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Terminal Monitor

```go
type TerminalMonitor struct {
    config        *TerminalMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    activeJobs    map[string]time.Time
    lastCommands  map[string]string
}

func (m *TerminalMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeJobs = make(map[string]time.Time)
    m.lastCommands = make(map[string]string)
    go m.monitor()
}

func (m *TerminalMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkTerminals()
        case <-m.stopCh:
            return
        }
    }
}

func (m *TerminalMonitor) checkTerminals() {
    jobs := m.getActiveJobs()

    for job, startTime := range jobs {
        lastStart := m.activeJobs[job]

        if lastStart.IsZero() {
            // New job
            m.activeJobs[job] = startTime
            m.onCommandStarted(job)
        }

        // Check for long-running jobs
        if time.Since(startTime) > m.config.LongThreshold {
            m.onLongRunning(job)
        }
    }

    // Check for completed jobs
    for job := range m.activeJobs {
        if _, exists := jobs[job]; !exists {
            delete(m.activeJobs, job)
            m.onCommandFinished(job)
        }
    }
}

func (m *TerminalMonitor) getActiveJobs() map[string]time.Time {
    jobs := make(map[string]time.Time)

    // Check for running processes in common shells
    for _, shell := range m.config.WatchShells {
        shellJobs := m.getShellJobs(shell)
        for job, startTime := range shellJobs {
            jobs[job] = startTime
        }
    }

    return jobs
}

func (m *TerminalMonitor) getShellJobs(shell string) map[string]time.Time {
    jobs := make(map[string]time.Time)

    // Get processes for this shell
    cmd := exec.Command("ps", "-x", "-o", "pid=,ppid=,comm=")
    output, err := cmd.Output()
    if err != nil {
        return jobs
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        pid := parts[0]
        ppid := parts[1]
        comm := parts[2]

        // Check if it's the shell or a child of the shell
        if comm == shell || m.isChildOfShell(ppid, shell) {
            if !m.shouldExclude(comm) {
                // Get process start time
                startTime := m.getProcessStartTime(pid)
                jobs[shell+":"+pid] = startTime
            }
        }
    }

    return jobs
}

func (m *TerminalMonitor) isChildOfShell(ppid, shell string) bool {
    // Check if the parent process is a shell
    cmd := exec.Command("ps", "-p", ppid, "-o", "comm=")
    output, err := cmd.Output()
    if err != nil {
        return false
    }

    parentComm := strings.TrimSpace(string(output))
    return parentComm == shell || parentComm == "bash" || parentComm == "zsh" ||
           parentComm == "fish" || parentComm == "sh"
}

func (m *TerminalMonitor) getProcessStartTime(pid string) time.Time {
    cmd := exec.Command("ps", "-p", pid, "-o", "lstart=")
    output, err := cmd.Output()
    if err != nil {
        return time.Now()
    }

    startStr := strings.TrimSpace(string(output))
    startTime, err := time.Parse("Mon Jan 2 15:04:05 2006", startStr)
    if err != nil {
        return time.Now()
    }

    return startTime
}

func (m *TerminalMonitor) shouldExclude(command string) bool {
    for _, excluded := range m.config.ExcludeCommands {
        if strings.Contains(command, excluded) {
            return true
        }
    }
    return false
}

func (m *TerminalMonitor) onCommandStarted(job string) {
    if !m.config.SoundOnCommand {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *TerminalMonitor) onCommandFinished(job string) {
    sound := m.config.Sounds["finished"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *TerminalMonitor) onCommandFailed(job string) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *TerminalMonitor) onLongRunning(job string) {
    sound := m.config.Sounds["long_running"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ps | procps | Free | Process listing |
| shell | System Tool | Free | Shell execution |

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
