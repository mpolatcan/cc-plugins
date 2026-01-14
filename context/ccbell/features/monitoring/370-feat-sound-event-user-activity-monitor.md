# Feature: Sound Event User Activity Monitor

Play sounds for user activity events, command executions, and session activities.

## Summary

Monitor user activities, command executions, and session events, playing sounds for activity events.

## Motivation

- User activity awareness
- Command tracking
- Session monitoring
- Activity alerts
- Audit trail feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### User Activity Events

| Event | Description | Example |
|-------|-------------|---------|
| Command Executed | User ran command | apt update |
| Sudo Used | Sudo command executed | sudo systemctl |
| File Accessed | Important file accessed | /etc/passwd |
| Screen Locked | Session locked | Screen locked |
| Screen Unlocked | Session unlocked | User returned |
| Session Timeout | Session timed out | Idle timeout |

### Configuration

```go
type UserActivityMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchUsers        []string          `json:"watch_users"` // "root", "admin", "*"
    WatchCommands     []string          `json:"watch_commands"` // "sudo", "rm", "chmod"
    WatchPaths        []string          `json:"watch_paths"` // "/etc", "/root"
    SoundOnCommand    bool              `json:"sound_on_command"]
    SoundOnSudo       bool              `json:"sound_on_sudo"]
    SoundOnAccess     bool              `json:"sound_on_access"]
    SoundOnLock       bool              `json:"sound_on_lock"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type UserActivityEvent struct {
    User      string
    TTY       string
    PID       int
    Command   string
    Path      string
    Activity  string // "login", "command", "sudo", "file_access", "lock"
    EventType string // "login", "command", "sudo", "access", "lock", "unlock"
}
```

### Commands

```bash
/ccbell:activity status               # Show activity status
/ccbell:activity add root             # Add user to watch
/ccbell:activity remove root
/ccbell:activity sound sudo <sound>
/ccbell:activity sound command <sound>
/ccbell:activity test                 # Test activity sounds
```

### Output

```
$ ccbell:activity status

=== Sound Event User Activity Monitor ===

Status: Enabled
Command Sounds: Yes
Sudo Sounds: Yes
File Access Sounds: Yes

Watched Users: 2
Watched Commands: 3
Watched Paths: 2

Recent Activities:

[1] root (tty1): Command (5 min ago)
       Command: apt update && apt upgrade
       Sound: bundled:activity-sudo

[2] admin (pts/0): Sudo (10 min ago)
       Command: systemctl restart nginx
       Sound: bundled:activity-sudo

[3] root (tty1): File Access (1 hour ago)
       Path: /etc/nginx/nginx.conf
       Action: modified
       Sound: bundled:activity-access

[4] admin (SSH): Session Locked (2 hours ago)
       TTY: pts/1
       Sound: bundled:activity-lock

Activity Statistics:
  Commands Today: 45
  Sudo Commands: 12
  File Access: 28

Sound Settings:
  Command: bundled:activity-command
  Sudo: bundled:activity-sudo
  Access: bundled:activity-access
  Lock: bundled:activity-lock

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

User activity monitoring doesn't play sounds directly:
- Monitoring feature using auditd/who
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### User Activity Monitor

```go
type UserActivityMonitor struct {
    config          *UserActivityMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    activityState   map[string]*ActivityInfo
    lastEventTime   map[string]time.Time
}

type ActivityInfo struct {
    User      string
    TTY       string
    PID       int
    Command   string
    Path      string
    Time      time.Time
}

func (m *UserActivityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activityState = make(map[string]*ActivityInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *UserActivityMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotActivity()

    for {
        select {
        case <-ticker.C:
            m.checkActivity()
        case <-m.stopCh:
            return
        }
    }
}

func (m *UserActivityMonitor) snapshotActivity() {
    m.checkActivity()
}

func (m *UserActivityMonitor) checkActivity() {
    // Check active sessions
    m.checkActiveSessions()

    // Check recent commands from history
    m.checkCommandHistory()

    // Check audit logs
    m.checkAuditLogs()
}

func (m *UserActivityMonitor) checkActiveSessions() {
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 5 {
            continue
        }

        user := parts[0]
        tty := parts[1]

        if !m.shouldWatchUser(user) {
            continue
        }

        key := fmt.Sprintf("%s:%s", user, tty)
        if _, exists := m.activityState[key]; !exists {
            m.activityState[key] = &ActivityInfo{
                User: user,
                TTY:  tty,
                Time: time.Now(),
            }
            m.onUserLoggedIn(user, tty)
        }
    }
}

func (m *UserActivityMonitor) checkCommandHistory() {
    for _, user := range m.config.WatchUsers {
        if user == "*" {
            continue
        }

        homeDir := fmt.Sprintf("/home/%s", user)
        if user == "root" {
            homeDir = "/root"
        }

        histPath := filepath.Join(homeDir, ".bash_history")
        data, err := os.ReadFile(histPath)
        if err != nil {
            continue
        }

        lines := strings.Split(string(data), "\n")
        for _, line := range lines {
            line = strings.TrimSpace(line)
            if line == "" {
                continue
            }

            cmd := strings.Fields(line)[0]
            if m.shouldWatchCommand(cmd) {
                m.onCommandExecuted(user, cmd)
            }
        }
    }
}

func (m *UserActivityMonitor) checkAuditLogs() {
    if _, err := os.Stat("/var/log/audit/audit.log"); err != nil {
        return
    }

    cmd := exec.Command("tail", "-50", "/var/log/audit/audit.log")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseAuditLog(string(output))
}

func (m *UserActivityMonitor) parseAuditLog(output string) {
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "SYSCALL") {
            // Parse audit entry
            re := regexp.MustCompile(`auid=(\d+) uid=(\d+) gid=(\d+) ses=(\d+)`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                // Process audit entry
            }
        }

        if strings.Contains(line, "PROCTITLE") {
            // Get command
            re := regexp.MustCompile(`proctitle=(.+)`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                cmd := strings.Fields(match[1])[0]
                if m.shouldWatchCommand(cmd) {
                    m.onCommandExecuted("unknown", cmd)
                }
            }
        }
    }
}

func (m *UserActivityMonitor) shouldWatchUser(user string) bool {
    if len(m.config.WatchUsers) == 0 {
        return true
    }

    for _, u := range m.config.WatchUsers {
        if u == "*" || u == user {
            return true
        }
    }

    return false
}

func (m *UserActivityMonitor) shouldWatchCommand(cmd string) bool {
    if len(m.config.WatchCommands) == 0 {
        return false
    }

    for _, c := range m.config.WatchCommands {
        if c == cmd || (c == "sudo" && cmd == "sudo") {
            return true
        }
    }

    return false
}

func (m *UserActivityMonitor) shouldWatchPath(path string) bool {
    for _, p := range m.config.WatchPaths {
        if strings.HasPrefix(path, p) {
            return true
        }
    }

    return false
}

func (m *UserActivityMonitor) onUserLoggedIn(user string, tty string) {
    // Optional: sound on login
}

func (m *UserActivityMonitor) onCommandExecuted(user string, cmd string) {
    if !m.config.SoundOnCommand {
        return
    }

    if cmd == "sudo" || m.isSudoCommand(cmd) {
        if !m.config.SoundOnSudo {
            return
        }
        m.onSudoCommand(user, cmd)
        return
    }

    key := fmt.Sprintf("command:%s:%s", user, cmd)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["command"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserActivityMonitor) isSudoCommand(cmd string) bool {
    return cmd == "sudo" || strings.HasPrefix(cmd, "sudo ")
}

func (m *UserActivityMonitor) onSudoCommand(user string, cmd string) {
    key := fmt.Sprintf("sudo:%s", user)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["sudo"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *UserActivityMonitor) onFileAccessed(user string, path string) {
    if !m.config.SoundOnAccess {
        return
    }

    if !m.shouldWatchPath(path) {
        return
    }

    key := fmt.Sprintf("access:%s:%s", user, path)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["access"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserActivityMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| who | System Tool | Free | Session listing |
| auditd | System Service | Free | Audit logging |
| ~/.bash_history | File | Free | Command history |

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
| macOS | Supported | Uses who, bash_history |
| Linux | Supported | Uses who, auditd, bash_history |
