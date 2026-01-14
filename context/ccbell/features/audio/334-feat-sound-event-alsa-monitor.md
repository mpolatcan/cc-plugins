# Feature: Sound Event ALSA Monitor

Play sounds for ALSA device changes and mixer events.

## Summary

Monitor ALSA sound devices, mixer changes, and audio device events, playing sounds for ALSA events.

## Motivation

- Audio device awareness
- Device change detection
- Mixer control feedback
- Jack detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### ALSA Events

| Event | Description | Example |
|-------|-------------|---------|
| Device Added | New sound device | USB audio attached |
| Device Removed | Sound device removed | USB audio detached |
| Jack Inserted | Headphone jack in | Headphones connected |
| Volume Changed | Master volume changed | 50% -> 60% |

### Configuration

```go
type ALSAMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchCards        []int             `json:"watch_cards"] // 0, 1
    VolumeWarningPct  int               `json:"volume_warning_pct"` // 90 default
    SoundOnDevice     bool              `json:"sound_on_device"]
    SoundOnJack       bool              `json:"sound_on_jack"]
    SoundOnVolume     bool              `json:"sound_on_volume"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type ALSAEvent struct {
    Card      int
    Device    string
    Type      string // "hda", "usb", "jack"
    Value     int
    EventType string // "device_add", "device_remove", "jack", "volume"
}
```

### Commands

```bash
/ccbell:alsa status                   # Show ALSA status
/ccbell:alsa add 0                    # Add card to watch
/ccbell:alsa remove 0
/ccbell:alsa volume 90                # Set volume warning
/ccbell:alsa sound device <sound>
/ccbell:alsa test                     # Test ALSA sounds
```

### Output

```
$ ccbell:alsa status

=== Sound Event ALSA Monitor ===

Status: Enabled
Volume Warning: 90%
Device Sounds: Yes

Watched Cards: 1

[1] Card 0 (HDA Intel PCH)
    Devices: 3
    Status: ACTIVE
    Master Volume: 50%
    Headphone Jack: PLUGGED
    Sound: bundled:stop

[2] Card 1 (USB Audio Device)
    Devices: 2
    Status: ACTIVE
    Master Volume: 40%
    Headphone Jack: UNPLUGGED
    Sound: bundled:alsa-usb

Recent Events:
  [1] Card 1: Device Added (5 min ago)
       USB Audio Device attached
  [2] Card 0: Headphone Jack (10 min ago)
       Headphones PLUGGED
  [3] Card 0: Volume Changed (1 hour ago)
       Master: 50% -> 60%

ALSA Statistics:
  Total devices: 5
  USB devices: 2

Sound Settings:
  Device Add: bundled:alsa-add
  Device Remove: bundled:alsa-remove
  Jack: bundled:alsa-jack

[Configure] [Add Card] [Test All]
```

---

## Audio Player Compatibility

ALSA monitoring doesn't play sounds directly:
- Monitoring feature using aplay/arecord
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### ALSA Monitor

```go
type ALSAMonitor struct {
    config           *ALSAMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    cardState        map[int]*ALSAInfo
    lastEventTime    map[string]time.Time
}

type ALSAInfo struct {
    Card         int
    Name         string
    Devices      int
    Volume       int
    JackState    string
}

func (m *ALSAMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cardState = make(map[int]*ALSAInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ALSAMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotALSAState()

    for {
        select {
        case <-ticker.C:
            m.checkALSAState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ALSAMonitor) snapshotALSAState() {
    // Check available cards
    cmd := exec.Command("aplay", "-l")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseALSAOutput(string(output))
}

func (m *ALSAMonitor) checkALSAState() {
    cmd := exec.Command("aplay", "-l")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseALSAOutput(string(output))
}

func (m *ALSAMonitor) parseALSAOutput(output string) {
    lines := strings.Split(output, "\n")
    currentCards := make(map[int]bool)

    for _, line := range lines {
        if strings.HasPrefix(line, "card ") {
            // Parse card info
            re := regexp.MustCompile(`card (\d+): ([^[]+)`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                cardNum, _ := strconv.Atoi(match[1])
                cardName := match[2]

                currentCards[cardNum] = true

                if !m.shouldWatchCard(cardNum) {
                    continue
                }

                // Get volume for this card
                volume := m.getMasterVolume(cardNum)
                jackState := m.getJackState(cardNum)

                info := &ALSAInfo{
                    Card:      cardNum,
                    Name:      cardName,
                    Volume:    volume,
                    JackState: jackState,
                }

                lastInfo := m.cardState[cardNum]
                m.evaluateALSAState(cardNum, info, lastInfo)

                m.cardState[cardNum] = info
            }
        }
    }

    // Check for removed cards
    for cardNum := range m.cardState {
        if !currentCards[cardNum] {
            m.onDeviceRemoved(cardNum, m.cardState[cardNum])
            delete(m.cardState, cardNum)
        }
    }
}

func (m *ALSAMonitor) getMasterVolume(cardNum int) int {
    cmd := exec.Command("amixer", "-c", strconv.Itoa(cardNum), "sget", "Master", "Playback", "Volume")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    re := regexp.MustCompile(`(\d+)%`)
    match := re.FindStringSubmatch(string(output))
    if match != nil {
        vol, _ := strconv.Atoi(match[1])
        return vol
    }

    return 0
}

func (m *ALSAMonitor) getJackState(cardNum int) string {
    // Check for headphone jack
    cmd := exec.Command("amixer", "-c", strconv.Itoa(cardNum), "cget", "iface=CARD", "name='Headphone Jack'")
    output, err := cmd.Output()
    if err != nil {
        return "UNKNOWN"
    }

    if strings.Contains(string(output), "values=on") || strings.Contains(string(output), "plugged") {
        return "PLUGGED"
    } else if strings.Contains(string(output), "values=off") || strings.Contains(string(output), "unplugged") {
        return "UNPLUGGED"
    }

    return "UNKNOWN"
}

func (m *ALSAMonitor) evaluateALSAState(cardNum int, info *ALSAInfo, lastInfo *ALSAInfo) {
    if lastInfo == nil {
        // New device
        m.onDeviceAdded(cardNum, info)
        return
    }

    // Check volume change
    if info.Volume != lastInfo.Volume {
        m.onVolumeChanged(cardNum, info.Volume, lastInfo.Volume)
    }

    // Check jack change
    if info.JackState != lastInfo.JackState {
        m.onJackChanged(cardNum, info.JackState)
    }
}

func (m *ALSAMonitor) shouldWatchCard(cardNum int) bool {
    if len(m.config.WatchCards) == 0 {
        return true
    }

    for _, c := range m.config.WatchCards {
        if c == cardNum {
            return true
        }
    }

    return false
}

func (m *ALSAMonitor) onDeviceAdded(cardNum int, info *ALSAInfo) {
    if !m.config.SoundOnDevice {
        return
    }

    key := fmt.Sprintf("device_add:%d", cardNum)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["device"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ALSAMonitor) onDeviceRemoved(cardNum int, info *ALSAInfo) {
    sound := m.config.Sounds["device_remove"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *ALSAMonitor) onVolumeChanged(cardNum int, newVolume int, oldVolume int) {
    if !m.config.SoundOnVolume {
        return
    }

    // Check warning threshold
    if newVolume >= m.config.VolumeWarningPct && oldVolume < m.config.VolumeWarningPct {
        key := fmt.Sprintf("volume:%d", cardNum)
        if m.shouldAlert(key, 5*time.Minute) {
            sound := m.config.Sounds["volume_warning"]
            if sound != "" {
                m.player.Play(sound, 0.4)
            }
        }
    }
}

func (m *ALSAMonitor) onJackChanged(cardNum int, jackState string) {
    if !m.config.SoundOnJack {
        return
    }

    key := fmt.Sprintf("jack:%d:%s", cardNum, jackState)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["jack"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *ALSAMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| aplay | System Tool | Free | ALSA device listing |
| amixer | System Tool | Free | ALSA mixer control |

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
| macOS | Not Supported | No native ALSA |
| Linux | Supported | Uses aplay, amixer |
| Windows | Not Supported | ccbell only supports macOS/Linux |
