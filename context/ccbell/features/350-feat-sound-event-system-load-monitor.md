# Feature: Sound Event System Load Monitor

Play sounds for system load threshold crossings and load spike events.

## Summary

Monitor system load averages (1/5/15 min), CPU load, and process queue, playing sounds for load events.

## Motivation

- Load awareness
- Performance degradation
- Load spike alerts
- Capacity planning feedback
- System stress detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Load Events

| Event | Description | Example |
|-------|-------------|---------|
| High Load 1min | 1-min load high | Load > CPU count |
| High Load 5min | 5-min load elevated | Load > 80% threshold |
| Load Spike | Sudden load increase | 2x normal |
| Load Normal | Load returned to normal | System recovered |
| Process Queue | Run queue long | 50+ processes |

### Configuration

```go
type SystemLoadMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Load1Threshold    float64           `json:"load1_threshold"` // CPU count default
    Load5Threshold    float64           `json:"load5_threshold"` // 0.8 * CPU default
    SpikeMultiplier   float64           `json:"spike_multiplier"` // 2.0 default
    ProcessQueueLimit int               `json:"process_queue_limit"` // 50 default
    SoundOnHigh       bool              `json:"sound_on_high"`
    SoundOnSpike      bool              `json:"sound_on_spike"`
    SoundOnNormal     bool              `json:"sound_on_normal"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type SystemLoadEvent struct {
    Load1       float64
    Load5       float64
    Load15      float64
    NumCPU      int
    ProcessQueue int
    EventType   string // "high", "spike", "normal", "queue"
}
```

### Commands

```bash
/ccbell:load status                   # Show system load status
/ccbell:load threshold 4.0            # Set load threshold
/ccbell:load spike 2.0                # Set spike multiplier
/ccbell:load sound high <sound>
/ccbell:load sound spike <sound>
/ccbell:load test                     # Test load sounds
```

### Output

```
$ ccbell:load status

=== Sound Event System Load Monitor ===

Status: Enabled
Load 1min Threshold: 4.0 (CPU count)
Load 5min Threshold: 3.2
Spike Multiplier: 2.0
High Load Sounds: Yes
Spike Sounds: Yes

System Load:
  Load 1min:  5.2 *** HIGH ***
  Load 5min:  3.8
  Load 15min: 2.5
  CPU Count:  4
  Process Queue: 12
  Sound: bundled:load-high

Recent Events:
  [1] System: High Load 1min (5 min ago)
       Load: 5.2 > 4.0 threshold
  [2] System: Load Spike (10 min ago)
       Load: 2.1 -> 5.2 (2.5x increase)
  [3] System: Load Normal (1 hour ago)
       Load returned to normal range

Load Statistics:
  Avg Load 1min: 2.8
  Max Load 1min: 6.5
  High Load Events: 15

Sound Settings:
  High: bundled:load-high
  Spike: bundled:load-spike
  Normal: bundled:load-normal

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

System load monitoring doesn't play sounds directly:
- Monitoring feature using /proc/loadavg
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Load Monitor

```go
type SystemLoadMonitor struct {
    config          *SystemLoadMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    loadState       *LoadInfo
    lastEventTime   map[string]time.Time
}

type LoadInfo struct {
    Load1       float64
    Load5       float64
    Load15      float64
    NumCPU      int
    ProcessQueue int
    LastUpdate  time.Time
}

func (m *SystemLoadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.loadState = &LoadInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemLoadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Get CPU count
    m.loadState.NumCPU = runtime.NumCPU()

    // Set default thresholds
    if m.config.Load1Threshold == 0 {
        m.config.Load1Threshold = float64(m.loadState.NumCPU)
    }
    if m.config.Load5Threshold == 0 {
        m.config.Load5Threshold = float64(m.loadState.NumCPU) * 0.8
    }

    // Initial snapshot
    m.snapshotLoadState()

    for {
        select {
        case <-ticker.C:
            m.checkLoadState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemLoadMonitor) snapshotLoadState() {
    m.checkLoadState()
}

func (m *SystemLoadMonitor) checkLoadState() {
    data, err := os.ReadFile("/proc/loadavg")
    if err != nil {
        return
    }

    parts := strings.Fields(string(data))
    if len(parts) < 5 {
        return
    }

    load1, _ := strconv.ParseFloat(parts[0], 64)
    load5, _ := strconv.ParseFloat(parts[1], 64)
    load15, _ := strconv.ParseFloat(parts[2], 64)

    // Get process queue from /proc/stat
    processQueue := m.getProcessQueue()

    newState := &LoadInfo{
        Load1:        load1,
        Load5:        load5,
        Load15:       load15,
        NumCPU:       m.loadState.NumCPU,
        ProcessQueue: processQueue,
        LastUpdate:   time.Now(),
    }

    if m.loadState.Load1 > 0 {
        m.evaluateLoadEvents(newState, m.loadState)
    }

    m.loadState = newState
}

func (m *SystemLoadMonitor) getProcessQueue() int {
    data, err := os.ReadFile("/proc/loadavg")
    if err != nil {
        return 0
    }

    parts := strings.Fields(string(data))
    if len(parts) >= 5 {
        // Last field is the number of currently running processes
        running, _ := strconv.Atoi(parts[3])
        return running
    }

    return 0
}

func (m *SystemLoadMonitor) evaluateLoadEvents(newState *LoadInfo, lastState *LoadInfo) {
    // Check for high load
    if newState.Load1 >= m.config.Load1Threshold &&
        lastState.Load1 < m.config.Load1Threshold {
        m.onHighLoad(newState)
    }

    // Check for load spike
    if lastState.Load1 > 0 {
        spikeRatio := newState.Load1 / lastState.Load1
        if spikeRatio >= m.config.SpikeMultiplier && spikeRatio < 10 {
            m.onLoadSpike(newState, lastState, spikeRatio)
        }
    }

    // Check for return to normal
    if newState.Load1 < m.config.Load1Threshold*0.8 &&
        lastState.Load1 >= m.config.Load1Threshold {
        m.onLoadNormal(newState)
    }

    // Check process queue
    if newState.ProcessQueue >= m.config.ProcessQueueLimit &&
        lastState.ProcessQueue < m.config.ProcessQueueLimit {
        m.onHighProcessQueue(newState)
    }
}

func (m *SystemLoadMonitor) onHighLoad(state *LoadInfo) {
    if !m.config.SoundOnHigh {
        return
    }

    key := "high"
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemLoadMonitor) onLoadSpike(newState *LoadInfo, lastState *LoadInfo, ratio float64) {
    if !m.config.SoundOnSpike {
        return
    }

    key := "spike"
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["spike"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemLoadMonitor) onLoadNormal(state *LoadInfo) {
    if !m.config.SoundOnNormal {
        return
    }

    key := "normal"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["normal"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SystemLoadMonitor) onHighProcessQueue(state *LoadInfo) {
    // Optional: sound for high process queue
}

func (m *SystemLoadMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/loadavg | File | Free | Load average |
| /proc/stat | File | Free | Process info |

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
| macOS | Supported | Uses sysctl, uptime |
| Linux | Supported | Uses /proc/loadavg |
