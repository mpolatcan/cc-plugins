# Feature: Sound Event Activity Log Monitor

Play sounds for user activity and command history events.

## Summary

Monitor user activity, command history, and session events, playing sounds for significant activity events.

## Motivation

- Activity awareness
- Session change detection
- User login feedback
- Activity summary alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Activity Log Events

| Event | Description | Example |
|-------|-------------|---------|
| Login | User logged in | SSH connection |
| Logout | User logged out | Session ended |
| Sudo | Elevated privilege | sudo command |
| New Session | New terminal opened | New tab |
| Command Run | Long command executed | make build |

### Configuration

```go
type ActivityLogMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchUsers     []string          `json:"watch_users"` // User names
    WatchCommands  []string          `json:"watch_commands"` // Commands
    SoundOnLogin   bool              `json:"sound_on_login"`
    SoundOnLogout  bool              `json:"sound_on_logout"`
    SoundOnSudo    bool              `json:"sound_on_sudo"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 30 default
}

type ActivityLogEvent struct {
    UserName   string
    EventType  string // "login", "logout", "sudo", "session", "command"
    Command    string
    SessionID  string
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:activity status           # Show activity status
/ccbell:activity add user         # Add user to watch
/ccbell:activity login on         # Enable login sounds
/ccbell:activity sound login <sound>
/ccbell:activity sound sudo <sound>
/ccbell:activity test             # Test activity sounds
```

### Output

```
$ ccbell:activity status

=== Sound Event Activity Log Monitor ===

Status: Enabled
Login Sounds: Yes
Logout Sounds: Yes

Current Activity:
  Active Users: 2
  Active Sessions: 5
  Last Activity: 2 min ago

Recent Events:
  [1] user: sudo command (2 min ago)
       "sudo vim /etc/nginx/nginx.conf"
  [2] user: Login (5 min ago)
       SSH from 192.168.1.100
  [3] user: New session (10 min ago)
       iTerm2 tab opened

Watched Users: 2
  user, admin

Recent History:
  Today: 45 activities
  This Week: 312 activities

Sound Settings:
  Login: bundled:stop
  Logout: bundled:stop
  Sudo: bundled:stop

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

Activity log monitoring doesn't play sounds directly:
- Monitoring feature using log parsing
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Activity Log Monitor

```go
type ActivityLogMonitor struct {
    config       *ActivityLogMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastEvents   map[string]time.Time
}

func (m *ActivityLogMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEvents = make(map[string]time.Time)
    go m.monitor()
}

func (m *ActivityLogMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkActivity()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ActivityLogMonitor) checkActivity() {
    events := m.parseActivityLog()

    for _, event := range events {
        if m.shouldProcess(event) {
            m.onActivity(event)
        }
    }
}

func (m *ActivityLogMonitor) parseActivityLog() []*ActivityLogEvent {
    var events []*ActivityLogEvent

    // Read system log for user activity
    logPaths := []string{
        "/var/log/system.log",
        "/var/log/auth.log",
        "/var/log/secure",
    }

    var logData []byte
    for _, path := range logPaths {
        if data, err := os.ReadFile(path); err == nil {
            logData = data
            break
        }
    }

    if logData == nil {
        return events
    }

    lines := strings.Split(string(logData), "\n")
    for _, line := range lines {
        event := m.parseActivityLine(line)
        if event != nil {
            events = append(events, event)
        }
    }

    return events
}

func (m *ActivityLogMonitor) parseActivityLine(line string) *ActivityLogEvent {
    event := &ActivityLogEvent{
        Timestamp: time.Now(),
    }

    // Check for login events
    if strings.Contains(line, "sshd") && strings.Contains(line, "Accepted") {
        event.EventType = "login"
        event.UserName = m.extractUser(line)
        return event
    }

    // Check for logout events
    if strings.Contains(line, "sshd") && strings.Contains(line, "Closed") {
        event.EventType = "logout"
        return event
    }

    // Check for sudo events
    if strings.Contains(line, "sudo:") && strings.Contains(line, "COMMAND") {
        event.EventType = "sudo"
        event.Command = m.extractCommand(line)
        event.UserName = m.extractUser(line)
        return event
    }

    // Check for new session
    if strings.Contains(line, "session") && strings.Contains(line, "opened") {
        event.EventType = "session"
        return event
    }

    return nil
}

func (m *ActivityLogMonitor) extractUser(line string) string {
    // Try to extract username from log line
    patterns := []string{
        `for (\w+) from`,
        `user (\w+)`,
        `by (\w+)`,
    }

    for _, pattern := range patterns {
        re := regexp.MustCompile(pattern)
        match := re.FindStringSubmatch(line)
        if len(match) >= 2 {
            return match[1]
        }
    }

    return "unknown"
}

func (m *ActivityLogMonitor) extractCommand(line string) string {
    // Try to extract command from sudo line
    re := regexp.MustCompile(`COMMAND=(.+)`)
    match := re.FindStringSubmatch(line)
    if len(match) >= 2 {
        return match[1]
    }

    return ""
}

func (m *ActivityLogMonitor) shouldProcess(event *ActivityLogEvent) bool {
    // Check user filter
    if len(m.config.WatchUsers) > 0 {
        found := false
        for _, user := range m.config.WatchUsers {
            if event.UserName == user {
                found = true
                break
            }
        }
        if !found {
            return false
        }
    }

    // Check command filter
    if len(m.config.WatchCommands) > 0 && event.Command != "" {
        found := false
        for _, cmd := range m.config.WatchCommands {
            if strings.Contains(event.Command, cmd) {
                found = true
                break
            }
        }
        if !found {
            return false
        }
    }

    // Debounce: don't repeat same event within 5 seconds
    key := event.EventType + ":" + event.UserName
    if lastTime := m.lastEvents[key]; lastTime.Add(5 * time.Second).After(time.Now()) {
        return false
    }

    return true
}

func (m *ActivityLogMonitor) onActivity(event *ActivityLogEvent) {
    key := event.EventType + ":" + event.UserName
    m.lastEvents[key] = time.Now()

    switch event.EventType {
    case "login":
        m.onLogin(event)
    case "logout":
        m.onLogout(event)
    case "sudo":
        m.onSudo(event)
    case "session":
        m.onNewSession(event)
    }
}

func (m *ActivityLogMonitor) onLogin(event *ActivityLogEvent) {
    if !m.config.SoundOnLogin {
        return
    }

    sound := m.config.Sounds["login"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ActivityLogMonitor) onLogout(event *ActivityLogEvent) {
    if !m.config.SoundOnLogout {
        return
    }

    sound := m.config.Sounds["logout"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ActivityLogMonitor) onSudo(event *ActivityLogEvent) {
    if !m.config.SoundOnSudo {
        return
    }

    sound := m.config.Sounds["sudo"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *ActivityLogMonitor) onNewSession(event *ActivityLogEvent) {
    sound := m.config.Sounds["session"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /var/log/auth.log | File | Free | Authentication logging |
| /var/log/secure | File | Free | Security logging |
| /var/log/system.log | File | Free | System logging |

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
| macOS | Supported | Uses system.log |
| Linux | Supported | Uses auth.log/secure |
| Windows | Not Supported | ccbell only supports macOS/Linux |
