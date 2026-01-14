# Feature: Sound Event Terminal Session Monitor

Play sounds for terminal session opens/closes, background process completion, and shell events.

## Summary

Monitor terminal sessions, shell activities, and background process completions, playing sounds for terminal events.

## Motivation

- Session awareness
- Long-running task completion
- Terminal activity detection
- Background job notifications
- Shell event tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Terminal Session Events

| Event | Description | Example |
|-------|-------------|---------|
| Session Opened | New terminal opened | xterm, tmux |
| Session Closed | Terminal closed | logout |
| Background Done | Background job finished | make complete |
| Command Done | Long command finished | sleep 60 |
| Bell Triggered | Terminal bell | Ctrl+G |
| Tmux Activity | Pane activity | activity |

### Configuration

```go
type TerminalSessionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchTTYs         []string          `json:"watch_ttys"` // "pts/0", "*"
    WatchTmux         bool              `json:"watch_tmux"`
    WatchScreen       bool              `json:"watch_screen"`
    SoundOnOpen       bool              `json:"sound_on_open"`
    SoundOnClose      bool              `json:"sound_on_close"`
    SoundOnDone       bool              `json:"sound_on_done"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:term status                    # Show terminal status
/ccbell:term watch-tmux yes            # Enable tmux monitoring
/ccbell:term sound open <sound>
/ccbell:term sound close <sound>
/ccbell:term test                      # Test terminal sounds
```

### Output

```
$ ccbell:term status

=== Sound Event Terminal Session Monitor ===

Status: Enabled
Open Sounds: Yes
Close Sounds: Yes
Done Sounds: Yes

Active Sessions: 5

Terminal Sessions:

[1] pts/0 (admin)
    Started: 5 min ago
    Shell: /bin/bash
    Background Jobs: 2
    Sound: bundled:term-pts0

[2] pts/1 (root)
    Started: 1 hour ago
    Shell: /bin/zsh
    Background Jobs: 0
    Sound: bundled:term-pts1

[3] tmux:myproject (admin)
    Started: 2 hours ago
    Panes: 4
    Activity: 1
    Sound: bundled:term-tmux

Recent Events:
  [1] pts/0: Session Opened (5 min ago)
       Shell: bash
  [2] tmux:myproject: Activity (1 hour ago)
       Pane 2 had activity
  [3] pts/1: Session Closed (3 hours ago)
       Duration: 2h 30m

Session Statistics:
  Sessions Today: 15
  Opens: 12
  Closes: 10

Sound Settings:
  Open: bundled:term-open
  Close: bundled:term-close
  Done: bundled:term-done

[Configure] [Test All]
```

---

## Audio Player Compatibility

Terminal monitoring doesn't play sounds directly:
- Monitoring feature using who/script/tmux
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Terminal Session Monitor

```go
type TerminalSessionMonitor struct {
    config          *TerminalSessionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    sessionState    map[string]*SessionInfo
    lastEventTime   map[string]time.Time
}

type SessionInfo struct {
    TTY       string
    User      string
    Shell     string
    Started   time.Time
    PID       int
    Tmux      bool
}

func (m *TerminalSessionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sessionState = make(map[string]*SessionInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *TerminalSessionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSessionState()

    for {
        select {
        case <-ticker.C:
            m.checkSessionState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *TerminalSessionMonitor) snapshotSessionState() {
    // Get terminal sessions using 'who'
    m.getWhoSessions()

    // Get tmux sessions if enabled
    if m.config.WatchTmux {
        m.getTmuxSessions()
    }
}

func (m *TerminalSessionMonitor) checkSessionState() {
    currentSessions := m.getWhoSessions()

    // Check for new sessions
    for id, session := range currentSessions {
        if _, exists := m.sessionState[id]; !exists {
            m.sessionState[id] = session
            if m.shouldWatchTTY(session.TTY) {
                m.onSessionOpened(session)
            }
        }
    }

    // Check for closed sessions
    for id, lastSession := range m.sessionState {
        if _, exists := currentSessions[id]; !exists {
            delete(m.sessionState, id)
            if m.shouldWatchTTY(lastSession.TTY) {
                m.onSessionClosed(lastSession)
            }
        }
    }

    // Check tmux if enabled
    if m.config.WatchTmux {
        m.checkTmuxSessions()
    }
}

func (m *TerminalSessionMonitor) getWhoSessions() map[string]*SessionInfo {
    sessions := make(map[string]*SessionInfo)

    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return sessions
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) >= 5 {
            user := parts[0]
            tty := parts[1]
            date := parts[2]
            timeStr := parts[3]
            origin := parts[4]

            id := fmt.Sprintf("%s-%s", user, tty)

            sessions[id] = &SessionInfo{
                TTY:     tty,
                User:    user,
                Shell:   m.getShellForUser(user),
                Started: m.parseTime(date, timeStr),
            }
        }
    }

    return sessions
}

func (m *TerminalSessionMonitor) getTmuxSessions() {
    cmd := exec.Command("tmux", "list-sessions", "-F", "#{session_name}: #{session panes}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        parts := strings.SplitN(line, ":", 2)
        if len(parts) >= 1 {
            sessionName := strings.TrimSpace(parts[0])
            id := fmt.Sprintf("tmux:%s", sessionName)

            m.sessionState[id] = &SessionInfo{
                TTY:     id,
                User:    "tmux",
                Shell:   "tmux",
                Started: time.Now(),
                Tmux:    true,
            }
        }
    }
}

func (m *TerminalSessionMonitor) checkTmuxSessions() {
    // Check for activity in watched sessions
    for name := range m.sessionState {
        if !strings.HasPrefix(name, "tmux:") {
            continue
        }

        sessionName := strings.TrimPrefix(name, "tmux:")
        cmd := exec.Command("tmux", "list-panes", "-t", sessionName, "-F", "#{pane_activity}")
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        outputStr := strings.TrimSpace(string(output))
        if outputStr != "0" && outputStr != "" {
            key := fmt.Sprintf("tmux:%s:activity", sessionName)
            if m.shouldAlert(key, 30*time.Second) {
                sound := m.config.Sounds["tmux_activity"]
                if sound != "" {
                    m.player.Play(sound, 0.3)
                }
            }
        }
    }
}

func (m *TerminalSessionMonitor) onSessionOpened(session *SessionInfo) {
    if !m.config.SoundOnOpen {
        return
    }

    key := fmt.Sprintf("open:%s", session.TTY)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["open"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *TerminalSessionMonitor) onSessionClosed(session *SessionInfo) {
    if !m.config.SoundOnClose {
        return
    }

    key := fmt.Sprintf("close:%s", session.TTY)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["close"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *TerminalSessionMonitor) shouldWatchTTY(tty string) bool {
    if len(m.config.WatchTTYs) == 0 {
        return true
    }

    for _, t := range m.config.WatchTTYs {
        if t == "*" || t == tty {
            return true
        }
    }

    return false
}

func (m *TerminalSessionMonitor) getShellForUser(user string) string {
    cmd := exec.Command("getent", "passwd", user)
    output, err := cmd.Output()
    if err != nil {
        return "/bin/bash"
    }

    parts := strings.Split(string(output), ":")
    if len(parts) >= 7 {
        return parts[6]
    }

    return "/bin/bash"
}

func (m *TerminalSessionMonitor) parseTime(date, timeStr string) time.Time {
    layout := "2006-01-02 15:04"
    t, _ := time.Parse(layout, date+" "+timeStr)
    return t
}

func (m *TerminalSessionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| who | System Tool | Free | User sessions |
| tmux | System Tool | Free | Terminal multiplexer |
| screen | System Tool | Free | Terminal multiplexer |
| getent | System Tool | Free | User database |

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
| macOS | Supported | Uses who, tmux |
| Linux | Supported | Uses who, tmux, screen |
