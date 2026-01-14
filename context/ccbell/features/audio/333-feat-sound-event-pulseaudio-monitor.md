# Feature: Sound Event PulseAudio Monitor

Play sounds for PulseAudio server events and sink/source changes.

## Summary

Monitor PulseAudio server status, sink changes, and volume events, playing sounds for audio events.

## Motivation

- Audio device awareness
- Sink change feedback
- Volume alerts
- Server status detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### PulseAudio Events

| Event | Description | Example |
|-------|-------------|---------|
| Sink Changed | Default sink changed | hdmi -> analog |
| Server Started | PA server started | daemon started |
| Volume Changed | Sink volume changed | 50% -> 75% |
| Mute Changed | Sink muted/unmuted | Muted |

### Configuration

```go
type PulseAudioMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchSinks        []string          `json:"watch_sinks"] // "alsa_output", "hdmi"
    VolumeWarningPct  int               `json:"volume_warning_pct"` // 90 default
    SoundOnSinkChange bool              `json:"sound_on_sink_change"]
    SoundOnVolume     bool              `json:"sound_on_volume"]
    SoundOnMute       bool              `json:"sound_on_mute"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type PulseAudioEvent struct {
    Sink      string
    Volume    int
    Muted     bool
    Server    string
    EventType string // "sink_change", "volume", "mute", "server_start"
}
```

### Commands

```bash
/ccbell:pulse status                  # Show PulseAudio status
/ccbell:pulse add hdmi                # Add sink to watch
/ccbell:pulse remove hdmi
/ccbell:pulse volume 90               # Set volume warning
/ccbell:pulse sound sink <sound>
/ccbell:pulse test                    # Test PulseAudio sounds
```

### Output

```
$ ccbell:pulse status

=== Sound Event PulseAudio Monitor ===

Status: Enabled
Volume Warning: 90%
Sink Sounds: Yes

Default Sink: alsa_output.pci-0000_00_1f.3.analog-stereo
Server: local (PulseAudio 17.0)

Sinks:
  [1] alsa_output.pci-0000_00_1f.3.analog-stereo
      Volume: 50%
      Muted: No
      Status: RUNNING
      Sound: bundled:stop

  [2] alsa_output.hdmi-stereo
      Volume: 75%
      Muted: No
      Status: IDLE
      Sound: bundled:pulse-sink

Recent Events:
  [1] Sink Changed (5 min ago)
       alsa_output.hdmi-stereo -> alsa_output.pci-0000_00_1f.3.analog-stereo
  [2] Volume Changed (10 min ago)
       alsa_output.pci-0000_00_1f.3.analog-stereo: 50% -> 75%
  [3] Server Started (1 hour ago)
       PulseAudio daemon started

Sound Settings:
  Sink Change: bundled:pulse-sink
  Volume: bundled:pulse-volume
  Mute: bundled:pulse-mute

[Configure] [Add Sink] [Test All]
```

---

## Audio Player Compatibility

PulseAudio monitoring doesn't play sounds directly:
- Monitoring feature using pactl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### PulseAudio Monitor

```go
type PulseAudioMonitor struct {
    config           *PulseAudioMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    sinkState        map[string]*SinkInfo
    lastEventTime    map[string]time.Time
}

type SinkInfo struct {
    Name     string
    Volume   int
    Muted    bool
    Running  bool
}

func (m *PulseAudioMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sinkState = make(map[string]*SinkInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *PulseAudioMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSinkState()

    for {
        select {
        case <-ticker.C:
            m.checkSinkState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PulseAudioMonitor) snapshotSinkState() {
    cmd := exec.Command("pactl", "list", "short", "sinks")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSinkList(string(output))
}

func (m *PulseAudioMonitor) checkSinkState() {
    cmd := exec.Command("pactl", "list", "short", "sinks")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseSinkList(string(output))
}

func (m *PulseAudioMonitor) parseSinkList(output string) {
    lines := strings.Split(output, "\n")
    currentSinks := make(map[string]*SinkInfo)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        sinkName := parts[1]
        if !m.shouldWatchSink(sinkName) {
            continue
        }

        // Get sink info
        info := m.getSinkInfo(sinkName)
        if info == nil {
            continue
        }

        currentSinks[sinkName] = info

        lastInfo := m.sinkState[sinkName]
        if lastInfo == nil {
            // First time seeing this sink
            m.sinkState[sinkName] = info
            continue
        }

        // Check for changes
        if info.Volume != lastInfo.Volume {
            m.onVolumeChanged(sinkName, info.Volume, lastInfo.Volume)
        }

        if info.Muted != lastInfo.Muted {
            m.onMuteChanged(sinkName, info.Muted)
        }
    }

    // Check for default sink change
    m.checkDefaultSink()

    m.sinkState = currentSinks
}

func (m *PulseAudioMonitor) getSinkInfo(sinkName string) *SinkInfo {
    cmd := exec.Command("pactl", "list", "sinks")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    var inSink bool
    var volume int
    var muted bool

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Sink #") {
            inSink = strings.Contains(line, sinkName)
            continue
        }

        if !inSink {
            continue
        }

        if strings.HasPrefix(line, "\tVolume:") {
            // Parse volume percentage
            re := regexp.MustCompile(`(\d+)%`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                volume, _ = strconv.Atoi(match[1])
            }
        }

        if strings.HasPrefix(line, "\tMute:") {
            muted = strings.Contains(line, "yes")
        }
    }

    return &SinkInfo{
        Name:   sinkName,
        Volume: volume,
        Muted:  muted,
    }
}

func (m *PulseAudioMonitor) checkDefaultSink() {
    cmd := exec.Command("pactl", "get-default-sink")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    defaultSink := strings.TrimSpace(string(output))

    lastDefault := ""
    for name, info := range m.sinkState {
        if info.Running {
            lastDefault = name
            break
        }
    }

    if lastDefault != "" && defaultSink != lastDefault {
        m.onSinkChanged(defaultSink, lastDefault)
    }

    // Mark the new default as running
    if info, exists := m.sinkState[defaultSink]; exists {
        info.Running = true
    }
}

func (m *PulseAudioMonitor) shouldWatchSink(sinkName string) bool {
    if len(m.config.WatchSinks) == 0 {
        return true
    }

    for _, s := range m.config.WatchSinks {
        if strings.Contains(sinkName, s) {
            return true
        }
    }

    return false
}

func (m *PulseAudioMonitor) onSinkChanged(newSink string, oldSink string) {
    if !m.config.SoundOnSinkChange {
        return
    }

    key := fmt.Sprintf("sink_change:%s->%s", oldSink, newSink)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["sink_change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PulseAudioMonitor) onVolumeChanged(sinkName string, newVolume int, oldVolume int) {
    if !m.config.SoundOnVolume {
        return
    }

    // Check warning threshold
    if newVolume >= m.config.VolumeWarningPct && oldVolume < m.config.VolumeWarningPct {
        key := fmt.Sprintf("volume_warning:%s", sinkName)
        if m.shouldAlert(key, 5*time.Minute) {
            sound := m.config.Sounds["volume_warning"]
            if sound != "" {
                m.player.Play(sound, 0.4)
            }
        }
    }
}

func (m *PulseAudioMonitor) onMuteChanged(sinkName string, muted bool) {
    if !m.config.SoundOnMute {
        return
    }

    if muted {
        key := fmt.Sprintf("mute:%s", sinkName)
        if m.shouldAlert(key, 30*time.Second) {
            sound := m.config.Sounds["mute"]
            if sound != "" {
                m.player.Play(sound, 0.3)
            }
        }
    }
}

func (m *PulseAudioMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| macOS | Not Supported | No PulseAudio |
| Linux | Supported | Uses pactl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
