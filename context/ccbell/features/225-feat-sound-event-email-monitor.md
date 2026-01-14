# Feature: Sound Event Email Monitor

Play sounds for email notifications and events.

## Summary

Monitor email accounts for new messages, unread counts, and important email alerts, playing sounds for email events.

## Motivation

- New message awareness
- Priority email alerts
- Unread count feedback
- Zero inbox celebration

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Email Events

| Event | Description | Example |
|-------|-------------|---------|
| New Email | New message received | Incoming mail |
| Unread High | Unread count high | > 50 unread |
| Priority Email | High priority message | From boss |
| Zero Inbox | All emails read | Inbox zero |
| Sender Blocked | Blocked sender email | Spam detected |
| Digest Ready | Periodic digest ready | Daily summary |

### Configuration

```go
type EmailMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    Accounts         []*EmailAccount  `json:"accounts"`
    NewEmailSound    string            `json:"new_email_sound"`
    PrioritySound    string            `json:"priority_sound"`
    UnreadThreshold  int               `json:"unread_threshold"` // 50 default
    CheckInterval    int               `json:"check_interval_sec"` // 60 default
    Sounds           map[string]string `json:"sounds"`
}

type EmailAccount struct {
    Name       string  `json:"name"`
    Type       string  `json:"type"` // "gmail", "imap", "outlook"
    Config     map[string]string `json:"config"` // Host, port, username
    Sound      string  `json:"sound"`
    LastUnread int     `json:"last_unread"`
}

type EmailEvent struct {
    Account    string
    Subject    string
    From       string
    Priority   string // "normal", "high", "urgent"
    UnreadCount int
}
```

### Commands

```bash
/ccbell:email status              # Show email status
/ccbell:email add gmail --user user@gmail.com
/ccbell:email add imap --host mail.example.com
/ccbell:email remove "Work Email"
/ccbell:email threshold 100       # Set unread threshold
/ccbell:email sound new <sound>
/ccbell:email sound priority <sound>
/ccbell:email test                # Test email sounds
```

### Output

```
$ ccbell:email status

=== Sound Event Email Monitor ===

Status: Enabled
Check Interval: 60s
Unread Threshold: 50

Monitored Accounts: 2

[1] Personal (Gmail)
    Unread: 12
    Last Check: 2 min ago
    Status: Connected
    Sound: bundled:stop
    [Edit] [Remove]

[2] Work (Outlook)
    Unread: 3
    Last Check: 2 min ago
    Status: Connected
    Sound: bundled:stop
    [Edit] [Remove]

Total Unread: 15

Recent Events:
  [1] Work: New email from manager (10 min ago)
       Subject: "Project Update"
       Priority: High
  [2] Personal: Unread count dropped to 0 (1 hour ago)
       Status: INBOX ZERO!
  [3] Work: New email from team (2 hours ago)

[Configure] [Add Account] [Test All]
```

---

## Audio Player Compatibility

Email monitoring doesn't play sounds directly:
- Monitoring feature using email protocols
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Email Monitor

```go
type EmailMonitor struct {
    config        *EmailMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastUnread    map[string]int
    lastEmailTime map[string]time.Time
}

func (m *EmailMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastUnread = make(map[string]int)
    m.lastEmailTime = make(map[string]time.Time)

    // Initialize last unread counts
    for _, account := range m.config.Accounts {
        m.lastUnread[account.Name] = 0
        m.lastEmailTime[account.Name] = time.Now()
    }

    go m.monitor()
}

func (m *EmailMonitor) monitor() {
    interval := time.Duration(m.config.CheckInterval) * time.Second
    ticker := time.NewTicker(interval)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkEmails()
        case <-m.stopCh:
            return
        }
    }
}

func (m *EmailMonitor) checkEmails() {
    for _, account := range m.config.Accounts {
        status := m.checkAccount(account)
        m.evaluateAccount(account, status)
    }
}

func (m *EmailMonitor) checkAccount(account *EmailAccount) *EmailEvent {
    event := &EmailEvent{
        Account: account.Name,
    }

    switch account.Type {
    case "gmail":
        return m.checkGmail(account, event)
    case "imap":
        return m.checkIMAP(account, event)
    case "outlook":
        return m.checkOutlook(account, event)
    }

    return event
}

func (m *EmailMonitor) checkGmail(account *EmailAccount, event *EmailEvent) *EmailEvent {
    // Use Gmail API or IMAP
    username := account.Config["username"]
    password := account.Config["password"]

    // Connect via IMAP to Gmail
    server := "imap.gmail.com:993"
    tlsConfig := &tls.Config{}

    conn, err := tls.Dial("tcp", server, tlsConfig)
    if err != nil {
        return event
    }
    defer conn.Close()

    // Read greeting
    buf := bufio.NewReader(conn)
    _, _ = buf.ReadString('\n')

    // Login
    fmt.Fprintf(conn, "a001 LOGIN %s %s\r\n", username, password)
    response, _ := buf.ReadString('\n')

    if !strings.Contains(response, "a001 OK") {
        return event
    }

    // Select inbox
    fmt.Fprintf(conn, "a002 SELECT INBOX\r\n")
    response, _ = buf.ReadString('\n')

    // Parse unread count from response
    unreadMatch := regexp.MustCompile(`UNSEEN (\d+)`).FindStringSubmatch(response)
    if unreadMatch != nil {
        event.UnreadCount, _ = strconv.Atoi(unreadMatch[1])
    }

    // Get recent emails
    fmt.Fprintf(conn, "a003 FETCH 1:5 (FLAGS RFC822.SIZE)\r\n")
    response, _ = buf.ReadString('\n')

    // Check for recent email (within last check interval)
    if m.lastEmailTime[account.Name].Add(time.Duration(m.config.CheckInterval)*time.Second).Before(time.Now()) {
        // Look for recent emails
        fmt.Fprintf(conn, "a004 SEARCH UNSEEN SINCE %s\r\n",
            m.lastEmailTime[account.Name].Format("02-Jan-2006"))
        searchResult, _ := buf.ReadString('\n')

        if strings.Contains(searchResult, "a004 SEARCH") {
            event.Priority = "normal"
        }
    }

    // Logout
    fmt.Fprintf(conn, "a005 LOGOUT\r\n")

    return event
}

func (m *EmailMonitor) checkIMAP(account *EmailAccount, event *EmailEvent) *EmailEvent {
    host := account.Config["host"]
    port := account.Config["port"]
    if port == "" {
        port = "993"
    }
    username := account.Config["username"]
    password := account.Config["password"]

    server := host + ":" + port
    tlsConfig := &tls.Config{}

    conn, err := tls.Dial("tcp", server, tlsConfig)
    if err != nil {
        return event
    }
    defer conn.Close()

    // Similar IMAP logic as Gmail
    buf := bufio.NewReader(conn)
    _, _ = buf.ReadString('\n')

    fmt.Fprintf(conn, "a001 LOGIN %s %s\r\n", username, password)
    response, _ := buf.ReadString('\n')

    if !strings.Contains(response, "a001 OK") {
        return event
    }

    fmt.Fprintf(conn, "a002 SELECT INBOX\r\n")
    response, _ = buf.ReadString('\n')

    unreadMatch := regexp.MustCompile(`UNSEEN (\d+)`).FindStringSubmatch(response)
    if unreadMatch != nil {
        event.UnreadCount, _ = strconv.Atoi(unreadMatch[1])
    }

    fmt.Fprintf(conn, "a003 LOGOUT\r\n")

    return event
}

func (m *EmailMonitor) checkOutlook(account *EmailAccount, event *EmailEvent) *EmailEvent {
    // Microsoft Graph API for Outlook
    clientID := account.Config["client_id"]
    tenantID := account.Config["tenant_id"]

    if clientID == "" || tenantID == "" {
        return event
    }

    // Get access token
    tokenURL := fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenantID)
    values := url.Values{
        "client_id":     {clientID},
        "scope":         {"https://graph.microsoft.com/.default"},
        "client_secret": {account.Config["client_secret"]},
        "grant_type":    {"client_credentials"},
    }

    resp, err := http.PostForm(tokenURL, values)
    if err != nil {
        return event
    }
    defer resp.Body.Close()

    var tokenResp struct {
        AccessToken string `json:"access_token"`
    }

    if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
        return event
    }

    // Get unread count from Graph API
    graphURL := "https://graph.microsoft.com/v1.0/me/mailFolders/Inbox/messageCount"
    req, _ := http.NewRequest("GET", graphURL, nil)
    req.Header.Set("Authorization", "Bearer "+tokenResp.AccessToken)

    client := &http.Client{}
    resp, err = client.Do(req)
    if err != nil {
        return event
    }
    defer resp.Body.Close()

    var countResp struct {
        UnreadItemCount int `json:"unreadItemCount"`
    }

    if err := json.NewDecoder(resp.Body).Decode(&countResp); err == nil {
        event.UnreadCount = countResp.UnreadItemCount
    }

    return event
}

func (m *EmailMonitor) evaluateAccount(account *EmailAccount, event *EmailEvent) {
    lastUnread := m.lastUnread[account.Name]
    m.lastUnread[account.Name] = event.UnreadCount

    // Check for new email
    if event.UnreadCount > lastUnread && lastUnread > 0 {
        m.onNewEmail(account, event)
    }

    // Check unread threshold
    if event.UnreadCount >= m.config.UnreadThreshold &&
       lastUnread < m.config.UnreadThreshold {
        m.onUnreadThreshold(account, event)
    }

    // Check for inbox zero
    if event.UnreadCount == 0 && lastUnread > 0 {
        m.onInboxZero(account)
    }
}

func (m *EmailMonitor) onNewEmail(account *EmailAccount, event *EmailEvent) {
    sound := account.Sound
    if sound == "" {
        sound = m.config.Sounds["new"]
    }
    if sound == "" {
        sound = m.config.NewEmailSound
    }

    if event.Priority == "high" || event.Priority == "urgent" {
        altSound := m.config.Sounds["priority"]
        if altSound != "" {
            sound = altSound
        }
    }

    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *EmailMonitor) onUnreadThreshold(account *EmailAccount, event *EmailEvent) {
    sound := m.config.Sounds["threshold"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *EmailMonitor) onInboxZero(account *EmailAccount) {
    sound := m.config.Sounds["inbox_zero"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| IMAP/SMTP | Protocol | Free | Email protocol |
| TLS | Go Stdlib | Free | Encrypted connection |
| Microsoft Graph | API | Free | Outlook integration |

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
| macOS | Supported | Uses IMAP/TLS |
| Linux | Supported | Uses IMAP/TLS |
| Windows | Not Supported | ccbell only supports macOS/Linux |
