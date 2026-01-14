# Feature: Sound Event I/O Wait Monitor

Play sounds for I/O wait percentage, disk latency, and queue depth alerts.

## Summary

Monitor I/O wait percentages, disk latency, and queue depths for performance degradation, playing sounds for I/O events.

## Motivation

- I/O performance
- Latency alerts
- Queue monitoring
- Disk health
- Performance optimization

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### I/O Wait Events

| Event | Description | Example |
|-------|-------------|---------|
| High I/O Wait | Wait > 20% | 30% wait |
| High Latency | Latency > 100ms | 200ms |
| Queue Full | Queue depth maxed | 100% full |
| Disk Slow | Slow disk | slow read |
| Read Error | Read failed | error |
| Write Error | Write failed | error |

### Configuration

```go
type IOWaitMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchDevices    []string          `json:"watch_devices"` // "sda", "nvme0", "*"
    WaitThreshold   float64           `json:"wait_threshold"` // 20.0
    LatencyThreshold int              `json:"latency_threshold_ms"` // 100
    QueueThreshold  int               `json:"queue_threshold"` // 80
    SoundOnWait     bool              `json:"sound_on_wait"`
    SoundOnLatency  bool              `json:"sound_on_latency"`
    SoundOnQueue    bool              `json:"sound_on_queue"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:iowait status               # Show I/O wait status
/ccbell:iowait add sda              # Add device to watch
/ccbell:iowait wait 20              # Set wait threshold
/ccbell:iowait sound wait <sound>
/ccbell:iowait test                 # Test I/O wait sounds
```

### Output

```
$ ccbell:iowait status

=== Sound Event I/O Wait Monitor ===

Status: Enabled
Wait Threshold: 20%
Latency Threshold: 100ms

I/O Wait Status:

[1] sda (SSD)
    Status: HEALTHY
    I/O Wait: 2.5%
    Read: 15 MB/s
    Write: 25 MB/s
    Latency: 5ms
    Queue: 2/32 (6%)
    Sound: bundled:iowait-sda

[2] sdb (HDD)
    Status: WARNING *** WARNING ***
    I/O Wait: 35% *** HIGH ***
    Read: 50 MB/s
    Write: 40 MB/s
    Latency: 150ms *** HIGH ***
    Queue: 28/32 (87%) *** NEAR FULL ***
    Sound: bundled:iowait-sdb *** FAILED ***

Recent Events:

[1] sdb: High I/O Wait (5 min ago)
       35% > 20% threshold
       Sound: bundled:iowait-wait
  [2] sdb: High Latency (10 min ago)
       150ms > 100ms threshold
       Sound: bundled:iowait-latency
  [3] sda: Queue Near Full (1 hour ago)
       Queue 87% full
       Sound: bundled:iowait-queue

I/O Statistics:
  Total Devices: 2
  Healthy: 1
  Warning: 1
  Avg I/O Wait: 18%

Sound Settings:
  Wait: bundled:iowait-wait
  Latency: bundled:iowait-latency
  Queue: bundled:iowait-queue
  Error: bundled:iowait-error

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

I/O wait monitoring doesn't play sounds directly:
- Monitoring feature using iostat, sar
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### I/O Wait Monitor

```go
type IOWaitMonitor struct {
    config        *IOWaitMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    deviceState   map[string]*DeviceInfo
    lastEventTime map[string]time.Time
}

type DeviceInfo struct {
    Name       string
    Status     string // "healthy", "warning", "critical"
    IOWait     float64
    ReadMBps   float64
    WriteMBps  float64
    LatencyMs  int
    QueueDepth int
    MaxQueue   int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| iostat | System Tool | Free | I/O statistics |
| sar | System Tool | Free | System activity reporter |

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
| macOS | Supported | Uses iostat |
| Linux | Supported | Uses iostat, sar |
