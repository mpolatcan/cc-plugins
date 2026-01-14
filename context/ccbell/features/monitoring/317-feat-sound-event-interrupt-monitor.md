# Feature: Sound Event Interrupt Monitor

Play sounds for hardware interrupt rate changes and anomalies.

## Summary

Monitor hardware interrupt rates, IRQ handling times, and interrupt storms, playing sounds for interrupt events.

## Motivation

- Hardware issue detection
- Performance bottleneck identification
- Interrupt storm alerts
- Driver problem feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Interrupt Events

| Event | Description | Example |
|-------|-------------|---------|
| High Interrupt Rate | IRQ spike | > 1000/s |
| Interrupt Storm | Sustained high rate | > 5000/s |
| New IRQ | New device interrupt | USB device |
| Slow IRQ | High latency IRQ | > 1ms avg |

### Configuration

```go
type InterruptMonitorConfig struct {
    Enabled              bool              `json:"enabled"`
    WatchIRQs            []int             `json:"watch_irqs"] // 1, 9, 14
    WarningRate          int               `json:"warning_rate_per_sec"` // 1000 default
    CriticalRate         int               `json:"critical_rate_per_sec"` // 5000 default
    SoundOnHigh          bool              `json:"sound_on_high"]
    SoundOnStorm         bool              `json:"sound_on_storm"]
    SoundOnNewIRQ        bool              `json:"sound_on_new_irq"]
    Sounds               map[string]string `json:"sounds"`
    PollInterval         int               `json:"poll_interval_sec"` // 5 default
}

type InterruptEvent struct {
    IRQ         int
    Device      string
    Count       int64
    RatePerSec  float64
    AvgLatency  float64
    EventType   string // "high", "storm", "new", "slow"
}
```

### Commands

```bash
/ccbell:intr status                   # Show interrupt status
/ccbell:intr add 9                    # Add IRQ to watch
/ccbell:intr remove 9
/ccbell:intr rate 1000                # Set warning rate
/ccbell:intr sound storm <sound>
/ccbell:intr test                     # Test interrupt sounds
```

### Output

```
$ ccbell:intr status

=== Sound Event Interrupt Monitor ===

Status: Enabled
Warning Rate: 1000/sec
Critical Rate: 5000/sec

Watched IRQs: 3

[1] IRQ 1 (keyboard)
    Rate: 50/sec
    Avg Latency: 0.01ms
    Status: OK
    Sound: bundled:stop

[2] IRQ 9 (acpi)
    Rate: 200/sec
    Avg Latency: 0.05ms
    Status: OK
    Sound: bundled:stop

[3] IRQ 14 (sata)
    Rate: 1,500/sec
    Avg Latency: 0.2ms
    Status: WARNING
    Sound: bundled:intr-warning

Recent Events:
  [1] IRQ 14: High Rate (5 min ago)
       1500/sec sustained
  [2] IRQ 9: New IRQ (1 hour ago)
       ACPI thermal interrupt
  [3] IRQ 51: Slow IRQ (2 hours ago)
       5ms average latency

Interrupt Statistics:
  Total IRQs/sec: 2500
  Storm events: 0

Sound Settings:
  High: bundled:intr-warning
  Storm: bundled:intr-storm
  New: bundled:stop

[Configure] [Add IRQ] [Test All]
```

---

## Audio Player Compatibility

Interrupt monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Interrupt Monitor

```go
type InterruptMonitor struct {
    config            *InterruptMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    irqState          map[int]*IRQInfo
    lastEventTime     map[string]time.Time
}

type IRQInfo struct {
    IRQ       int
    Device    string
    Count     int64
    Rate      float64
    Latency   float64
}

func (m *InterruptMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.irqState = make(map[int]*IRQInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *InterruptMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotInterruptState()

    for {
        select {
        case <-ticker.C:
            m.checkInterruptState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *InterruptMonitor) snapshotInterruptState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinInterrupts()
    } else {
        m.snapshotLinuxInterrupts()
    }
}

func (m *InterruptMonitor) snapshotDarwinInterrupts() {
    cmd := exec.Command("sysctl", "hw.interrupts")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSysctlOutput(string(output))
}

func (m *InterruptMonitor) snapshotLinuxInterrupts() {
    // Read /proc/interrupts
    data, err := os.ReadFile("/proc/interrupts")
    if err != nil {
        return
    }

    m.parseInterruptsFile(string(data))
}

func (m *InterruptMonitor) checkInterruptState() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinInterrupts()
    } else {
        m.checkLinuxInterrupts()
    }
}

func (m *InterruptMonitor) checkDarwinInterrupts() {
    cmd := exec.Command("sysctl", "hw.interrupts")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSysctlOutput(string(output))
}

func (m *InterruptMonitor) checkLinuxInterrupts() {
    data, err := os.ReadFile("/proc/interrupts")
    if err != nil {
        return
    }

    m.parseInterruptsFile(string(data))
}

func (m *InterruptMonitor) parseSysctlOutput(output string) {
    lines := strings.Split(output, "\n")
    currentIRQs := make(map[int]int64)

    for _, line := range lines {
        if !strings.HasPrefix(line, "hw.interrupts") {
            continue
        }

        parts := strings.Split(line, ":")
        if len(parts) < 2 {
            continue
        }

        // Parse interrupt counts
        values := strings.Fields(parts[1])
        for i, val := range values {
            count, _ := strconv.ParseInt(val, 10, 64)
            currentIRQs[i] = count
        }
    }

    m.evaluateIRQChanges(currentIRQs)
}

func (m *InterruptMonitor) parseInterruptsFile(data string) {
    lines := strings.Split(data, "\n")
    currentIRQs := make(map[int]*IRQInfo)

    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "  ") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        // First column is IRQ number
        irqStr := strings.TrimSuffix(parts[0], ":")
        irq, err := strconv.Atoi(irqStr)
        if err != nil {
            continue
        }

        // Skip total line
        if irqStr == "total" {
            continue
        }

        // Parse count (last numeric column)
        var count int64
        for i := len(parts) - 1; i >= 0; i-- {
            if c, err := strconv.ParseInt(parts[i], 10, 64); err == nil {
                count = c
                break
            }
        }

        // Extract device name (usually in brackets)
        device := ""
        for _, part := range parts {
            if strings.HasPrefix(part, "[") && strings.HasSuffix(part, "]") {
                device = strings.Trim(part, "[]")
                break
            }
        }

        currentIRQs[irq] = &IRQInfo{
            IRQ:    irq,
            Device: device,
            Count:  count,
        }
    }

    m.evaluateIRQChanges(currentIRQs)
}

func (m *InterruptMonitor) evaluateIRQChanges(currentIRQs map[int]*IRQInfo) {
    // Check for new IRQs
    for irq := range currentIRQs {
        if _, exists := m.irqState[irq]; !exists {
            m.onNewIRQ(irq, currentIRQs[irq])
        }
    }

    // Check rate changes
    for irq, info := range currentIRQs {
        lastInfo, exists := m.irqState[irq]
        if !exists {
            continue
        }

        // Calculate rate
        interval := float64(m.config.PollInterval)
        rate := float64(info.Count-lastInfo.Count) / interval

        if rate >= float64(m.config.CriticalRate) {
            m.onInterruptStorm(irq, rate)
        } else if rate >= float64(m.config.WarningRate) {
            m.onHighInterruptRate(irq, rate)
        }

        info.Rate = rate
    }

    m.irqState = currentIRQs
}

func (m *InterruptMonitor) onNewIRQ(irq int, info *IRQInfo) {
    if !m.config.SoundOnNewIRQ {
        return
    }

    key := fmt.Sprintf("new:%d", irq)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["new"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *InterruptMonitor) onHighInterruptRate(irq int, rate float64) {
    if !m.config.SoundOnHigh {
        return
    }

    if !m.shouldWatchIRQ(irq) {
        return
    }

    key := fmt.Sprintf("high:%d", irq)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *InterruptMonitor) onInterruptStorm(irq int, rate float64) {
    if !m.config.SoundOnStorm {
        return
    }

    if !m.shouldWatchIRQ(irq) {
        return
    }

    key := fmt.Sprintf("storm:%d", irq)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["storm"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *InterruptMonitor) shouldWatchIRQ(irq int) bool {
    if len(m.config.WatchIRQs) == 0 {
        return true
    }

    for _, w := range m.config.WatchIRQs {
        if w == irq {
            return true
        }
    }

    return false
}

func (m *InterruptMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| sysctl | System Tool | Free | macOS interrupt info |
| /proc/interrupts | File | Free | Linux interrupt info |

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
| macOS | Supported | Uses sysctl |
| Linux | Supported | Uses /proc/interrupts |
| Windows | Not Supported | ccbell only supports macOS/Linux |
