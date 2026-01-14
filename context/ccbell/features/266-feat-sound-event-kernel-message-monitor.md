# Feature: Sound Event Kernel Message Monitor

Play sounds for kernel messages and system alerts.

## Summary

Monitor kernel messages, system alerts, and kernel-level events, playing sounds when significant kernel events occur.

## Motivation

- Kernel panic alerts
- System call warnings
- Hardware events
- Security notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Kernel Message Events

| Event | Description | Example |
|-------|-------------|---------|
| Kernel Panic | Critical failure | Oops message |
| Warning | Kernel warning | memory warning |
| Info | Informational | device attached |
| Error | Kernel error | I/O error |

### Configuration

```go
type KernelMessageMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchPatterns    []string          `json:"watch_patterns"` // "panic", "error", "warning"
    IgnorePatterns   []string          `json:"ignore_patterns"`
    SoundOnPanic     bool              `json:"sound_on_panic"`
    SoundOnError     bool              `json:"sound_on_error"`
    SoundOnWarning   bool              `json:"sound_on_warning"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 1 default
}

type KernelMessageEvent struct {
    Message    string
    Facility   string // "kernel", "auth", "daemon"
    Severity   string // "panic", "error", "warning", "info"
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:kernel status               # Show kernel status
/ccbell:kernel add "panic"          # Add pattern to watch
/ccbell:kernel remove "panic"
/ccbell:kernel sound panic <sound>
/ccbell:kernel test                 # Test kernel sounds
```

### Output

```
$ ccbell:kernel status

=== Sound Event Kernel Message Monitor ===

Status: Enabled
Panic Sounds: Yes
Error Sounds: Yes

Current Kernel Activity:
  Messages/min: 15
  Warnings/min: 2
  Errors/min: 0

Recent Events:
  [1] WARNING (5 min ago)
       memory: page allocation failure
  [2] INFO (1 hour ago)
       device: USB device attached
  [3] ERROR (2 hours ago)
       I/O: disk read error

Filtered Patterns:
  - panic (watching)
  - error (watching)
  - warning (watching)

Sound Settings:
  Panic: bundled:stop
  Error: bundled:stop
  Warning: bundled:stop

[Configure] [Add Pattern] [Test All]
```

---

## Audio Player Compatibility

Kernel message monitoring doesn't play sounds directly:
- Monitoring feature using kernel log tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Kernel Message Monitor

```go
type KernelMessageMonitor struct {
    config         *KernelMessageMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    logPosition    int64
    lastEventTime  map[string]time.Time
}

func (m *KernelMessageMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *KernelMessageMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkKernelMessages()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KernelMessageMonitor) checkKernelMessages() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinKernelMessages()
    } else {
        m.checkLinuxKernelMessages()
    }
}

func (m *KernelMessageMonitor) checkDarwinKernelMessages() {
    // Use log command to read system log
    cmd := exec.Command("log", "show", "--predicate", "eventMessage CONTAINS 'kernel'",
        "--last", "1m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        event := m.parseKernelMessage(line)
        if event != nil {
            m.evaluateEvent(event)
        }
    }
}

func (m *KernelMessageMonitor) checkLinuxKernelMessages() {
    // Read from /dev/kmsg or /var/log/kern.log
    kmsgPath := "/dev/kmsg"
    if _, err := os.Stat(kmsgPath); os.IsNotExist(err) {
        kmsgPath = "/var/log/kern.log"
    }

    file, err := os.Open(kmsgPath)
    if err != nil {
        return
    }
    defer file.Close()

    // Seek to last position
    file.Seek(m.logPosition, 0)

    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        line := scanner.Text()
        event := m.parseKernelMessage(line)
        if event != nil {
            m.evaluateEvent(event)
        }
    }

    // Update position
    pos, _ := file.Seek(0, 1)
    m.logPosition = pos
}

func (m *KernelMessageMonitor) parseKernelMessage(line string) *KernelMessageEvent {
    event := &KernelMessageEvent{
        Timestamp: time.Now(),
    }

    // Check ignore patterns
    for _, pattern := range m.config.IgnorePatterns {
        if strings.Contains(strings.ToLower(line), strings.ToLower(pattern)) {
            return nil
        }
    }

    // Determine severity
    lineLower := strings.ToLower(line)
    if strings.Contains(lineLower, "panic") ||
       strings.Contains(lineLower, "oops") ||
       strings.Contains(lineLower, "kernel bug") {
        event.Severity = "panic"
    } else if strings.Contains(lineLower, "error") ||
              strings.Contains(lineLower, "fail") ||
              strings.Contains(lineLower, "critical") {
        event.Severity = "error"
    } else if strings.Contains(lineLower, "warning") ||
              strings.Contains(lineLower, "warn") {
        event.Severity = "warning"
    } else if strings.Contains(lineLower, "info") {
        event.Severity = "info"
    } else {
        return nil
    }

    // Check watch patterns
    if len(m.config.WatchPatterns) > 0 {
        found := false
        for _, pattern := range m.config.WatchPatterns {
            if strings.Contains(strings.ToLower(line), strings.ToLower(pattern)) {
                found = true
                break
            }
        }
        if !found {
            return nil
        }
    }

    event.Message = line
    return event
}

func (m *KernelMessageMonitor) evaluateEvent(event *KernelMessageEvent) {
    // Debounce similar events
    key := event.Severity + ":" + event.Facility
    if lastTime := m.lastEventTime[key]; lastTime.Add(5*time.Second).After(time.Now()) {
        return
    }
    m.lastEventTime[key] = time.Now()

    switch event.Severity {
    case "panic":
        m.onKernelPanic(event)
    case "error":
        m.onKernelError(event)
    case "warning":
        m.onKernelWarning(event)
    }
}

func (m *KernelMessageMonitor) onKernelPanic(event *KernelMessageEvent) {
    if !m.config.SoundOnPanic {
        return
    }

    sound := m.config.Sounds["panic"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}

func (m *KernelMessageMonitor) onKernelError(event *KernelMessageEvent) {
    if !m.config.SoundOnError {
        return
    }

    sound := m.config.Sounds["error"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *KernelMessageMonitor) onKernelWarning(event *KernelMessageEvent) {
    if !m.config.SoundOnWarning {
        return
    }

    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| log | System Tool | Free | macOS logging |
| /dev/kmsg | Device | Free | Linux kernel ring buffer |
| /var/log/kern.log | File | Free | Linux kernel log |

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
| Linux | Supported | Uses /dev/kmsg |
| Windows | Not Supported | ccbell only supports macOS/Linux |
