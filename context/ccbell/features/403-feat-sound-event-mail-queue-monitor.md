# Feature: Sound Event Mail Queue Monitor

Play sounds for mail queue buildup, delivery failures, and spam detection.

## Summary

Monitor mail queues for message backlog, bounce messages, and delivery errors, playing sounds for mail events.

## Motivation

- Mail system awareness
- Queue backlog alerts
- Delivery failure detection
- Spam monitoring
- MTA health tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Mail Queue Events

| Event | Description | Example |
|-------|-------------|---------|
| Queue Buildup | Messages queued | > 100 |
| Delivery Failed | Bounce generated | 550 error |
| Message Bounced | Return to sender | invalid user |
| Spam Detected | High spam score | flagged |
| Relay Blocked | Connection refused | 554 denied |
| Queue Cleared | Messages sent | drain complete |

### Configuration

```go
type MailQueueMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchQueues       []string          `json:"watch_queues"` // "incoming", "active", "*"
    MTA               string            `json:"mta"` // "postfix", "sendmail", "exim", "auto"
    QueueThreshold    int               `json:"queue_threshold"` // 100 default
    SoundOnBuildup    bool              `json:"sound_on_buildup"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnCleared    bool              `json:"sound_on_cleared"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 120 default
}
```

### Commands

```bash
/ccbell:mailq status                   # Show mail queue status
/ccbell:mailq threshold 100            # Set queue threshold
/ccbell:mailq sound buildup <sound>
/ccbell:mailq sound fail <sound>
/ccbell:mailq test                     # Test mail sounds
```

### Output

```
$ ccbell:mailq status

=== Sound Event Mail Queue Monitor ===

Status: Enabled
MTA: Postfix
Queue Threshold: 100
Buildup Sounds: Yes
Fail Sounds: Yes

Mail Queue Status:

[1] incoming (Postfix)
    Messages: 45
    Size: 2.5 MB
    Oldest: 10 min
    Sound: bundled:mailq-incoming

[2] active (Postfix)
    Messages: 3
    Size: 150 KB
    Oldest: 2 min
    Sound: bundled:mailq-active

[3] deferred (Postfix)
    Messages: 25
    Size: 1.2 MB
    Oldest: 1 hour
    Sound: bundled:mailq-deferred *** WARNING ***

Queue Statistics:
  Total Messages: 73
  Size: 3.85 MB
  Oldest: 1 hour

Recent Events:
  [1] deferred: Queue Buildup (5 min ago)
       25 > 10 threshold
  [2] incoming: Message Bounced (1 hour ago)
       User not found
  [3] active: Queue Cleared (2 hours ago)
       All messages delivered

Mail Log Summary:
  Delivered Today: 500
  Bounced Today: 12
  Rejected Today: 5

Sound Settings:
  Buildup: bundled:mailq-buildup
  Fail: bundled:mailq-fail
  Cleared: bundled:mailq-cleared

[Configure] [Test All]
```

---

## Audio Player Compatibility

Mail queue monitoring doesn't play sounds directly:
- Monitoring feature using mailq/postqueue
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Mail Queue Monitor

```go
type MailQueueMonitor struct {
    config          *MailQueueMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    queueState      map[string]*MailQueueInfo
    lastEventTime   map[string]time.Time
}

type MailQueueInfo struct {
    Name       string
    Messages   int
    Size       int64 // bytes
    Oldest     time.Duration
    LastCheck  time.Time
}

func (m *MailQueueMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.queueState = make(map[string]*MailQueueInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *MailQueueMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Detect MTA
    m.detectMTA()

    for {
        select {
        case <-ticker.C:
            m.checkQueues()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MailQueueMonitor) detectMTA() {
    if m.config.MTA != "auto" {
        return
    }

    // Check for Postfix
    cmd := exec.Command("which", "postqueue")
    if cmd.Run() == nil {
        m.config.MTA = "postfix"
        return
    }

    // Check for Sendmail
    cmd = exec.Command("which", "sendmail")
    if cmd.Run() == nil {
        m.config.MTA = "sendmail"
        return
    }

    // Check for Exim
    cmd = exec.Command("which", "exim")
    if cmd.Run() == nil {
        m.config.MTA = "exim"
        return
    }
}

func (m *MailQueueMonitor) checkQueues() {
    switch m.config.MTA {
    case "postfix":
        m.checkPostfixQueues()
    case "sendmail":
        m.checkSendmailQueues()
    case "exim":
        m.checkEximQueues()
    }
}

func (m *MailQueueMonitor) checkPostfixQueues() {
    queues := []string{"incoming", "active", "deferred", "hold"}

    for _, queue := range queues {
        info := &MailQueueInfo{
            Name:      queue,
            LastCheck: time.Now(),
        }

        cmd := exec.Command("postqueue", "-p", "-q", queue)
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "mail queue") {
                // Parse: "incoming queue - 45 messages"
                re := regexp.MustEach(`(\d+) messages?`)
                matches := re.FindAllStringSubmatch(line, -1)
                if len(matches) > 0 {
                    info.Messages, _ = strconv.Atoi(matches[0][1])
                }
                break
            }
        }

        m.processQueueStatus(queue, info)
    }
}

func (m *MailQueueMonitor) checkSendmailQueues() {
    cmd := exec.Command("mailq")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse mailq output
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Mqueue") {
            // Total queue
            re := regexp.MustEach(`total size (\d+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                size, _ := strconv.ParseInt(matches[0][1], 10, 64)
                info := &MailQueueInfo{
                    Name:      "mqueue",
                    Messages:  0, // Would need to count
                    Size:      size * 1024,
                    LastCheck: time.Now(),
                }
                m.processQueueStatus("mqueue", info)
            }
            break
        }
    }
}

func (m *MailQueueMonitor) checkEximQueues() {
    cmd := exec.Command("exim", "-bp")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    count := 0
    for _, line := range lines {
        if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
            continue
        }
        if strings.TrimSpace(line) != "" && !strings.Contains(line, "Message log") {
            count++
        }
    }

    info := &MailQueueInfo{
        Name:      "exim",
        Messages:  count,
        LastCheck: time.Now(),
    }

    m.processQueueStatus("exim", info)
}

func (m *MailQueueMonitor) processQueueStatus(queue string, info *MailQueueInfo) {
    lastInfo := m.queueState[queue]

    if lastInfo == nil {
        m.queueState[queue] = info
        return
    }

    // Check for queue buildup
    if info.Messages >= m.config.QueueThreshold {
        if lastInfo.Messages < m.config.QueueThreshold {
            if m.config.SoundOnBuildup {
                m.onQueueBuildup(queue, info)
            }
        }
    } else if lastInfo.Messages >= m.config.QueueThreshold && info.Messages < m.config.QueueThreshold {
        if m.config.SoundOnCleared {
            m.onQueueCleared(queue, info)
        }
    }

    m.queueState[queue] = info
}

func (m *MailQueueMonitor) onQueueBuildup(queue string, info *MailQueueInfo) {
    key := fmt.Sprintf("buildup:%s", queue)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["buildup"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *MailQueueMonitor) onQueueCleared(queue string, info *MailQueueInfo) {
    if !m.config.SoundOnCleared {
        return
    }

    key := fmt.Sprintf("cleared:%s", queue)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["cleared"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *MailQueueMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| postqueue | System Tool | Free | Postfix queue |
| mailq | System Tool | Free | Sendmail queue |
| exim | System Tool | Free | Exim queue |

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
| macOS | Supported | Uses mailq (if installed) |
| Linux | Supported | Uses postqueue, mailq, exim |
