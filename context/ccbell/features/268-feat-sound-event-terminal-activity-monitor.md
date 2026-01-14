# Feature: Sound Event Terminal Activity Monitor

Play sounds for terminal activity and command execution.

## Summary

Monitor terminal sessions, command executions, and shell activity, playing sounds for terminal events.

## Motivation

- Command completion feedback
- Long-running task alerts
- Terminal session awareness
- Build completion notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Terminal Events

| Event | Description | Example |
|-------|-------------|---------|
| Command Started | New command | npm install |
| Command Complete | Command finished | Exit 0 |
| Command Failed | Command errored | Exit 1 |
| Long Running | Task > 5 min | make build |
| Background Job | Job completed | bg job done |

### Configuration

```go
type TerminalActivityMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchUsers         []string          `json:"watch_users"`
    WatchCommands      []string          `json:"watch_commands"` // Commands to watch
    LongRunThreshold   int               `json:"long_run_threshold_sec"` // 300 default
    SoundOnStart       bool              `json:"sound_on_start"`
    SoundOnComplete    bool              `json:"sound_on_complete"`
    SoundOnFail        bool              `json:"sound_on_fail"`
    SoundOnLongRun     bool              `json:"sound_on_long_run"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 5 default
}

type TerminalEvent struct {
    UserName   string
    Command    string
    PID        int
    TTY        string
    Duration   time.Duration
    ExitCode   int
    EventType  string // "start", "complete", "fail", "long_run"
}
```

### Commands

```bash
/ccbell:terminal status              # Show terminal status
/ccbell:terminal add "npm install"   # Add command to watch
/ccbell:terminal remove "npm install"
/ccbell:terminal sound complete <sound>
/ccbell:terminal sound fail <sound>
/ccbell:terminal test                # Test terminal sounds
```

### Output

```
$ ccbell:terminal status

=== Sound Event Terminal Activity Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes

Current Active Sessions: 3

[1] user@localhost (pts/0)
    Command: vim README.md
    Running: 5 min
    Sound: bundled:stop

[2] user@localhost (pts/1)
    Command: npm install
    Running: 2 min
    Status: Running
    Sound: bundled:stop

[3] user@localhost (pts/2)
    Command: sleep 3600
    Running: 1 hour
    Status: Background
    Sound: bundled:stop

Recent Events:
  [1] npm install: Complete (5 min ago)
       Exit code: 0
       Duration: 2 min
  [2] vim README.md: Long Running (started 5 min ago)
  [3] make build: Failed (1 hour ago)
       Exit code: 2

Watched Commands:
  - npm install
  - make build
  - docker compose

Sound Settings:
  Complete: bundled:stop
  Failed: bundled:stop
  Long Running: bundled:stop

[Configure] [Add Command] [Test All]
```

---

## Audio Player Compatibility

Terminal activity monitoring doesn't play sounds directly:
- Monitoring feature using process tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Terminal Activity Monitor

```go
type TerminalActivityMonitor struct {
    config         *TerminalActivityMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    activeCommands map[int]*CommandInfo
    commandHistory []*CommandInfo
}

type CommandInfo struct {
    PID        int
    UserName   string
    Command    string
    TTY        string
    StartTime  time.Time
    Duration   time.Duration
    ExitCode   int
}
```

```go
func (m *TerminalActivityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeCommands = make(map[int]*CommandInfo)
    go m.monitor()
}

func (m *TerminalActivityMonitor) monitor() {
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

func (m *TerminalActivityMonitor) checkTerminals() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinTerminals()
    } else {
        m.checkLinuxTerminals()
    }
}

func (m *TerminalActivityMonitor) checkDarwinTerminals() {
    // Use ps to get terminal processes
    cmd := exec.Command("ps", "-eo", "pid,user,tty,comm,etime")
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

        m.evaluateCommand(info)
    }
}

func (m *TerminalActivityMonitor) checkLinuxTerminals() {
    // Use ps with terminal filtering
    cmd := exec.Command("ps", "-eo", "pid,user,tty,cmd,etime", "--sort=-etime")
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

        m.evaluateCommand(info)
    }
}

func (m *TerminalActivityMonitor) parsePSLine(line string) *CommandInfo {
    parts := strings.Fields(line)
    if len(parts) < 5 {
        return nil
    }

    pid, err := strconv.Atoi(parts[0])
    if err != nil {
        return nil
    }

    user := parts[1]
    tty := parts[2]

    // Check user filter
    if len(m.config.WatchUsers) > 0 {
        found := false
        for _, watchUser := range m.config.WatchUsers {
            if user == watchUser {
                found = true
                break
            }
        }
        if !found {
            return nil
        }
    }

    // Skip system processes
    if tty == "?" || tty == "" {
        return nil
    }

    // Get command (may contain spaces)
    command := strings.Join(parts[3:], " ")

    // Check command filter
    if len(m.config.WatchCommands) > 0 {
        found := false
        for _, watchCmd := range m.config.WatchCommands {
            if strings.Contains(command, watchCmd) {
                found = true
                break
            }
        }
        if !found {
            return nil
        }
    }

    // Parse elapsed time
    elapsed := m.parseElapsedTime(parts[len(parts)-1])

    return &CommandInfo{
        PID:        pid,
        UserName:   user,
        Command:    command,
        TTY:        tty,
        StartTime:  time.Now().Add(-elapsed),
        Duration:   elapsed,
    }
}

func (m *TerminalActivityMonitor) parseElapsedTime(etime string) time.Duration {
    // Parse elapsed time in formats: "mm:ss", "hh:mm:ss", "dd-hh:mm:ss"
    parts := strings.Split(etime, "-")
    var duration time.Duration

    if len(parts) == 2 {
        // Days-hh:mm:ss
        if d, err := strconv.Atoi(parts[0]); err == nil {
            duration += time.Duration(d) * 24 * time.Hour
        }
        etime = parts[1]
    }

    timeParts := strings.Split(etime, ":")
    if len(timeParts) >= 3 {
        if h, err := strconv.Atoi(timeParts[0]); err == nil {
            duration += time.Duration(h) * time.Hour
        }
        if m, err := strconv.Atoi(timeParts[1]); err == nil {
            duration += time.Duration(m) * time.Minute
        }
        if s, err := strconv.Atoi(timeParts[2]); err == nil {
            duration += time.Duration(s) * time.Second
        }
    } else if len(timeParts) == 2 {
        if m, err := strconv.Atoi(timeParts[0]); err == nil {
            duration += time.Duration(m) * time.Minute
        }
        if s, err := strconv.Atoi(timeParts[1]); err == nil {
            duration += time.Duration(s) * time.Second
        }
    }

    return duration
}

func (m *TerminalActivityMonitor) evaluateCommand(info *CommandInfo) {
    lastInfo := m.activeCommands[info.PID]

    if lastInfo == nil {
        // New command
        m.activeCommands[info.PID] = info
        m.onCommandStarted(info)
        return
    }

    // Update duration
    info.StartTime = lastInfo.StartTime
    m.activeCommands[info.PID] = info

    // Check for long-running command
    threshold := time.Duration(m.config.LongRunThreshold) * time.Second
    if info.Duration > threshold && lastInfo.Duration <= threshold {
        m.onLongRunningCommand(info)
    }
}

func (m *TerminalActivityMonitor) onCommandStarted(info *CommandInfo) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["start"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *TerminalActivityMonitor) onCommandCompleted(info *CommandInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    delete(m.activeCommands, info.PID)

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *TerminalActivityMonitor) onCommandFailed(info *CommandInfo) {
    if !m.config.SoundOnFail {
        return
    }

    delete(m.activeCommands, info.PID)

    sound := m.config.Sounds["fail"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *TerminalActivityMonitor) onLongRunningCommand(info *CommandInfo) {
    if !m.config.SoundOnLongRun {
        return
    }

    sound := m.config.Sounds["long_run"]
    if sound != "" {
        m.player.Play(sound, 0.5)
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
