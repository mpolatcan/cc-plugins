# Feature: Sound Event Signal Monitor

Play sounds for important signal delivery events.

## Summary

Monitor signal delivery to processes, playing sounds for significant signal events.

## Motivation

- Signal awareness
- Process termination feedback
- Debugging assistance
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

### Signal Events

| Event | Description | Example |
|-------|-------------|---------|
| SIGTERM Sent | Graceful termination | kill -15 |
| SIGKILL Sent | Force termination | kill -9 |
| SIGINT Sent | Interrupt signal | Ctrl+C |
| SIGSEGV Received | Segmentation fault | Crash |

### Configuration

```go
type SignalMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchSignals    []string          `json:"watch_signals"` // "SIGTERM", "SIGKILL", "SIGINT"
    WatchProcesses  []string          `json:"watch_processes"`
    SoundOnSignal   bool              `json:"sound_on_signal"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 1 default
}

type SignalEvent struct {
    ProcessName string
    PID         int
    Signal      string
    SenderPID   int
    EventType   string
}
```

### Commands

```bash
/ccbell:signal status                 # Show signal status
/ccbell:signal add SIGTERM            # Add signal to watch
/ccbell:signal remove SIGTERM
/ccbell:signal sound SIGTERM <sound>
/ccbell:signal test                   # Test signal sounds
```

### Output

```
$ ccbell:signal status

=== Sound Event Signal Monitor ===

Status: Enabled
Signal Sounds: Yes

Watched Signals: 3

[1] SIGTERM
    Count/min: 5
    Last Signal: 5 sec ago
    Sound: bundled:stop

[2] SIGKILL
    Count/min: 1
    Last Signal: 1 min ago
    Sound: bundled:signal-kill

[3] SIGINT
    Count/min: 10
    Last Signal: 10 sec ago
    Sound: bundled:stop

Recent Events:
  [1] nginx: SIGTERM (5 sec ago)
       PID: 1234
  [2] java: SIGKILL (1 min ago)
       PID: 5678
  [3] node: SIGINT (5 min ago)
       PID: 9012

Signal Statistics (Last Hour):
  - SIGTERM: 300 sent
  - SIGKILL: 60 sent
  - SIGINT: 600 sent

Sound Settings:
  SIGTERM: bundled:stop
  SIGKILL: bundled:signal-kill
  SIGINT: bundled:stop

[Configure] [Add Signal] [Test All]
```

---

## Audio Player Compatibility

Signal monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Signal Monitor

```go
type SignalMonitor struct {
    config           *SignalMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    signalCount      map[string]int
    lastSignalTime   map[string]time.Time
}

func (m *SignalMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.signalCount = make(map[string]int)
    m.lastSignalTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SignalMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSignals()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SignalMonitor) checkSignals() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinSignals()
    } else {
        m.checkLinuxSignals()
    }
}

func (m *SignalMonitor) checkDarwinSignals() {
    // Use log to capture signal events
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'signal' || eventMessage CONTAINS 'SIGTERM' || eventMessage CONTAINS 'SIGKILL'",
        "--last", "1m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLogOutput(string(output))
}

func (m *SignalMonitor) checkLinuxSignals() {
    // Check /proc/*/stat for signal info
    entries, err := os.ReadDir("/proc")
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        // Skip non-PID directories
        if _, err := strconv.Atoi(entry.Name()); err != nil {
            continue
        }

        statFile := filepath.Join("/proc", entry.Name(), "stat")
        data, err := os.ReadFile(statFile)
        if err != nil {
            continue
        }

        // Parse signal info from stat (field 40+)
        m.parseProcStat(entry.Name(), string(data))
    }
}

func (m *SignalMonitor) parseLogOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        for _, sig := range m.config.WatchSignals {
            if strings.Contains(line, sig) {
                m.onSignalDetected("unknown", sig)
                break
            }
        }
    }
}

func (m *SignalMonitor) parseProcStat(pid string, data string) {
    // Stat format: pid (comm) state ppid pgrp session tty_nr ...
    // Fields after comm are in parentheses, need to handle that
    start := strings.Index(data, "(")
    end := strings.Index(data, ")")

    if start == -1 || end == -1 {
        return
    }

    afterComm := data[end+2:]
    fields := strings.Fields(afterComm)

    // Field 7 is tty_nr, field 40+ contains signal info
    if len(fields) < 40 {
        return
    }

    // sigign and sigcatch are fields 40 and 41
    sigign := fields[39]
    sigcatch := fields[40]
}

func (m *SignalMonitor) shouldWatchSignal(signal string) bool {
    if len(m.config.WatchSignals) == 0 {
        return true
    }

    for _, sig := range m.config.WatchSignals {
        if signal == sig {
            return true
        }
    }

    return false
}

func (m *SignalMonitor) onSignalDetected(processName string, signal string) {
    if !m.config.SoundOnSignal {
        return
    }

    if !m.shouldWatchSignal(signal) {
        return
    }

    // Debounce: don't alert too frequently
    key := signal
    if lastTime := m.lastSignalTime[key]; lastTime.Add(5*time.Second).After(time.Now()) {
        return
    }
    m.lastSignalTime[key] = time.Now()

    m.signalCount[signal]++

    // Get sound for this signal
    sound := m.config.Sounds[signal]
    if sound == "" {
        sound = m.config.Sounds["default"]
    }

    if sound != "" {
        // SIGKILL is more critical
        volume := 0.4
        if signal == "SIGKILL" {
            volume = 0.6
        }
        m.player.Play(sound, volume)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| log | System Tool | Free | macOS logging |
| /proc/*/stat | File | Free | Linux process info |

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
| Linux | Supported | Uses /proc/*/stat |
| Windows | Not Supported | ccbell only supports macOS/Linux |
