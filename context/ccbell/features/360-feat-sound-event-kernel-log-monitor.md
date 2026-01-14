# Feature: Sound Event Kernel Log Monitor

Play sounds for kernel log events, errors, and warnings.

## Summary

Monitor kernel messages, system errors, and critical log entries, playing sounds for kernel log events.

## Motivation

- Kernel awareness
- Error detection
- Hardware failure alerts
- System instability warnings
- Kernel panic detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Kernel Log Events

| Event | Description | Example |
|-------|-------------|---------|
| Kernel Error | Error message logged | Hardware error |
| Kernel Warning | Warning message | Deprecated API |
| Kernel Panic | System panic detected | Kernel panic |
| OOM Killer | Out of memory killer | Process killed |
| Hardware Error | Hardware failure | ECC error |
| Driver Error | Driver problem | Failed to load |

### Configuration

```go
type KernelLogMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnError      bool              `json:"sound_on_error"]
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnPanic      bool              `json:"sound_on_panic"`
    SoundOnOOM        bool              `json:"sound_on_oom"`
    SoundOnHardware   bool              `json:"sound_on_hardware"`
    IgnorePatterns    []string          `json:"ignore_patterns"` // "debug", "info"
    WatchPatterns     []string          `json:"watch_patterns"` // "error", "failed", "panic"
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type KernelLogEvent struct {
    Level      string // "err", "warn", "panic", "info"
    Message    string
    Source     string // module/component
    Timestamp  time.Time
    Count      int
    EventType  string // "error", "warning", "panic", "oom", "hardware"
}
```

### Commands

```bash
/ccbell:klog status                   # Show kernel log status
/ccbell:klog sound error <sound>
/ccbell:klog sound panic <sound>
/ccbell:klog add pattern error        # Add pattern to watch
/ccbell:klog remove pattern error
/ccbell:klog test                     # Test kernel log sounds
```

### Output

```
$ ccbell:klog status

=== Sound Event Kernel Log Monitor ===

Status: Enabled
Error Sounds: Yes
Warning Sounds: Yes
Panic Sounds: Yes
OOM Sounds: Yes

Recent Kernel Events:
  [1] ERROR: mmc0: Timeout waiting for hardware interrupt (5 min ago)
       [mmc_host]
       Count: 1

  [2] WARNING: nvidia: API mismatch (10 min ago)
       [nvidia_drm]
       Count: 3

  [3] OOM: oom-killer invoked (1 hour ago)
       [memory]
       PID: 12345, Command: chrome
       Count: 1

  [4] ERROR: network: interface eth0 went down (2 hours ago)
       [e1000e]
       Count: 1

Kernel Log Statistics:
  Errors Today: 15
  Warnings: 45
  OOM Events: 2
  Panic Events: 0

Sound Settings:
  Error: bundled:klog-error
  Warning: bundled:klog-warning
  Panic: bundled:klog-panic
  OOM: bundled:klog-oom

[Configure] [Set Patterns] [Test All]
```

---

## Audio Player Compatibility

Kernel log monitoring doesn't play sounds directly:
- Monitoring feature using journalctl/dmesg
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Kernel Log Monitor

```go
type KernelLogMonitor struct {
    config          *KernelLogMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    lastLine        string
    errorCount      map[string]int
    lastEventTime   map[string]time.Time
}

func (m *KernelLogMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.errorCount = make(map[string]int)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *KernelLogMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial: read existing logs
    m.readKernelLogs()

    for {
        select {
        case <-ticker.C:
            m.checkKernelLogs()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KernelLogMonitor) readKernelLogs() {
    if runtime.GOOS == "linux" {
        // Read from journalctl
        m.readJournalctlLogs()
    } else {
        m.readDmesgLogs()
    }
}

func (m *KernelLogMonitor) checkKernelLogs() {
    if runtime.GOOS == "linux" {
        m.readJournalctlLogs()
    } else {
        m.readDmesgLogs()
    }
}

func (m *KernelLogMonitor) readJournalctlLogs() {
    cmd := exec.Command("journalctl", "-k", "--since=5m", "-o", "json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseJournalctlOutput(string(output))
}

func (m *KernelLogMonitor) parseJournalctlOutput(output string) {
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse JSON log entry
        event := m.parseJSONLogEntry(line)
        if event != nil {
            m.evaluateLogEvent(event)
        }
    }
}

func (m *KernelLogMonitor) parseJSONLogEntry(line string) *KernelLogEvent {
    // Simple JSON parsing for priority and message
    // This is a simplified approach

    if strings.Contains(line, `"PRIORITY":"0"`) || strings.Contains(line, `"PRIORITY":0`) {
        return &KernelLogEvent{Level: "emergency"}
    } else if strings.Contains(line, `"PRIORITY":"1"`) || strings.Contains(line, `"PRIORITY":1`) {
        return &KernelLogEvent{Level: "alert"}
    } else if strings.Contains(line, `"PRIORITY":"2"`) || strings.Contains(line, `"PRIORITY":2`) {
        return &KernelLogEvent{Level: "critical"}
    } else if strings.Contains(line, `"PRIORITY":"3"`) || strings.Contains(line, `"PRIORITY":3`) {
        return &KernelLogEvent{Level: "error"}
    } else if strings.Contains(line, `"PRIORITY":"4"`) || strings.Contains(line, `"PRIORITY":4`) {
        return &KernelLogEvent{Level: "warning"}
    }

    return nil
}

func (m *KernelLogMonitor) readDmesgLogs() {
    cmd := exec.Command("dmesg", "-T", "--time-format=iso", "-L")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == m.lastLine {
            continue
        }

        event := m.parseDmesgLine(line)
        if event != nil {
            m.evaluateLogEvent(event)
        }

        m.lastLine = line
    }
}

func (m *KernelLogMonitor) parseDmesgLine(line string) *KernelLogEvent {
    // Parse dmesg line format: "[timestamp] level: message"
    re := regexp.MustCompile(`\[([^\]]+)\] (\w+): (.+)`)
    match := re.FindStringSubmatch(line)
    if match == nil {
        return nil
    }

    timestamp := match[1]
    level := strings.ToLower(match[2])
    message := match[3]

    // Check if should ignore
    for _, pattern := range m.config.IgnorePatterns {
        if strings.Contains(strings.ToLower(message), strings.ToLower(pattern)) {
            return nil
        }
    }

    event := &KernelLogEvent{
        Level:    level,
        Message:  message,
        Timestamp: time.Now(),
    }

    // Determine event type
    if strings.Contains(message, "oom-killer") || strings.Contains(message, "Out of memory") {
        event.EventType = "oom"
    } else if strings.Contains(message, "panic") {
        event.EventType = "panic"
    } else if strings.Contains(message, "hardware error") || strings.Contains(message, "ECC error") {
        event.EventType = "hardware"
    } else if level == "error" || strings.Contains(message, "error") {
        event.EventType = "error"
    } else if level == "warning" || strings.Contains(message, "warning") {
        event.EventType = "warning"
    }

    return event
}

func (m *KernelLogMonitor) evaluateLogEvent(event *KernelLogEvent) {
    if event.EventType == "" {
        return
    }

    switch event.EventType {
    case "error":
        m.onKernelError(event)
    case "warning":
        m.onKernelWarning(event)
    case "panic":
        m.onKernelPanic(event)
    case "oom":
        m.onOOMKiller(event)
    case "hardware":
        m.onHardwareError(event)
    }
}

func (m *KernelLogMonitor) onKernelError(event *KernelLogEvent) {
    if !m.config.SoundOnError {
        return
    }

    key := m.getEventKey(event)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *KernelLogMonitor) onKernelWarning(event *KernelLogEvent) {
    if !m.config.SoundOnWarning {
        return
    }

    key := m.getEventKey(event)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *KernelLogMonitor) onKernelPanic(event *KernelLogEvent) {
    if !m.config.SoundOnPanic {
        return
    }

    key := m.getEventKey(event)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["panic"]
        if sound != "" {
            m.player.Play(sound, 0.8)
        }
    }
}

func (m *KernelLogMonitor) onOOMKiller(event *KernelLogEvent) {
    if !m.config.SoundOnOOM {
        return
    }

    key := m.getEventKey(event)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["oom"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *KernelLogMonitor) onHardwareError(event *KernelLogEvent) {
    if !m.config.SoundOnHardware {
        return
    }

    key := m.getEventKey(event)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["hardware"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *KernelLogMonitor) getEventKey(event *KernelLogEvent) string {
    // Create a unique key based on message content
    if len(event.Message) > 50 {
        return fmt.Sprintf("%s:%s", event.EventType, event.Message[:50])
    }
    return fmt.Sprintf("%s:%s", event.EventType, event.Message)
}

func (m *KernelLogMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| journalctl | System Tool | Free | systemd journal |
| dmesg | System Tool | Free | Kernel messages |

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
| macOS | Supported | Uses log, dmesg |
| Linux | Supported | Uses journalctl, dmesg |
