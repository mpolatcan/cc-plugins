# Feature: Sound Event Kernel Print Monitor

Play sounds for kernel print messages and oops/panic events.

## Summary

Monitor kernel messages, oops, and panic events, playing sounds for critical kernel events.

## Motivation

- Kernel debugging feedback
- Crash detection
- Driver issue alerts
- System stability monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Kernel Print Events

| Event | Description | Example |
|-------|-------------|---------|
| Kernel Oops | Non-fatal error | NULL pointer deref |
| Kernel Panic | Fatal error | Kernel panic |
| Warning | Kernel warning | BUG warning |
| Info | Informational | Device attached |

### Configuration

```go
type KernelPrintMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchPatterns []string          `json:"watch_patterns"` // "panic", "oops", "BUG"
    SoundOnPanic  bool              `json:"sound_on_panic"]
    SoundOnOops   bool              `json:"sound_on_oops"]
    SoundOnWarn   bool              `json:"sound_on_warn"]
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 5 default
}

type KernelPrintEvent struct {
    Message   string
    Timestamp time.Time
    Level     string // "panic", "error", "warn", "info"
    Source    string
}
```

### Commands

```bash
/ccbell:kprint status                 # Show kernel print status
/ccbell:kprint add panic              # Add pattern to watch
/ccbell:kprint remove panic
/ccbell:kprint sound panic <sound>
/ccbell:kprint sound oops <sound>
/ccbell:kprint test                   # Test kernel sounds
```

### Output

```
$ ccbell:kprint status

=== Sound Event Kernel Print Monitor ===

Status: Enabled
Panic Sounds: Yes
Oops Sounds: Yes

Watched Patterns: 3

[1] panic
    Matches: 0
    Last Match: --
    Sound: bundled:kprint-panic

[2] oops
    Matches: 5
    Last Match: 5 min ago
    Sound: bundled:kprint-oops

[3] BUG
    Matches: 2
    Last Match: 1 hour ago
    Sound: bundled:kprint-bug

Recent Events:
  [1] oops (5 min ago)
       NULL pointer dereference in ext4
  [2] BUG (1 hour ago)
       kernel BUG at mm/slab.c
  [3] warning (2 hours ago)
       CPU temperature high

Kernel Message Statistics:
  Panics: 0 (24h)
  Oops: 5 (24h)
  Warnings: 50 (24h)

Sound Settings:
  Panic: bundled:kprint-panic
  Oops: bundled:kprint-oops
  Warning: bundled:kprint-warn

[Configure] [Add Pattern] [Test All]
```

---

## Audio Player Compatibility

Kernel print monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Kernel Print Monitor

```go
type KernelPrintMonitor struct {
    config           *KernelPrintMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    patternMatches   map[string]int
    lastMatchTime    map[string]time.Time
}

func (m *KernelPrintMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.patternMatches = make(map[string]int)
    m.lastMatchTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *KernelPrintMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotKernelMessages()

    for {
        select {
        case <-ticker.C:
            m.checkKernelMessages()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KernelPrintMonitor) snapshotKernelMessages() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinKernelMessages()
    } else {
        m.snapshotLinuxKernelMessages()
    }
}

func (m *KernelPrintMonitor) snapshotDarwinKernelMessages() {
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'kernel' || eventMessage CONTAINS 'panic'",
        "--last", "5m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLogOutput(string(output))
}

func (m *KernelPrintMonitor) snapshotLinuxKernelMessages() {
    // Read kernel ring buffer
    cmd := exec.Command("dmesg")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDmesgOutput(string(output))
}

func (m *KernelPrintMonitor) checkKernelMessages() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinKernelMessages()
    } else {
        m.checkLinuxKernelMessages()
    }
}

func (m *KernelPrintMonitor) checkDarwinKernelMessages() {
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'kernel' || eventMessage CONTAINS 'panic' || eventMessage CONTAINS 'oops'",
        "--last", "1m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLogOutput(string(output))
}

func (m *KernelPrintMonitor) checkLinuxKernelMessages() {
    cmd := exec.Command("dmesg")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDmesgOutput(string(output))
}

func (m *KernelPrintMonitor) parseLogOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        for _, pattern := range m.config.WatchPatterns {
            if strings.Contains(strings.ToLower(line), strings.ToLower(pattern)) {
                m.onKernelMessageMatched(pattern, line)
            }
        }
    }
}

func (m *KernelPrintMonitor) parseDmesgOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        for _, pattern := range m.config.WatchPatterns {
            if strings.Contains(strings.ToLower(line), strings.ToLower(pattern)) {
                m.onKernelMessageMatched(pattern, line)
            }
        }
    }
}

func (m *KernelPrintMonitor) onKernelMessageMatched(pattern string, message string) {
    eventType := m.classifyEvent(message)

    switch eventType {
    case "panic":
        if !m.config.SoundOnPanic {
            return
        case "oops", "bug":
        if !m.config.SoundOnOops {
            return
        case "warning":
        if !m.config.SoundOnWarn {
            return
        }
    }

    m.patternMatches[pattern]++

    key := fmt.Sprintf("%s:%s", pattern, eventType)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds[eventType]
        if sound == "" {
            sound = m.config.Sounds[pattern]
        }
        if sound == "" {
            sound = m.config.Sounds["default"]
        }

        if sound != "" {
            volume := m.getEventVolume(eventType)
            m.player.Play(sound, volume)
        }
    }

    m.lastMatchTime[key] = time.Now()
}

func (m *KernelPrintMonitor) classifyEvent(message string) string {
    lower := strings.ToLower(message)

    if strings.Contains(lower, "kernel panic") || strings.Contains(lower, "panic:") {
        return "panic"
    }
    if strings.Contains(lower, "oops") || strings.Contains(lower, "BUG") {
        return "oops"
    }
    if strings.Contains(lower, "warning") || strings.Contains(lower, "warn") {
        return "warning"
    }

    return "info"
}

func (m *KernelPrintMonitor) getEventVolume(eventType string) float64 {
    switch eventType {
    case "panic":
        return 0.8
    case "oops":
        return 0.6
    case "warning":
        return 0.4
    default:
        return 0.3
    }
}

func (m *KernelPrintMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastMatchTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastMatchTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| log | System Tool | Free | macOS logging |
| dmesg | System Tool | Free | Linux kernel messages |

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
| Linux | Supported | Uses dmesg |
| Windows | Not Supported | ccbell only supports macOS/Linux |
