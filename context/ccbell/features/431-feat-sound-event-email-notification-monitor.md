# Feature: Sound Event Email Notification Monitor

Play sounds for new email arrivals, unread count changes, and email server events.

## Summary

Monitor email accounts for new messages, unread count changes, and notification events, playing sounds for email events.

## Motivation

- Email awareness
- New message alerts
- Priority detection
- Unread tracking
- Communication feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Email Notification Events

| Event | Description | Example |
|-------|-------------|---------|
| New Email | New message received | Inbox |
| Unread High | Unread > threshold | > 50 |
| Mail Sent | Message sent | Sent |
| Mailbox Full | Storage full | 95% |
| Server Error | IMAP/SMTP error | Connection lost |
| Calendar Invite | Meeting request | Event |

### Configuration

```go
type EmailNotificationMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchAccounts     []string          `json:"watch_accounts"` // "user@gmail.com", "*"
    CheckInterval     int               `json:"check_interval_sec"` // 60 default
    UnreadWarning     int               `json:"unread_warning"` // 50 default
    SoundOnNewEmail   bool              `json:"sound_on_new_email"`
    SoundOnUnreadHigh bool              `json:"sound_on_unread_high"`
    SoundOnSent       bool              `json:"sound_on_sent"`
    Sounds            map[string]string `json:"sounds"`
}
```

### Commands

```bash
/ccbell:email status                 # Show email status
/ccbell:email add user@gmail.com     # Add account to watch
/ccbell:email warning 50             # Set unread warning
/ccbell:email sound new <sound>
/ccbell:email test                   # Test email sounds
```

### Output

```
$ ccbell:email status

=== Sound Event Email Notification Monitor ===

Status: Enabled
Check Interval: 60s
Unread Warning: 50

Email Accounts:

[1] user@gmail.com (Gmail)
    Status: CONNECTED
    Unread: 12
    Total: 5,432
    Storage: 68%
    Last Check: 1 min ago
    Sound: bundled:email-gmail

[2] user@company.com (IMAP)
    Status: CONNECTED
    Unread: 3
    Total: 1,250
    Storage: 45%
    Last Check: 1 min ago
    Sound: bundled:email-work

[3] user@icloud.com (IMAP)
    Status: CONNECTED
    Unread: 0
    Total: 892
    Storage: 72%
    Last Check: 1 min ago
    Sound: bundled:email-icloud

Recent Email Events:
  [1] user@gmail.com: New Email (5 min ago)
       Subject: Meeting agenda
       From: colleague
       Sound: bundled:email-new
  [2] user@company.com: New Email (1 hour ago)
       Subject: Weekly report
       From: manager
       Sound: bundled:email-new
  [3] user@gmail.com: Unread High Warning (2 hours ago)
       52 unread messages
       Sound: bundled:email-warning

Email Statistics:
  Accounts: 3
  Total Unread: 15
  New Today: 8
  Sent Today: 12

Sound Settings:
  New Email: bundled:email-new
  Unread High: bundled:email-warning
  Sent: bundled:email-sent
  Server Error: bundled:email-error

[Configure] [Add Account] [Test All]
```

---

## Audio Player Compatibility

Email monitoring doesn't play sounds directly:
- Monitoring feature using mail command or msmtp
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Email Notification Monitor

```go
type EmailNotificationMonitor struct {
    config          *EmailNotificationMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    accountState    map[string]*EmailAccountInfo
    lastEventTime   map[string]time.Time
}

type EmailAccountInfo struct {
    Name          string
    Email         string
    Status        string // "connected", "disconnected", "error"
    UnreadCount   int
    TotalCount    int
    StorageUsed   float64
    LastCheck     time.Time
    LastUnread    int
}

func (m *EmailNotificationMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.accountState = make(map[string]*EmailAccountInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *EmailNotificationMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.checkEmailAccounts()

    for {
        select {
        case <-ticker.C:
            m.checkEmailAccounts()
        case <-m.stopCh:
            return
        }
    }
}

func (m *EmailNotificationMonitor) checkEmailAccounts() {
    for _, account := range m.config.WatchAccounts {
        info := m.checkAccount(account)
        if info != nil {
            m.processAccountStatus(info)
        }
    }
}

func (m *EmailNotificationMonitor) checkAccount(account string) *EmailAccountInfo {
    info := &EmailAccountInfo{
        Email:     account,
        Name:      m.extractName(account),
        LastCheck: time.Now(),
    }

    // Try mail command first
    cmd := exec.Command("mail", "-u", account, "-H")
    output, err := cmd.Output()

    if err == nil {
        // Parse mail output
        outputStr := string(output)
        info = m.parseMailOutput(info, outputStr)
        return info
    }

    // Try msmtp for sent messages
    cmd = exec.Command("msmtp", "--version")
    if err := cmd.Run(); err == nil {
        // msmtp is available but doesn't provide inbox checking
        info.Status = "unknown"
        return info
    }

    // Try to use imap command for email checking
    info = m.checkViaIMAP(info)

    return info
}

func (m *EmailNotificationMonitor) parseMailOutput(info *EmailAccountInfo, output string) *EmailAccountInfo {
    lines := strings.Split(output, "\n")

    for _, line := range lines {
        // Look for inbox status
        if strings.Contains(line, "Inbox") {
            // Parse: "Inbox      12/5323   12   0"
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                // Try to parse unread
                for i, part := range parts {
                    if n, err := strconv.Atoi(part); err == nil {
                        if i+1 < len(parts) {
                            next, _ := strconv.Atoi(parts[i+1])
                            info.UnreadCount = n
                            info.TotalCount = next
                            break
                        }
                    }
                }
            }
            info.Status = "connected"
            break
        }
    }

    // Check for error states
    if strings.Contains(output, "NO") || strings.Contains(output, "ERROR") {
        info.Status = "error"
    } else if info.UnreadCount > 0 {
        info.Status = "connected"
    }

    return info
}

func (m *EmailNotificationMonitor) checkViaIMAP(info *EmailAccountInfo) *EmailAccountInfo {
    // For accounts that support it, use curl with IMAP
    // This is a simplified example - real implementation would need
    // proper authentication

    // Try to check using a simple connection test
    cmd := exec.Command("nc", "-z", "localhost", "143")
    err := cmd.Run()

    if err == nil {
        info.Status = "connected"
    } else {
        info.Status = "disconnected"
    }

    return info
}

func (m *EmailNotificationMonitor) extractName(email string) string {
    // Extract name from email address
    parts := strings.Split(email, "@")
    if len(parts) >= 1 {
        return parts[0]
    }
    return email
}

func (m *EmailNotificationMonitor) processAccountStatus(info *EmailAccountInfo) {
    lastInfo := m.accountState[info.Email]

    if lastInfo == nil {
        m.accountState[info.Email] = info
        return
    }

    // Check for new emails
    if info.UnreadCount > lastInfo.UnreadCount {
        newEmails := info.UnreadCount - lastInfo.UnreadCount
        if newEmails > 0 && m.config.SoundOnNewEmail {
            m.onNewEmail(info, newEmails)
        }
    }

    // Check for unread warning
    if info.UnreadCount >= m.config.UnreadWarning &&
       lastInfo.UnreadCount < m.config.UnreadWarning {
        if m.config.SoundOnUnreadHigh {
            m.onUnreadHigh(info)
        }
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        if info.Status == "error" || info.Status == "disconnected" {
            // Connection lost
        }
    }

    m.accountState[info.Email] = info
}

func (m *EmailNotificationMonitor) onNewEmail(info *EmailAccountInfo, count int) {
    key := fmt.Sprintf("new:%s", info.Email)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["new_email"]
        if sound != "" {
            volume := 0.3
            if count > 1 {
                volume = 0.4
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *EmailNotificationMonitor) onUnreadHigh(info *EmailAccountInfo) {
    key := fmt.Sprintf("warning:%s", info.Email)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["unread_high"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *EmailNotificationMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| mail | System Tool | Free | Mail command (mailx) |
| msmtp | System Tool | Free | SMTP client |
| nc | System Tool | Free | Netcat (IMAP check) |

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
| macOS | Supported | Uses mail, msmtp |
| Linux | Supported | Uses mail, msmtp |
