# Feature: Sound Event Network Packet Monitor

Play sounds for network packet rates, dropped packets, and traffic anomalies.

## Summary

Monitor network interface packet statistics for rate changes, drops, and anomalies, playing sounds for packet events.

## Motivation

- Network awareness
- Packet loss detection
- Traffic monitoring
- Anomaly detection
- Performance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Packet Events

| Event | Description | Example |
|-------|-------------|---------|
| High Packet Rate | Packets > threshold | > 10000/s |
| Packet Drop | Dropped packets | drops detected |
| Error Rate | Error rate high | errors > 1% |
| Traffic Spike | Sudden spike | doubled |
| Packet Flood | Possible flood | SYN flood |
| Collision | Collision detected | collision |

### Configuration

```go
type NetworkPacketMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchInterfaces  []string          `json:"watch_interfaces"` // "eth0", "en0", "*"
    PacketThreshold  int               `json:"packet_threshold"` // 10000 per second
    DropThreshold    int               `json:"drop_threshold"` // 100 per second
    ErrorThreshold   float64           `json:"error_threshold"` // 0.01 (1%)
    SoundOnHighRate  bool              `json:"sound_on_high_rate"`
    SoundOnDrop      bool              `json:"sound_on_drop"`
    SoundOnError     bool              `json:"sound_on_error"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:packet status               # Show packet status
/ccbell:packet add eth0             # Add interface to watch
/ccbell:packet threshold 10000      # Set packet threshold
/ccbell:packet sound drop <sound>
/ccbell:packet test                 # Test packet sounds
```

### Output

```
$ ccbell:packet status

=== Sound Event Network Packet Monitor ===

Status: Enabled
Packet Threshold: 10000/s
Drop Threshold: 100/s

Network Packet Status:

[1] eth0
    Status: HEALTHY
    RX Packets: 5,234,567
    TX Packets: 3,456,789
    Packets/s: 2,500
    RX Drops: 0/s
    TX Drops: 0/s
    Errors: 0.01%
    Sound: bundled:packet-eth0

[2] wlan0
    Status: WARNING *** WARNING ***
    RX Packets: 1,234,567
    TX Packets: 567,890
    Packets/s: 12,000 *** HIGH ***
    RX Drops: 150/s *** HIGH ***
    Errors: 0.5%
    Sound: bundled:packet-wlan0 *** FAILED ***

Recent Events:

[1] wlan0: High Packet Rate (5 min ago)
       12000/s > 10000/s threshold
       Sound: bundled:packet-highrate
  [2] wlan0: Packet Drop (10 min ago)
       150 drops/s > 100/s threshold
       Sound: bundled:packet-drop
  [3] eth0: Traffic Spike (1 hour ago)
       Packets doubled in 1 minute
       Sound: bundled:packet-spike

Packet Statistics:
  Total RX: 6,469,134
  Total TX: 4,024,679
  Drops Today: 500
  Errors Today: 12

Sound Settings:
  High Rate: bundled:packet-highrate
  Drop: bundled:packet-drop
  Error: bundled:packet-error
  Spike: bundled:packet-spike

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Packet monitoring doesn't play sounds directly:
- Monitoring feature using netstat, ifconfig, ip
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Network Packet Monitor

```go
type NetworkPacketMonitor struct {
    config        *NetworkPacketMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    packetState   map[string]*PacketInfo
    lastEventTime map[string]time.Time
}

type PacketInfo struct {
    Name         string
    Status       string // "healthy", "warning", "critical"
    RXPackets    int64
    TXPackets    int64
    PacketsPerSec float64
    RXDrops      float64
    TXDrops      float64
    RXErrors     float64
    TXErrors     float64
    ErrorRate    float64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| netstat | System Tool | Free | Network statistics |
| ifconfig | System Tool | Free | Interface config |
| ip | System Tool | Free | Network configuration |

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
| macOS | Supported | Uses netstat, ifconfig |
| Linux | Supported | Uses ip, /proc/net/dev |
