# Feature: Sound Event Email Monitor

Play sounds for email delivery failures, queue buildup, and bounce notifications.

## Summary

Monitor email queue (Postfix, sendmail, mailutils) for delivery failures, queue size, and bounce notifications, playing sounds for email events.

## Motivation

- Email delivery awareness
- Failure detection
- Queue monitoring
- Bounce notification
- SMTP health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Email Events

| Event | Description | Example |
|-------|-------------|---------|
| Email Bounced | Delivery failed | bounce |
| Queue Buildup | Too many queued | > 100 |
| Queue Cleared | Queue processed | cleared |
| Deferral | Message deferred | deferral |
| Spam Detected | Spam caught | spam |
| Size Warning | Large message | > 10MB |

### Configuration

```go
type EmailMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    QueueThreshold   int               `json:"queue_threshold"` // 100 default
    SizeThresholdMB  int               `json:"size_threshold_mb"` // 10 default
    SoundOnBounce    bool              `json:"sound_on_bounce"`
    SoundOnQueueHigh bool              `json:"sound_on_queue_high"`
    SoundOnQueueClear bool             `json:"sound_on_queue_clear"`
    SoundOnDeferral  bool              `json:"sound_on_deferral"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:email status                # Show email status
/ccbell:email threshold queue 100   # Set queue threshold
/ccbell:email sound bounce <sound>
/ccbell:email test                  # Test email sounds
```

### Output

```
$ ccbell:email status

=== Sound Event Email Monitor ===

Status: Enabled
Queue Threshold: 100
Size Threshold: 10 MB

Email Queue Status:

[1] Postfix (main)
    Status: HEALTHY
    Queue Size: 15
    Deferred: 3
    Incoming: 2
    Active: 1
    Maildrop: 0
    Sound: bundled:email-postfix

[2] Sendmail
    Status: WARNING *** WARNING ***
    Queue Size: 145 *** HIGH ***
    Deferred: 25
    Bounced: 5
    Sound: bundled:email-sendmail *** WARNING ***

Recent Events:

[1] Sendmail: Queue High (5 min ago)
       145 messages > 100 threshold
       Sound: bundled:email-queue-high
  [2] Postfix: Email Bounced (1 hour ago)
       5 bounces detected
       Sound: bundled:email-bounce
  [3] Sendmail: Deferral (2 hours ago)
       3 messages deferred
       Sound: bundled:email-deferral

Email Statistics:
  Total Queues: 2
  Total Queued: 160
  Deferred: 28
  Bounced: 5

Sound Settings:
  Bounce: bundled:email-bounce
  Queue High: bundled:email-queue-high
  Queue Clear: bundled:email-queue-clear
  Deferral: bundled:email-deferral

[Configure] [Test All]
```

---

## Audio Player Compatibility

Email monitoring doesn't play sounds directly:
- Monitoring feature using mailq, postqueue
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Email Monitor

```go
type EmailMonitor struct {
    config        *EmailMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    emailState    map[string]*EmailQueueInfo
    lastEventTime map[string]time.Time
}

type EmailQueueInfo struct {
    MTA           string // "postfix", "sendmail", "exim"
    Status        string // "healthy", "warning", "critical"
    QueueSize     int
    DeferredSize  int
    IncomingSize  int
    ActiveSize    int
    BouncedSize   int
    LastCheck     time.Time
}

func (m *EmailMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.emailState = make(map[string]*EmailQueueInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *EmailMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotEmailState()

    for {
        select {
        case <-ticker.C:
            m.checkEmailState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *EmailMonitor) snapshotEmailState() {
    m.checkEmailState()
}

func (m *EmailMonitor) checkEmailState() {
    // Check Postfix
    m.checkPostfix()

    // Check Sendmail
    m.checkSendmail()

    // Check Exim
    m.checkExim()
}

func (m *EmailMonitor) checkPostfix() {
    info := &EmailQueueInfo{
        MTA: "postfix",
    }

    // Get queue count
    cmd := exec.Command("mailq", "-T")
    output, err := cmd.Output()
    if err != nil {
        // Try postqueue
        cmd = exec.Command("postqueue", "-p")
        output, err = cmd.Output()
    }

    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    m.parseMailqOutput(lines, info)

    // Check deferred queue
    cmd = exec.Command("find", "/var/spool/postfix/deferred", "-type", "f")
    deferOutput, _ := cmd.Output()
    deferredCount := strings.Count(string(deferOutput), "\n")
    info.DeferredSize = deferredCount

    // Check incoming queue
    cmd = exec.Command("find", "/var/spool/postfix/incoming", "-type", "f")
    incomingOutput, _ := cmd.Output()
    info.IncomingSize = strings.Count(string(incomingOutput), "\n")

    info.Status = m.calculateStatus(info)
    m.processEmailStatus(info)
}

func (m *EmailMonitor) checkSendmail() {
    info := &EmailQueueInfo{
        MTA: "sendmail",
    }

    cmd := exec.Command("mailq")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    m.parseMailqOutput(lines, info)

    // Check sendmail queue directory
    queuePath := "/var/spool/mqueue"
    if _, err := os.Stat(queuePath); err == nil {
        cmd = exec.Command("find", queuePath, "-type", "f", "-name", "df*")
        dfOutput, _ := cmd.Output()
        info.QueueSize = strings.Count(string(dfOutput), "\n")
    }

    // Check deferred queue
    deferredPath := "/var/spool/mqueue-client"
    if _, err := os.Stat(deferredPath); err == nil {
        cmd = exec.Command("find", deferredPath, "-type", "f")
        defOutput, _ := cmd.Output()
        info.DeferredSize = strings.Count(string(defOutput), "\n")
    }

    info.Status = m.calculateStatus(info)
    m.processEmailStatus(info)
}

func (m *EmailMonitor) checkExim() {
    info := &EmailQueueInfo{
        MTA: "exim",
    }

    cmd := exec.Command("exim", "-bpc")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    info.QueueSize, _ = strconv.Atoi(strings.TrimSpace(string(output)))

    // Get frozen messages
    cmd = exec.Command("exim", "-bpr", "|", "grep", "-c", "frozen")
    frozenOutput, err := cmd.Output()
    if err == nil {
        info.DeferredSize, _ = strconv.Atoi(strings.TrimSpace(string(frozenOutput)))
    }

    info.Status = m.calculateStatus(info)
    m.processEmailStatus(info)
}

func (m *EmailMonitor) parseMailqOutput(lines []string, info *EmailQueueInfo) {
    inQueueSection := false
    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.Contains(line, "--") && strings.Contains(line, "Kbytes") {
            inQueueSection = true
            continue
        }

        if inQueueSection && line != "" {
            // Count queue entries (lines with timestamps)
            if strings.Contains(line, ":") {
                info.QueueSize++
            }

            // Look for bounce indicators
            if strings.Contains(strings.ToLower(line), "bounce") ||
               strings.Contains(strings.ToLower(line), "returned") {
                info.BouncedSize++
            }
        }
    }
}

func (m *EmailMonitor) calculateStatus(info *EmailQueueInfo) string {
    totalQueue := info.QueueSize + info.DeferredSize
    if totalQueue >= m.config.QueueThreshold {
        return "critical"
    }
    if totalQueue >= m.config.QueueThreshold/2 {
        return "warning"
    }
    return "healthy"
}

func (m *EmailMonitor) processEmailStatus(info *EmailQueueInfo) {
    lastInfo := m.emailState[info.MTA]

    if lastInfo == nil {
        m.emailState[info.MTA] = info
        return
    }

    // Check for queue buildup
    if info.QueueSize > m.config.QueueThreshold && lastInfo.QueueSize <= m.config.QueueThreshold {
        if m.config.SoundOnQueueHigh && m.shouldAlert(info.MTA+"queue", 10*time.Minute) {
            m.onQueueHigh(info)
        }
    }

    // Check for queue cleared
    if info.QueueSize < m.config.QueueThreshold/2 && lastInfo.QueueSize >= m.config.QueueThreshold {
        if m.config.SoundOnQueueClear {
            m.onQueueCleared(info)
        }
    }

    // Check for bounces
    if info.BouncedSize > lastInfo.BouncedSize {
        if m.config.SoundOnBounce && m.shouldAlert(info.MTA+"bounce", 5*time.Minute) {
            m.onBounce(info)
        }
    }

    m.emailState[info.MTA] = info
}

func (m *EmailMonitor) onQueueHigh(info *EmailQueueInfo) {
    sound := m.config.Sounds["queue_high"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *EmailMonitor) onQueueCleared(info *EmailQueueInfo) {
    sound := m.config.Sounds["queue_clear"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *EmailMonitor) onBounce(info *EmailQueueInfo) {
    sound := m.config.Sounds["bounce"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *EmailMonitor) onDeferral(info *EmailQueueInfo) {
    sound := m.config.Sounds["deferral"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *EmailMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| mailq | System Tool | Free | Mail queue viewer |
| postqueue | System Tool | Free | Postfix queue |
| find | System Tool | Free | File search |

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
| macOS | Supported | Uses mailq, postqueue |
| Linux | Supported | Uses mailq, postqueue, exim |
