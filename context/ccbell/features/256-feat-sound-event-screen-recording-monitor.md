# Feature: Sound Event Screen Recording Monitor

Play sounds for screen recording start and stop events.

## Summary

Monitor screen recording activities, capturing start/stop events, and playing sounds for recording status changes.

## Motivation

- Recording state awareness
- Privacy protection
- Recording completion alerts
- Capture session feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Screen Recording Events

| Event | Description | Example |
|-------|-------------|---------|
| Recording Started | Capture began | Cmd+Shift+5 |
| Recording Stopped | Capture ended | Stop button |
| Screenshot Taken | Image captured | Cmd+Shift+4 |
| Recording Paused | Capture paused | Edit mode |

### Configuration

```go
type ScreenRecordingMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    SoundOnStart    bool              `json:"sound_on_start"`
    SoundOnStop     bool              `json:"sound_on_stop"`
    SoundOnScreenshot bool            `json:"sound_on_screenshot"`
    WatchProcesses  []string          `json:"watch_processes"` // "screencapture", "ffmpeg"
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 1 default
}

type ScreenRecordingEvent struct {
    ProcessName  string
    EventType    string // "started", "stopped", "screenshot"
    Duration     time.Duration
    OutputPath   string
}
```

### Commands

```bash
/ccbell:screen-recording status     # Show recording status
/ccbell:screen-recording sound start <sound>
/ccbell:screen-recording sound stop <sound>
/ccbell:screen-recording test       # Test recording sounds
```

### Output

```
$ ccbell:screen-recording status

=== Sound Event Screen Recording Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes

Current Activity:
  Recording: No
  Last Recording: 2 hours ago
  Duration: 5 min 30 sec
  Saved: ~/Movies/Screen Recording.mov

Recent Events:
  [1] Recording Stopped (2 hours ago)
       Duration: 5:30
       Saved to ~/Movies/
  [2] Recording Started (2 hours ago)
  [3] Screenshot Taken (1 day ago)
       ~/Desktop/Screenshot.png

Sound Settings:
  Started: bundled:stop
  Stopped: bundled:stop
  Screenshot: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Screen recording monitoring doesn't play sounds directly:
- Monitoring feature using process and file tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Screen Recording Monitor

```go
type ScreenRecordingMonitor struct {
    config          *ScreenRecordingMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    activeProcesses map[string]*RecordingProcess
}

type RecordingProcess struct {
    PID        int
    Name       string
    StartTime  time.Time
    OutputPath string
}

func (m *ScreenRecordingMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeProcesses = make(map[string]*RecordingProcess)
    go m.monitor()
}

func (m *ScreenRecordingMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkRecording()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ScreenRecordingMonitor) checkRecording() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinRecording()
    } else {
        m.checkLinuxRecording()
    }
}

func (m *ScreenRecordingMonitor) checkDarwinRecording() {
    // Check for running screen recording processes
    processes := []string{"screencapture", "ffmpeg", "obs"}

    for _, proc := range processes {
        cmd := exec.Command("pgrep", "-f", proc)
        output, err := cmd.Output()

        if err == nil && len(output) > 0 {
            // Process is running
            pid, _ := strconv.Atoi(strings.TrimSpace(string(output)))

            key := fmt.Sprintf("%s-%d", proc, pid)
            if m.activeProcesses[key] == nil {
                m.activeProcesses[key] = &RecordingProcess{
                    PID:       pid,
                    Name:      proc,
                    StartTime: time.Now(),
                }
                m.onRecordingStarted(proc)
            }
        }
    }

    // Check for stopped processes
    for key, proc := range m.activeProcesses {
        cmd := exec.Command("ps", "-p", strconv.Itoa(proc.PID))
        err := cmd.Run()

        if err != nil {
            // Process no longer exists
            delete(m.activeProcesses, key)
            m.onRecordingStopped(proc)
        }
    }
}

func (m *ScreenRecordingMonitor) checkLinuxRecording() {
    // Check for ffmpeg or recordmydesktop processes
    processes := []string{"ffmpeg", "recordmydesktop", "simplescreenrecorder"}

    for _, proc := range processes {
        cmd := exec.Command("pgrep", "-f", proc)
        output, err := cmd.Output()

        if err == nil && len(output) > 0 {
            pid, _ := strconv.Atoi(strings.TrimSpace(string(output)))

            key := fmt.Sprintf("%s-%d", proc, pid)
            if m.activeProcesses[key] == nil {
                m.activeProcesses[key] = &RecordingProcess{
                    PID:       pid,
                    Name:      proc,
                    StartTime: time.Now(),
                }
                m.onRecordingStarted(proc)
            }
        }
    }

    // Check for stopped processes
    for key, proc := range m.activeProcesses {
        cmd := exec.Command("ps", "-p", strconv.Itoa(proc.PID))
        err := cmd.Run()

        if err != nil {
            delete(m.activeProcesses, key)
            m.onRecordingStopped(proc)
        }
    }
}

func (m *ScreenRecordingMonitor) onRecordingStarted(name string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenRecordingMonitor) onRecordingStopped(proc *RecordingProcess) {
    if !m.config.SoundOnStop {
        return
    }

    sound := m.config.Sounds["stopped"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ScreenRecordingMonitor) onScreenshotTaken() {
    if !m.config.SoundOnScreenshot {
        return
    }

    sound := m.config.Sounds["screenshot"]
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
| ps | System Tool | Free | Process status |
| ffmpeg | External Tool | Free | Recording software |
| screencapture | System Tool | Free | macOS screenshot |

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
| macOS | Supported | Uses screencapture, ffmpeg |
| Linux | Supported | Uses ffmpeg, recordmydesktop |
| Windows | Not Supported | ccbell only supports macOS/Linux |
