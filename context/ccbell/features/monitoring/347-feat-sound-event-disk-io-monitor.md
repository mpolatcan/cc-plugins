# Feature: Sound Event Disk I/O Monitor

Play sounds for disk I/O threshold crossings and high latency events.

## Summary

Monitor disk I/O operations, throughput, and latency, playing sounds for disk I/O events.

## Motivation

- I/O awareness
- Performance degradation alerts
- Disk health indicators
- I/O bottleneck detection
- Storage performance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Disk I/O Events

| Event | Description | Example |
|-------|-------------|---------|
| High Read I/O | Read throughput high | 100MB/s |
| High Write I/O | Write throughput high | 50MB/s |
| High Latency | I/O wait increased | 50ms avg |
| I/O Queue Full | Queue depth maxed | 128 requests |
| Disk Nearly Full | Space below threshold | 10% free |

### Configuration

```go
type DiskIOMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDevices      []string          `json:"watch_devices"` // "sda", "nvme0", "*"
    ReadThresholdMB   int64             `json:"read_threshold_mb"` // 100 default
    WriteThresholdMB  int64             `json:"write_threshold_mb"` // 50 default
    LatencyThreshold  int               `json:"latency_threshold_ms"` // 50 default
    QueueDepthLimit   int               `json:"queue_depth_limit"` // 128 default
    SoundOnRead       bool              `json:"sound_on_read"`
    SoundOnWrite      bool              `json:"sound_on_write"`
    SoundOnLatency    bool              `json:"sound_on_latency"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type DiskIOEvent struct {
    Device      string
    ReadMBps    float64
    WriteMBps   float64
    IOPS        int64
    LatencyMs   float64
    QueueDepth  int
    EventType   string // "read", "write", "latency", "queue", "space"
}
```

### Commands

```bash
/ccbell:diskio status                 # Show disk I/O status
/ccbell:diskio add sda                # Add device to watch
/ccbell:diskio remove sda
/ccbell:diskio read 100               # Set read threshold MB/s
/ccbell:diskio latency 50             # Set latency threshold ms
/ccbell:diskio test                   # Test disk I/O sounds
```

### Output

```
$ ccbell:diskio status

=== Sound Event Disk I/O Monitor ===

Status: Enabled
Read Threshold: 100 MB/s
Write Threshold: 50 MB/s
Latency Threshold: 50 ms
Read Sounds: Yes
Write Sounds: Yes
Latency Sounds: Yes

Watched Devices: 2

[1] nvme0n1
    Status: ACTIVE
    Read: 245.3 MB/s
    Write: 89.5 MB/s
    IOPS: 45000
    Latency: 2.5 ms
    Queue: 32
    Sound: bundled:diskio-nvme

[2] sda (HDD)
    Status: ACTIVE
    Read: 15.2 MB/s
    Write: 8.5 MB/s
    IOPS: 150
    Latency: 45.2 ms
    Queue: 64
    Sound: bundled:diskio-hdd

Recent Events:
  [1] nvme0n1: High Read I/O (5 min ago)
       Read: 245.3 MB/s > 100 MB/s limit
  [2] sda: High Latency (10 min ago)
       Latency: 45.2 ms > 50 ms threshold
  [3] sda: I/O Queue High (1 hour ago)
       Queue: 110 requests

Disk I/O Statistics:
  Avg Read: 85 MB/s
  Avg Write: 35 MB/s
  Peak Latency: 120 ms

Sound Settings:
  Read: bundled:diskio-read
  Write: bundled:diskio-write
  Latency: bundled:diskio-latency

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Disk I/O monitoring doesn't play sounds directly:
- Monitoring feature using /proc/diskstats
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk I/O Monitor

```go
type DiskIOMonitor struct {
    config          *DiskIOMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    deviceState     map[string]*DiskIOInfo
    lastEventTime   map[string]time.Time
}

type DiskIOInfo struct {
    Device      string
    ReadBytes   int64
    WriteBytes  int64
    ReadIOPS    int64
    WriteIOPS   int64
    ReadMBps    float64
    WriteMBps   float64
    IOTime      int64
    QueueDepth  int
    LastUpdate  time.Time
}

func (m *DiskIOMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*DiskIOInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DiskIOMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDeviceState()

    for {
        select {
        case <-ticker.C:
            m.checkDeviceState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DiskIOMonitor) snapshotDeviceState() {
    m.readDiskStats()
}

func (m *DiskIOMonitor) checkDeviceState() {
    m.readDiskStats()
}

func (m *DiskIOMonitor) readDiskStats() {
    data, err := os.ReadFile("/proc/diskstats")
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    currentDevices := make(map[string]*DiskIOInfo)

    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 14 {
            continue
        }

        deviceName := parts[2]
        if !m.shouldWatchDevice(deviceName) {
            continue
        }

        readsCompleted, _ := strconv.ParseInt(parts[5], 10, 64)
        readsMerged, _ := strconv.ParseInt(parts[6], 10, 64)
        sectorsRead, _ := strconv.ParseInt(parts[7], 10, 64)
        writesCompleted, _ := strconv.ParseInt(parts[9], 10, 64)
        writesMerged, _ := strconv.ParseInt(parts[10], 10, 64)
        sectorsWritten, _ := strconv.ParseInt(parts[11], 10, 64)
        ioTime, _ := strconv.ParseInt(parts[12], 10, 64)
        weightedIO, _ := strconv.ParseInt(parts[13], 10, 64)

        // Calculate queue depth from weighted I/O
        queueDepth := int(weightedIO / 1000)

        info := &DiskIOInfo{
            Device:      deviceName,
            ReadBytes:   sectorsRead * 512,
            WriteBytes:  sectorsWritten * 512,
            ReadIOPS:    readsCompleted - readsMerged,
            WriteIOPS:   writesCompleted - writesMerged,
            IOTime:      ioTime,
            QueueDepth:  queueDepth,
            LastUpdate:  time.Now(),
        }

        currentDevices[deviceName] = info

        lastInfo := m.deviceState[deviceName]
        if lastInfo == nil {
            m.deviceState[deviceName] = info
            continue
        }

        // Calculate throughput
        duration := info.LastUpdate.Sub(lastInfo.LastUpdate).Seconds()
        if duration > 0 {
            readDelta := info.ReadBytes - lastInfo.ReadBytes
            writeDelta := info.WriteBytes - lastInfo.WriteBytes

            info.ReadMBps = float64(readDelta) / duration / 1024 / 1024
            info.WriteMBps = float64(writeDelta) / duration / 1024 / 1024

            // Evaluate events
            m.evaluateIOEvents(deviceName, info, lastInfo)
        }

        m.deviceState[deviceName] = info
    }
}

func (m *DiskIOMonitor) shouldWatchDevice(name string) bool {
    if len(m.config.WatchDevices) == 0 {
        return true
    }

    for _, dev := range m.config.WatchDevices {
        if dev == "*" || strings.HasPrefix(name, dev) {
            return true
        }
    }

    return false
}

func (m *DiskIOMonitor) evaluateIOEvents(name string, info *DiskIOInfo, last *DiskIOInfo) {
    // Check read threshold
    if info.ReadMBps >= float64(m.config.ReadThresholdMB) &&
        last.ReadMBps < float64(m.config.ReadThresholdMB) {
        m.onHighReadIO(name, info)
    }

    // Check write threshold
    if info.WriteMBps >= float64(m.config.WriteThresholdMB) &&
        last.WriteMBps < float64(m.config.WriteThresholdMB) {
        m.onHighWriteIO(name, info)
    }

    // Check queue depth
    if info.QueueDepth >= m.config.QueueDepthLimit &&
        last.QueueDepth < m.config.QueueDepthLimit {
        m.onQueueFull(name, info)
    }
}

func (m *DiskIOMonitor) onHighReadIO(name string, info *DiskIOInfo) {
    if !m.config.SoundOnRead {
        return
    }

    key := fmt.Sprintf("read:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["read"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DiskIOMonitor) onHighWriteIO(name string, info *DiskIOInfo) {
    if !m.config.SoundOnWrite {
        return
    }

    key := fmt.Sprintf("write:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["write"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DiskIOMonitor) onQueueFull(name string, info *DiskIOInfo) {
    if !m.config.SoundOnLatency {
        return
    }

    key := fmt.Sprintf("queue:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["latency"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DiskIOMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/diskstats | File | Free | Disk I/O statistics |
| iostat | System Tool | Free | Alternative stats |

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
| macOS | Supported | Uses iostat or diskutil |
| Linux | Supported | Uses /proc/diskstats |
