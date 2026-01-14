# Feature: Sound Event Kernel Message Monitor

Play sounds for kernel messages, system errors, and critical kernel events.

## Summary

Monitor kernel message buffer (dmesg) for system errors, hardware issues, and critical kernel events, playing sounds for kernel events.

## Motivation

- Kernel error awareness
- Hardware failure detection
- System crash prevention
- Kernel panic alerts
- Driver issue detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Kernel Message Events

| Event | Description | Example |
|-------|-------------|---------|
| Kernel Error | Error level message | "error", "failed" |
| Kernel Warning | Warning level message | "warning", "warn" |
| Kernel Critical | Critical message | "critical", "panic" |
| Hardware Error | Hardware related | "hardware", "i/o error" |
| Memory Issue | Memory related | "oom", "out of memory" |
| Disk Error | Storage related | "disk", "sector", "smart" |

### Configuration

```go
type KernelMessageMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    ErrorPatterns    []string          `json:"error_patterns"` // "error", "failed", "panic"
    WarningPatterns  []string          `json:"warning_patterns"` // "warning", "warn"
    CriticalPatterns []string          `json:"critical_patterns"` // "critical", "panic", "oom"
    HardwarePatterns []string          `json:"hardware_patterns"` // "hardware", "i/o error"
    SoundOnError     bool              `json:"sound_on_error"`
    SoundOnWarning   bool              `json:"sound_on_warning"`
    SoundOnCritical  bool              `json:"sound_on_critical"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:dmesg status                # Show kernel message status
/ccbell:dmesg pattern error "error"  # Add error pattern
/ccbell:dmesg sound error <sound>
/ccbell:dmesg test                  # Test kernel sounds
```

### Output

```
$ ccbell:dmesg status

=== Sound Event Kernel Message Monitor ===

Status: Enabled
Error Patterns: 3
Warning Patterns: 2
Critical Patterns: 2

Recent Kernel Events:

[1] System: Kernel Error (5 min ago)
       [sd0] IOException sector 12345
       Sound: bundled:kernel-error
  [2] System: Kernel Warning (1 hour ago)
       [cpu0] temperature warning
       Sound: bundled:kernel-warning
  [3] System: Kernel Critical (2 hours ago)
       Memory OOM killer invoked
       Sound: bundled:kernel-critical

Kernel Event Statistics:
  Total Events Today: 15
  Errors: 5
  Warnings: 8
  Critical: 2

Sound Settings:
  Error: bundled:kernel-error
  Warning: bundled:kernel-warning
  Critical: bundled:kernel-critical

[Configure] [Test All]
```

---

## Audio Player Compatibility

Kernel monitoring doesn't play sounds directly:
- Monitoring feature using dmesg
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Kernel Message Monitor

```go
type KernelMessageMonitor struct {
    config        *KernelMessageMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastPosition  int64
    lastEventTime map[string]time.Time
}

type KernelEvent struct {
    Timestamp  time.Time
    Level      string // "error", "warning", "critical", "info"
    Message    string
    Source     string
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

    // Initial snapshot
    m.snapshotKernelState()

    for {
        select {
        case <-ticker.C:
            m.checkKernelState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KernelMessageMonitor) snapshotKernelState() {
    // Get current dmesg position
    cmd := exec.Command("dmesg", "--time-format=iso", "-T")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.lastPosition = int64(len(output))
}

func (m *KernelMessageMonitor) checkKernelState() {
    // Get new kernel messages since last check
    cmd := exec.Command("dmesg", "--time-format=iso", "-T", "--since=-"+strconv.Itoa(m.config.PollInterval)+"s")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        event := m.parseKernelMessage(line)
        if event != nil {
            m.processKernelEvent(event)
        }
    }
}

func (m *KernelMessageMonitor) parseKernelMessage(line string) *KernelEvent {
    event := &KernelEvent{
        Timestamp: time.Now(),
        Message:   line,
    }

    // Determine level based on patterns
    lineLower := strings.ToLower(line)

    for _, pattern := range m.config.CriticalPatterns {
        if strings.Contains(lineLower, strings.ToLower(pattern)) {
            event.Level = "critical"
            return event
        }
    }

    for _, pattern := range m.config.ErrorPatterns {
        if strings.Contains(lineLower, strings.ToLower(pattern)) {
            event.Level = "error"
            return event
        }
    }

    for _, pattern := range m.config.WarningPatterns {
        if strings.Contains(lineLower, strings.ToLower(pattern)) {
            event.Level = "warning"
            return event
        }
    }

    return nil
}

func (m *KernelMessageMonitor) processKernelEvent(event *KernelEvent) {
    key := fmt.Sprintf("%s:%s", event.Level, event.Message[:min(50, len(event.Message))])

    switch event.Level {
    case "critical":
        if m.config.SoundOnCritical && m.shouldAlert(key, 5*time.Minute) {
            m.onKernelCritical(event)
        }
    case "error":
        if m.config.SoundOnError && m.shouldAlert(key, 2*time.Minute) {
            m.onKernelError(event)
        }
    case "warning":
        if m.config.SoundOnWarning && m.shouldAlert(key, 5*time.Minute) {
            m.onKernelWarning(event)
        }
    }
}

func (m *KernelMessageMonitor) onKernelError(event *KernelEvent) {
    sound := m.config.Sounds["error"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *KernelMessageMonitor) onKernelWarning(event *KernelEvent) {
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *KernelMessageMonitor) onKernelCritical(event *KernelEvent) {
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *KernelMessageMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}

func min(a, b int) int {
    if a < b {
        return a
    }
    return b
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dmesg | System Tool | Free | Kernel message buffer |

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
| macOS | Supported | Uses log show instead of dmesg |
| Linux | Supported | Uses dmesg |
