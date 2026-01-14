# Feature: Sound Event Audio Device Stream Monitor

Play sounds for audio stream state changes and device events.

## Summary

Monitor audio device streams, PCM streams, and audio mixer events, playing sounds for audio stream events.

## Motivation

- Audio stream awareness
- Recording detection
- Playback state changes
- Audio device feedback
- Stream error detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Audio Stream Events

| Event | Description | Example |
|-------|-------------|---------|
| Stream Started | Audio playback started | Music playing |
| Stream Stopped | Audio playback stopped | Playback ended |
| Recording Started | Recording started | Mic active |
| Recording Stopped | Recording stopped | Mic muted |
| Stream Underrun | Buffer underrun | Audio glitch |
| Stream XRun | Exception in stream | Latency issue |

### Configuration

```go
type AudioStreamMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDevices      []string          `json:"watch_devices"` // "pulse", "alsa", "*"
    WatchStreams      []string          `json:"watch_streams"` // "spotify", "firefox", "*"
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnStop       bool              `json:"sound_on_stop"`
    SoundOnRecord     bool              `json:"sound_on_record"`
    SoundOnError      bool              `json:"sound_on_error"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type AudioStreamEvent struct {
    Device      string
    Stream      string
    Direction   string // "playback", "capture"
    State       string // "running", "stopped", "suspended"]
    Latency     int // ms
    Channels    int
    SampleRate  int
    EventType   string // "start", "stop", "record", "underrun", "error"
}
```

### Commands

```bash
/ccbell:audiostream status            # Show audio stream status
/ccbell:audiostream add spotify       # Add stream to watch
/ccbell:audiostream remove spotify
/ccbell:audiostream sound start <sound>
/ccbell:audiostream sound record <sound>
/ccbell:audiostream test              # Test audio stream sounds
```

### Output

```
$ ccbell:audiostream status

=== Sound Event Audio Device Stream Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes
Record Sounds: Yes

Watched Devices: 1
Watched Streams: 2

[1] Spotify
    Device: pulseaudio (alsa_output)
    State: PLAYING
    Latency: 23 ms
    Channels: 2
    Sample Rate: 44100 Hz
    Volume: 75%
    Sound: bundled:audio-spotify

[2] Firefox
    Device: pulseaudio (alsa_input)
    State: RECORDING
    Latency: 15 ms
    Channels: 1
    Sample Rate: 48000 Hz
    Sound: bundled:audio-browser

Recent Events:
  [1] Spotify: Stream Started (5 min ago)
       Playback began
  [2] Firefox: Recording Started (10 min ago)
       Microphone active
  [3] Spotify: Stream Stopped (1 hour ago)
       Playback ended

Audio Stream Statistics:
  Active Streams: 2
  Playback: 1
  Recording: 1
  XRun Events: 0

Sound Settings:
  Start: bundled:audio-start
  Stop: bundled:audio-stop
  Record: bundled:audio-record
  Error: bundled:audio-error

[Configure] [Add Stream] [Test All]
```

---

## Audio Player Compatibility

Audio stream monitoring doesn't play sounds directly:
- Monitoring feature using pactl/parec
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Audio Stream Monitor

```go
type AudioStreamMonitor struct {
    config          *AudioStreamMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    streamState     map[string]*StreamInfo
    lastEventTime   map[string]time.Time
}

type StreamInfo struct {
    Device      string
    Stream      string
    Direction   string
    State       string
    Latency     int
    Channels    int
    SampleRate  int
    Volume      int
    LastUpdate  time.Time
}

func (m *AudioStreamMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.streamState = make(map[string]*StreamInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *AudioStreamMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Detect audio system
    m.detectAudioSystem()

    // Initial snapshot
    m.snapshotStreamState()

    for {
        select {
        case <-ticker.C:
            m.checkStreamState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *AudioStreamMonitor) detectAudioSystem() {
    // Check for PulseAudio
    if _, err := exec.LookPath("pactl"); err == nil {
        m.config.WatchDevices = append(m.config.WatchDevices, "pulse")
    }

    // Check for ALSA
    if _, err := exec.LookPath("aplay"); err == nil {
        m.config.WatchDevices = append(m.config.WatchDevices, "alsa")
    }
}

func (m *AudioStreamMonitor) snapshotStreamState() {
    if m.hasPulseAudio() {
        m.checkPulseStreams()
    } else if m.hasALSA() {
        m.checkALSAStreams()
    }
}

func (m *AudioStreamMonitor) checkStreamState() {
    if m.hasPulseAudio() {
        m.checkPulseStreams()
    } else if m.hasALSA() {
        m.checkALSAStreams()
    }
}

func (m *AudioStreamMonitor) hasPulseAudio() bool {
    for _, dev := range m.config.WatchDevices {
        if dev == "pulse" {
            return true
        }
    }
    return false
}

func (m *AudioStreamMonitor) hasALSA() bool {
    for _, dev := range m.config.WatchDevices {
        if dev == "alsa" {
            return true
        }
    }
    return false
}

func (m *AudioStreamMonitor) checkPulseStreams() {
    // List sink inputs (playback streams)
    cmd := exec.Command("pactl", "list", "sink-inputs", "-j")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePulseStreams(string(output), "playback")

    // List source outputs (recording streams)
    cmd = exec.Command("pactl", "list", "source-outputs", "-j")
    output, err = cmd.Output()
    if err != nil {
        return
    }

    m.parsePulseStreams(string(output), "capture")
}

func (m *AudioStreamMonitor) parsePulseStreams(output string, direction string) {
    // Parse JSON output from pactl
    // This is a simplified approach

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Sink Input") || strings.Contains(line, "Source Output") {
            // Extract stream info
            re := regexp.MustCompile(`"name": "([^"]+)"`)
            match := re.FindStringSubmatch(line)
            if match == nil {
                continue
            }

            name := match[1]
            key := fmt.Sprintf("%s:%s", direction, name)

            info := &StreamInfo{
                Stream:    name,
                Direction: direction,
                State:     "running",
                LastUpdate: time.Now(),
            }

            // Get volume if available
            volCmd := exec.Command("pactl", "get-sink-input-volume", name)
            volOutput, _ := volCmd.Output()
            if strings.Contains(string(volOutput), "%") {
                volRe := regexp.MustCompile(`(\d+)%`)
                volMatch := volRe.FindStringSubmatch(string(volOutput))
                if volMatch != nil {
                    info.Volume, _ = strconv.Atoi(volMatch[1])
                }
            }

            lastInfo := m.streamState[key]
            if lastInfo == nil {
                m.streamState[key] = info
                if m.shouldWatchStream(name) {
                    if direction == "capture" {
                        m.onRecordingStarted(info)
                    } else {
                        m.onStreamStarted(info)
                    }
                }
                continue
            }

            // Check state changes
            if lastInfo.State == "running" && info.State != "running" {
                if m.shouldWatchStream(name) {
                    m.onStreamStopped(lastInfo)
                }
            }

            m.streamState[key] = info
        }
    }
}

func (m *AudioStreamMonitor) checkALSAStreams() {
    // Use aplay -l to list devices
    cmd := exec.Command("aplay", "-l")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse ALSA device list
    m.parseALSAOutput(string(output))
}

func (m *AudioStreamMonitor) parseALSAOutput(output string) {
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "card") {
            // Parse card info
            re := regexp.MustCompile(`card (\d+): ([^[]+)`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                // Device found
            }
        }
    }
}

func (m *AudioStreamMonitor) shouldWatchStream(name string) bool {
    if len(m.config.WatchStreams) == 0 {
        return true
    }

    for _, s := range m.config.WatchStreams {
        if s == "*" || strings.Contains(name, s) {
            return true
        }
    }

    return false
}

func (m *AudioStreamMonitor) onStreamStarted(info *StreamInfo) {
    if !m.config.SoundOnStart {
        return
    }

    key := fmt.Sprintf("start:%s", info.Stream)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AudioStreamMonitor) onStreamStopped(info *StreamInfo) {
    if !m.config.SoundOnStop {
        return
    }

    key := fmt.Sprintf("stop:%s", info.Stream)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["stop"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *AudioStreamMonitor) onRecordingStarted(info *StreamInfo) {
    if !m.config.SoundOnRecord {
        return
    }

    key := fmt.Sprintf("record:%s", info.Stream)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["record"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AudioStreamMonitor) onStreamError(info *StreamInfo) {
    if !m.config.SoundOnError {
        return
    }

    key := fmt.Sprintf("error:%s", info.Stream)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *AudioStreamMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| pactl | System Tool | Free | PulseAudio control |
| aplay | System Tool | Free | ALSA device listing |

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
| macOS | Limited | Uses audio APIs directly |
| Linux | Supported | Uses pactl, aplay |
