# Feature: Sound Event Screen Share Monitor

Play sounds for screen sharing session start and stop events.

## Summary

Monitor screen sharing sessions (Zoom, Teams, FaceTime, native), playing sounds when sharing begins or ends.

## Motivation

- Screen share awareness
- Privacy protection
- Meeting feedback
- Recording detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Screen Share Events

| Event | Description | Example |
|-------|-------------|---------|
| Share Started | Sharing began | Zoom screen share |
| Share Stopped | Sharing ended | Stop button |
| Participant Joined | Viewer connected | Someone joined |
| Recording Started | Recording began | Zoom recording |

### Configuration

```go
type ScreenShareMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WatchApps           []string          `json:"watch_apps"` // "zoom.us", "FaceTime"
    SoundOnShareStart   bool              `json:"sound_on_share_start"`
    SoundOnShareStop    bool              `json:"sound_on_share_stop"`
    SoundOnParticipant  bool              `json:"sound_on_participant"`
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 2 default
}

type ScreenShareEvent struct {
    AppName       string
    EventType     string // "share_start", "share_stop", "participant_join"
    ParticipantID string
    Duration      time.Duration
}
```

### Commands

```bash
/ccbell:screen-share status            # Show screen share status
/ccbell:screen-share add "zoom.us"     # Add app to watch
/ccbell:screen-share remove "zoom.us"
/ccbell:screen-share sound start <sound>
/ccbell:screen-share sound stop <sound>
/ccbell:screen-share test              # Test screen share sounds
```

### Output

```
$ ccbell:screen-share status

=== Sound Event Screen Share Monitor ===

Status: Enabled
Share Start Sounds: Yes
Share Stop Sounds: Yes

Current Sharing: No Active Sharing

Active Meetings: 1

[1] Zoom
    Meeting: Team Standup
    Participants: 5
    Started: 30 min ago
    Sharing: Yes (10 min)
    Sound: bundled:stop

[2] FaceTime
    Status: Inactive
    Last Call: Yesterday
    Sound: bundled:stop

Recent Events:
  [1] Zoom: Share Started (10 min ago)
  [2] Zoom: Participant Joined (15 min ago)
       John Doe
  [3] Zoom: Share Stopped (25 min ago)
       Duration: 15 min

Sound Settings:
  Share Start: bundled:stop
  Share Stop: bundled:stop
  Participant Join: bundled:stop

[Configure] [Add App] [Test All]
```

---

## Audio Player Compatibility

Screen share monitoring doesn't play sounds directly:
- Monitoring feature using process and system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Screen Share Monitor

```go
type ScreenShareMonitor struct {
    config            *ScreenShareMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    shareState        map[string]*ShareSession
}

type ShareSession struct {
    AppName      string
    PID          int
    Sharing      bool
    StartTime    time.Time
    Participants int
}
```

```go
func (m *ScreenShareMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.shareState = make(map[string]*ShareSession)
    go m.monitor()
}

func (m *ScreenShareMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkScreenShare()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ScreenShareMonitor) checkScreenShare() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinScreenShare()
    } else {
        m.checkLinuxScreenShare()
    }
}

func (m *ScreenShareMonitor) checkDarwinScreenShare() {
    // Check for screen sharing processes
    apps := []string{
        "zoom.us",
        "FaceTime",
        "Webex",
        "Slack",
        "Teams",
    }

    for _, app := range apps {
        cmd := exec.Command("pgrep", "-f", app)
        output, err := cmd.Output()

        if err == nil && len(output) > 0 {
            pid, _ := strconv.Atoi(strings.TrimSpace(string(output)))
            m.evaluateApp(app, pid)
        }
    }

    // Check for native screen sharing
    cmd := exec.Command("ps", "aux")
    output, err := cmd.Output()
    if err == nil {
        if strings.Contains(string(output), "screencapture") {
            m.evaluateApp("Screen Capture", 0)
        }
    }
}

func (m *ScreenShareMonitor) checkLinuxScreenShare() {
    // Check for screen sharing apps
    apps := []string{
        "zoom",
        "firefox", // for web-based sharing
        "chromium",
    }

    for _, app := range apps {
        cmd := exec.Command("pgrep", "-f", app)
        output, err := cmd.Output()

        if err == nil && len(output) > 0 {
            pid, _ := strconv.Atoi(strings.TrimSpace(string(output)))
            m.evaluateApp(app, pid)
        }
    }

    // Check for OBS studio (often used for streaming)
    cmd := exec.Command("pgrep", "-f", "obs")
    output, err := cmd.Output()
    if err == nil && len(output) > 0 {
        m.evaluateApp("OBS Studio", 0)
    }
}

func (m *ScreenShareMonitor) evaluateApp(app string, pid int) {
    key := app
    session := m.shareState[key]

    if session == nil {
        session = &ShareSession{
            AppName:   app,
            PID:       pid,
            StartTime: time.Now(),
        }
        m.shareState[key] = session
        m.onAppStarted(app)
        return
    }

    // Check if screen sharing is active
    sharing := m.detectScreenSharing(app, pid)

    if sharing && !session.Sharing {
        // Sharing just started
        session.Sharing = true
        m.onShareStarted(app)
    } else if !sharing && session.Sharing {
        // Sharing stopped
        session.Sharing = false
        m.onShareStopped(app, time.Since(session.StartTime))
    }

    session.PID = pid
}

func (m *ScreenShareMonitor) detectScreenSharing(app string, pid int) bool {
    switch app {
    case "zoom.us":
        return m.detectZoomSharing(pid)
    case "FaceTime":
        return m.detectFaceTimeSharing(pid)
    case "Slack":
        return m.detectSlackSharing(pid)
    case "Teams":
        return m.detectTeamsSharing(pid)
    default:
        return m.detectGenericSharing(pid)
    }
}

func (m *ScreenShareMonitor) detectZoomSharing(pid int) bool {
    // Check for Zoom screen share process
    cmd := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "comm=")
    output, _ := cmd.Output()
    procName := strings.TrimSpace(string(output))

    if procName == "CptHost" || procName == "Zoom" {
        return true
    }

    // Check for pipewire or quartz graphics
    cmd = exec.Command("lsof", "-p", strconv.Itoa(pid))
    output, _ = cmd.Output()
    if strings.Contains(string(output), "pipewire") ||
       strings.Contains(string(output), "screencapture") {
        return true
    }

    return false
}

func (m *ScreenShareMonitor) detectFaceTimeSharing(pid int) bool {
    // FaceTime screen sharing indicator
    cmd := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "args=")
    output, _ := cmd.Output()
    return strings.Contains(string(output), "AVConference")
}

func (m *ScreenShareMonitor) detectSlackSharing(pid int) bool {
    cmd := exec.Command("lsof", "-p", strconv.Itoa(pid))
    output, _ := cmd.Output()
    return strings.Contains(string(output), "screencapture")
}

func (m *ScreenShareMonitor) detectTeamsSharing(pid int) bool {
    cmd := exec.Command("lsof", "-p", strconv.Itoa(pid))
    output, _ := cmd.Output()
    return strings.Contains(string(output), "desktopCapturer")
}

func (m *ScreenShareMonitor) detectGenericSharing(pid int) bool {
    // Generic screen sharing detection
    cmd := exec.Command("lsof", "-p", strconv.Itoa(pid))
    output, _ := cmd.Output()

    indicators := []string{
        "pipewire",
        "screencapture",
        "x11grab",
        "gdigrab",
    }

    for _, indicator := range indicators {
        if strings.Contains(string(output), indicator) {
            return true
        }
    }

    return false
}

func (m *ScreenShareMonitor) onAppStarted(app string) {
    sound := m.config.Sounds["app_started"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ScreenShareMonitor) onShareStarted(app string) {
    if !m.config.SoundOnShareStart {
        return
    }

    sound := m.config.Sounds["share_start"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenShareMonitor) onShareStopped(app string, duration time.Duration) {
    if !m.config.SoundOnShareStop {
        return
    }

    sound := m.config.Sounds["share_stop"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenShareMonitor) onParticipantJoined(participantID string) {
    if !m.config.SoundOnParticipant {
        return
    }

    sound := m.config.Sounds["participant_join"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pgrep | System Tool | Free | Process checking |
| lsof | System Tool | Free | File descriptor checking |
| ps | System Tool | Free | Process status |

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
| macOS | Supported | Uses pgrep, lsof |
| Linux | Supported | Uses pgrep, lsof |
| Windows | Not Supported | ccbell only supports macOS/Linux |
