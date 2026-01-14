# Feature: Sound Event Network Bandwidth Monitor

Play sounds for network bandwidth threshold crossings and traffic spikes.

## Summary

Monitor network interface traffic, bandwidth usage, and data transfer thresholds, playing sounds for bandwidth events.

## Motivation

- Network awareness
- Bandwidth quota alerts
- Traffic spike detection
- Data transfer notifications
- Network congestion awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Bandwidth Events

| Event | Description | Example |
|-------|-------------|---------|
| Bandwidth Threshold | Traffic above threshold | 100MB/s detected |
| Traffic Spike | Sudden traffic increase | 10x normal rate |
| Daily Quota | Daily limit reached | 5GB quota used |
| Interface Up | Network up | eth0 connected |
| Interface Down | Network down | eth0 disconnected |

### Configuration

```go
type NetworkBandwidthMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchInterfaces   []string          `json:"watch_interfaces"` // "eth0", "en0", "*"
    UploadThreshold   int64             `json:"upload_threshold_mbps"` // 100 default
    DownloadThreshold int64             `json:"download_threshold_mbps"` // 100 default
    SpikeMultiplier   float64           `json:"spike_multiplier"` // 10.0 default
    DailyQuotaMB      int64             `json:"daily_quota_mb"` // 0 = disabled
    SoundOnThreshold  bool              `json:"sound_on_threshold"`
    SoundOnSpike      bool              `json:"sound_on_spike"`
    SoundOnQuota      bool              `json:"sound_on_quota"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type NetworkBandwidthEvent struct {
    Interface  string
    UploadMbps float64
    DownloadMbps float64
    DailyUsage int64 // MB
    EventType  string // "threshold", "spike", "quota", "up", "down"
}
```

### Commands

```bash
/ccbell:bandwidth status              # Show bandwidth status
/ccbell:bandwidth add eth0            # Add interface to watch
/ccbell:bandwidth threshold 100       # Set threshold in Mbps
/ccbell:bandwidth quota 5000          # Set daily quota in MB
/ccbell:bandwidth sound threshold <sound>
/ccbell:bandwidth test                # Test bandwidth sounds
```

### Output

```
$ ccbell:bandwidth status

=== Sound Event Network Bandwidth Monitor ===

Status: Enabled
Upload Threshold: 100 Mbps
Download Threshold: 100 Mbps
Daily Quota: 5000 MB
Threshold Sounds: Yes
Spike Sounds: Yes

Watched Interfaces: 2

[1] eth0
    Status: UP
    Upload: 45.2 Mbps
    Download: 128.5 Mbps
    Daily: 2456 MB
    Sound: bundled:bandwidth-eth0

[2] wlan0
    Status: UP
    Upload: 2.1 Mbps
    Download: 15.3 Mbps
    Daily: 512 MB
    Sound: bundled:bandwidth-wifi

Recent Events:
  [1] eth0: Traffic Spike (5 min ago)
       Upload: 2.1 -> 45.2 Mbps (21x normal)
  [2] eth0: Threshold Exceeded (10 min ago)
       Download: 128.5 Mbps > 100 Mbps limit
  [3] wlan0: Interface Up (1 hour ago)
       Connected to network

Bandwidth Statistics:
  Avg Upload: 25 Mbps
  Avg Download: 65 Mbps
  Total Today: 2.9 GB

Sound Settings:
  Threshold: bundled:bandwidth-threshold
  Spike: bundled:bandwidth-spike
  Quota: bundled:bandwidth-quota

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Network bandwidth monitoring doesn't play sounds directly:
- Monitoring feature using /proc/net/dev
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Bandwidth Monitor

```go
type NetworkBandwidthMonitor struct {
    config          *NetworkBandwidthMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    interfaceState  map[string]*InterfaceBandwidthInfo
    lastEventTime   map[string]time.Time
}

type InterfaceBandwidthInfo struct {
    Interface   string
    Status      string // "up", "down"
    UploadRx    int64  // bytes
    UploadTx    int64  // bytes
    DownloadRx  int64  // bytes
    DownloadTx  int64  // bytes
    UploadMbps  float64
    DownloadMbps float64
    DailyUsage  int64 // MB
    LastUpdate  time.Time
}

func (m *NetworkBandwidthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.interfaceState = make(map[string]*InterfaceBandwidthInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkBandwidthMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotInterfaceState()

    for {
        select {
        case <-ticker.C:
            m.checkInterfaceState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkBandwidthMonitor) snapshotInterfaceState() {
    m.readInterfaceStats()
}

func (m *NetworkBandwidthMonitor) checkInterfaceState() {
    m.readInterfaceStats()
}

func (m *NetworkBandwidthMonitor) readInterfaceStats() {
    // Read from /proc/net/dev on Linux
    data, err := os.ReadFile("/proc/net/dev")
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    currentInterfaces := make(map[string]*InterfaceBandwidthInfo)

    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) < 10 {
            continue
        }

        interfaceName := strings.TrimSuffix(parts[0], ":")
        if !m.shouldWatchInterface(interfaceName) {
            continue
        }

        rxBytes, _ := strconv.ParseInt(parts[1], 10, 64)
        txBytes, _ := strconv.ParseInt(parts[9], 10, 64)

        info := &InterfaceBandwidthInfo{
            Interface: interfaceName,
            DownloadRx: rxBytes,
            UploadTx:   txBytes,
            LastUpdate: time.Now(),
        }

        currentInterfaces[interfaceName] = info

        lastInfo := m.interfaceState[interfaceName]
        if lastInfo == nil {
            m.interfaceState[interfaceName] = info
            m.onInterfaceUp(interfaceName)
            continue
        }

        // Calculate bandwidth
        duration := info.LastUpdate.Sub(lastInfo.LastUpdate).Seconds()
        if duration > 0 {
            rxDelta := info.DownloadRx - lastInfo.DownloadRx
            txDelta := info.UploadTx - lastInfo.UploadTx

            info.DownloadMbps = float64(rxDelta*8) / duration / 1000000
            info.UploadMbps = float64(txDelta*8) / duration / 1000000

            // Update daily usage
            info.DailyUsage = lastInfo.DailyUsage + (rxDelta+txDelta)/(1024*1024)

            // Check thresholds
            m.evaluateBandwidthEvents(interfaceName, info, lastInfo)
        }

        // Check status change
        if lastInfo.Status == "down" && info.Status != "down" {
            m.onInterfaceUp(interfaceName)
        }

        m.interfaceState[interfaceName] = info
    }

    // Check for down interfaces
    for name, lastInfo := range m.interfaceState {
        if _, exists := currentInterfaces[name]; !exists {
            m.interfaceState[name].Status = "down"
            m.onInterfaceDown(name)
        }
    }
}

func (m *NetworkBandwidthMonitor) shouldWatchInterface(name string) bool {
    if len(m.config.WatchInterfaces) == 0 {
        return true
    }

    for _, iface := range m.config.WatchInterfaces {
        if iface == "*" || iface == name {
            return true
        }
    }

    return false
}

func (m *NetworkBandwidthMonitor) evaluateBandwidthEvents(name string, info *InterfaceBandwidthInfo, last *InterfaceBandwidthInfo) {
    // Check threshold
    if info.DownloadMbps >= float64(m.config.DownloadThreshold) &&
        last.DownloadMbps < float64(m.config.DownloadThreshold) {
        m.onBandwidthThreshold(name, info, "download")
    }

    if info.UploadMbps >= float64(m.config.UploadThreshold) &&
        last.UploadMbps < float64(m.config.UploadThreshold) {
        m.onBandwidthThreshold(name, info, "upload")
    }

    // Check spike
    if last.DownloadMbps > 0 {
        spikeRatio := info.DownloadMbps / last.DownloadMbps
        if spikeRatio >= m.config.SpikeMultiplier {
            m.onTrafficSpike(name, info, spikeRatio)
        }
    }

    // Check quota
    if m.config.DailyQuotaMB > 0 && info.DailyUsage >= m.config.DailyQuotaMB &&
        last.DailyUsage < m.config.DailyQuotaMB {
        m.onDailyQuotaReached(name, info)
    }
}

func (m *NetworkBandwidthMonitor) onBandwidthThreshold(name string, info *InterfaceBandwidthInfo, direction string) {
    if !m.config.SoundOnThreshold {
        return
    }

    key := fmt.Sprintf("threshold:%s:%s", name, direction)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["threshold"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkBandwidthMonitor) onTrafficSpike(name string, info *InterfaceBandwidthInfo, ratio float64) {
    if !m.config.SoundOnSpike {
        return
    }

    key := fmt.Sprintf("spike:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["spike"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *NetworkBandwidthMonitor) onDailyQuotaReached(name string, info *InterfaceBandwidthInfo) {
    if !m.config.SoundOnQuota {
        return
    }

    key := fmt.Sprintf("quota:%s", name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["quota"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *NetworkBandwidthMonitor) onInterfaceUp(name string) {
    // Optional: sound when interface comes up
}

func (m *NetworkBandwidthMonitor) onInterfaceDown(name string) {
    // Optional: sound when interface goes down
}

func (m *NetworkBandwidthMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/net/dev | File | Free | Network statistics |
| netstat | System Tool | Free | Network stats (optional) |

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
| macOS | Supported | Uses netstat or ifconfig |
| Linux | Supported | Uses /proc/net/dev |
