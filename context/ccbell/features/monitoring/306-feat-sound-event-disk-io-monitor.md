# Feature: Sound Event Disk I/O Monitor

Play sounds for disk I/O activity and saturation events.

## Summary

Monitor disk I/O operations, throughput, and latency, playing sounds when I/O becomes saturated or anomalous.

## Motivation

- I/O bottleneck detection
- Disk health awareness
- Performance monitoring
- Latency alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Disk I/O Events

| Event | Description | Example |
|-------|-------------|---------|
| I/O Saturation | High wait time | > 50ms await |
| High Throughput | Read/write surge | > 100 MB/s |
| High IOPS | I/O operation spike | > 1000 IOPS |
| I/O Error | Read/write failure | I/O error |

### Configuration

```go
type DiskIOMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDevices      []string          `json:"watch_devices"` // "disk0", "sda"
    WarningLatency    int               `json:"warning_latency_ms"` // 50 default
    CriticalLatency   int               `json:"critical_latency_ms"` // 100 default
    SoundOnSaturation bool              `json:"sound_on_saturation"]
    SoundOnError      bool              `json:"sound_on_error"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type DiskIOEvent struct {
    Device       string
    ReadBytes    int64
    WriteBytes   int64
    ReadOps      int64
    WriteOps     int64
    AvgLatency   float64
    IOPS         int64
    EventType    string // "saturation", "error", "spike"
}
```

### Commands

```bash
/ccbell:diskio status                 # Show disk I/O status
/ccbell:diskio add disk0              # Add device to watch
/ccbell:diskio remove disk0
/ccbell:diskio latency 50             # Set warning latency
/ccbell:diskio sound saturation <sound>
/ccbell:diskio test                   # Test disk I/O sounds
```

### Output

```
$ ccbell:diskio status

=== Sound Event Disk I/O Monitor ===

Status: Enabled
Warning Latency: 50ms
Critical Latency: 100ms

Watched Devices: 2

[1] disk0 (APFS)
    Read: 50 MB/s
    Write: 30 MB/s
    IOPS: 500
    Latency: 5ms
    Status: OK
    Sound: bundled:stop

[2] disk1 (External SSD)
    Read: 120 MB/s
    Write: 80 MB/s
    IOPS: 2,500
    Latency: 75ms
    Status: WARNING
    Sound: bundled:diskio-warning

Recent Events:
  [1] disk1: I/O Saturation (5 min ago)
       Latency: 75ms, IOPS: 2500
  [2] disk0: High Throughput (1 hour ago)
       150 MB/s sustained
  [3] disk1: I/O Error (2 hours ago)
       Read failed

I/O Statistics (Last Hour):
  - disk0: avg 30 MB/s
  - disk1: avg 80 MB/s

Sound Settings:
  Saturation: bundled:diskio-warning
  Error: bundled:diskio-error

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Disk I/O monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk I/O Monitor

```go
type DiskIOMonitor struct {
    config              *DiskIOMonitorConfig
    player              *audio.Player
    running             bool
    stopCh              chan struct{}
    deviceStats         map[string]*DiskIOStats
    lastAlertTime       map[string]time.Time
}

type DiskIOStats struct {
    Device        string
    ReadBytes     int64
    WriteBytes    int64
    ReadOps       int64
    WriteOps      int64
    AvgLatency    float64
    IOPS          int64
}

func (m *DiskIOMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceStats = make(map[string]*DiskIOStats)
    m.lastAlertTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DiskIOMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDiskIO()

    for {
        select {
        case <-ticker.C:
            m.checkDiskIO()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DiskIOMonitor) snapshotDiskIO() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinDiskIO()
    } else {
        m.snapshotLinuxDiskIO()
    }
}

func (m *DiskIOMonitor) snapshotDarwinDiskIO() {
    cmd := exec.Command("iostat", "-d", "-c", "2")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIOStatOutput(string(output))
}

func (m *DiskIOMonitor) snapshotLinuxDiskIO() {
    // Read /proc/diskstats
    data, err := os.ReadFile("/proc/diskstats")
    if err != nil {
        return
    }

    m.parseDiskstats(string(data))
}

func (m *DiskIOMonitor) checkDiskIO() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinDiskIO()
    } else {
        m.checkLinuxDiskIO()
    }
}

func (m *DiskIOMonitor) checkDarwinDiskIO() {
    cmd := exec.Command("iostat", "-d", "-c", "2")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIOStatOutput(string(output))
}

func (m *DiskIOMonitor) checkLinuxDiskIO() {
    data, err := os.ReadFile("/proc/diskstats")
    if err != nil {
        return
    }

    m.parseDiskstats(string(data))
}

func (m *DiskIOMonitor) parseIOStatOutput(output string) {
    lines := strings.Split(output, "\n")
    currentDevice := ""

    for _, line := range lines {
        if strings.HasPrefix(line, "       ") || strings.HasPrefix(line, "\t") {
            parts := strings.Fields(line)
            if len(parts) >= 6 {
                device := parts[0]
                if m.shouldWatchDevice(device) {
                    readKB, _ := strconv.ParseFloat(parts[2], 64)
                    writeKB, _ := strconv.ParseFloat(parts[3], 64)
                    util, _ := strconv.ParseFloat(parts[5], 64)

                    m.evaluateDiskIO(device, int64(readKB*1024), int64(writeKB*1024), util)
                }
            }
        }
    }
}

func (m *DiskIOMonitor) parseDiskstats(data string) {
    lines := strings.Split(data, "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 14 {
            continue
        }

        device := parts[2]
        if !m.shouldWatchDevice(device) {
            continue
        }

        readSectors, _ := strconv.ParseInt(parts[5], 10, 64)
        writeSectors, _ := strconv.ParseInt(parts[9], 10, 64)
        ioTicks, _ := strconv.ParseInt(parts[12], 10, 64)

        readBytes := readSectors * 512
        writeBytes := writeSectors * 512

        m.evaluateDiskIO(device, readBytes, writeBytes, float64(ioTicks))
    }
}

func (m *DiskIOMonitor) shouldWatchDevice(device string) bool {
    if len(m.config.WatchDevices) == 0 {
        return true
    }

    for _, d := range m.config.WatchDevices {
        if device == d {
            return true
        }
    }

    return false
}

func (m *DiskIOMonitor) evaluateDiskIO(device string, readBytes, writeBytes int64, utilization float64) {
    lastStats := m.deviceStats[device]

    // Calculate throughput
    throughput := readBytes + writeBytes

    // Estimate latency from utilization (rough approximation)
    avgLatency := utilization * 10 // Rough conversion

    // Check for saturation
    if avgLatency >= float64(m.config.CriticalLatency) {
        if lastStats == nil || lastStats.AvgLatency < float64(m.config.CriticalLatency) {
            m.onIOSaturation(device, avgLatency, throughput)
        }
    } else if avgLatency >= float64(m.config.WarningLatency) {
        if lastStats == nil || lastStats.AvgLatency < float64(m.config.WarningLatency) {
            m.onIOSaturation(device, avgLatency, throughput)
        }
    }

    // Update stats
    iops := (readBytes + writeBytes) / 4096 // Rough IOPS estimate
    m.deviceStats[device] = &DiskIOStats{
        Device:     device,
        ReadBytes:  readBytes,
        WriteBytes: writeBytes,
        IOPS:       iops,
        AvgLatency: avgLatency,
    }
}

func (m *DiskIOMonitor) onIOSaturation(device string, latency float64, throughput int64) {
    if !m.config.SoundOnSaturation {
        return
    }

    key := fmt.Sprintf("sat:%s", device)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["saturation"]
        if sound != "" {
            volume := 0.5
            if latency >= float64(m.config.CriticalLatency) {
                volume = 0.7
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *DiskIOMonitor) onIOError(device string) {
    if !m.config.SoundOnError {
        return
    }

    key := fmt.Sprintf("err:%s", device)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *DiskIOMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastAlertTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastAlertTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| iostat | System Tool | Free | I/O statistics |
| /proc/diskstats | File | Free | Linux disk I/O info |

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
| Linux | Supported | Uses /proc/diskstats |
| Windows | Not Supported | ccbell only supports macOS/Linux |
