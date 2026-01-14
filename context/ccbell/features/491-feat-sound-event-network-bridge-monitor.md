# Feature: Sound Event Network Bridge Monitor

Play sounds for network bridge status changes, interface membership, and forwarding events.

## Summary

Monitor network bridges (br0, bridge0) for status changes, port membership, and forwarding state, playing sounds for bridge events.

## Motivation

- Bridge awareness
- Network virtualization
- Interface management
- Forwarding status
- VLAN bridging

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Bridge Events

| Event | Description | Example |
|-------|-------------|---------|
| Bridge Up | Bridge activated | up |
| Bridge Down | Bridge deactivated | down |
| Port Added | Interface added | eth0 added |
| Port Removed | Interface removed | eth0 removed |
| Forwarding State | Forwarding changed | forwarding |
| STP Change | Spanning tree state | stp state |

### Configuration

```go
type NetworkBridgeMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchBridges     []string          `json:"watch_bridges"` // "br0", "*"
    SoundOnUp        bool              `json:"sound_on_up"]
    SoundOnDown      bool              `json:"sound_on_down"]
    SoundOnPort      bool              `json:"sound_on_port"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:bridge status               # Show bridge status
/ccbell:bridge add br0              # Add bridge to watch
/ccbell:bridge sound up <sound>
/ccbell:bridge test                 # Test bridge sounds
```

### Output

```
$ ccbell:bridge status

=== Sound Event Network Bridge Monitor ===

Status: Enabled
Watch Bridges: all

Bridge Status:

[1] br0 (bridge)
    Status: UP
    Interfaces: 2
    Members: eth0, wlan0
    Forwarding: FORWARDING
    STP: Disabled
    Age: 120 seconds
    Sound: bundled:bridge-br0

[2] docker0 (bridge)
    Status: UP
    Interfaces: 1
    Members: veth1234567
    Forwarding: FORWARDING
    STP: Disabled
    Age: 86400 seconds
    Sound: bundled:bridge-docker

Recent Events:

[1] br0: Interface Added (5 min ago)
       wlan0 added to bridge
       Sound: bundled:bridge-port-add
  [2] docker0: Bridge Up (1 hour ago)
       Bridge interface activated
       Sound: bundled:bridge-up
  [3] br0: Forwarding State Changed (2 hours ago)
       Forwarding: DISABLED -> FORWARDING
       Sound: bundled:bridge-forward

Bridge Statistics:
  Total Bridges: 2
  Up: 2
  Down: 0
  Ports Total: 3

Sound Settings:
  Up: bundled:bridge-up
  Down: bundled:bridge-down
  Port Add: bundled:bridge-port-add
  Port Remove: bundled:bridge-port-remove

[Configure] [Add Bridge] [Test All]
```

---

## Audio Player Compatibility

Bridge monitoring doesn't play sounds directly:
- Monitoring feature using brctl, bridge, ip
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Network Bridge Monitor

```go
type NetworkBridgeMonitor struct {
    config        *NetworkBridgeMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    bridgeState   map[string]*BridgeInfo
    lastEventTime map[string]time.Time
}

type BridgeInfo struct {
    Name        string
    Status      string // "up", "down"
    Members     []string
    Forwarding  string // "forwarding", "disabled", "blocking"
    STP         string // "enabled", "disabled"
    Age         int // seconds
    PortCount   int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| brctl | System Tool | Free | Bridge control |
| bridge | System Tool | Free | Bridge utilities |
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
| macOS | Limited | Limited bridge support |
| Linux | Supported | Uses brctl, bridge, ip |
