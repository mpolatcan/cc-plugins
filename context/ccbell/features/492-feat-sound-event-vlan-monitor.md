# Feature: Sound Event VLAN Monitor

Play sounds for VLAN status changes, tagging events, and membership modifications.

## Summary

Monitor VLAN interfaces for status changes, tag modifications, and port membership, playing sounds for VLAN events.

## Motivation

- VLAN awareness
- Network segmentation
- Tag management
- Membership tracking
- Trunk monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### VLAN Events

| Event | Description | Example |
|-------|-------------|---------|
| VLAN Up | VLAN interface activated | up |
| VLAN Down | VLAN interface deactivated | down |
| Tag Changed | VLAN ID modified | 100 -> 200 |
| Member Added | Port added to VLAN | eth0 added |
| Member Removed | Port removed from VLAN | eth0 removed |
| Native VLAN | Native VLAN changed | native change |

### Configuration

```go
type VLANMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchVLANs       []string          `json:"watch_vlans"` // "eth0.100", "*"
    SoundOnUp        bool              `json:"sound_on_up"`
    SoundOnDown      bool              `json:"sound_on_down"`
    SoundOnTag       bool              `json:"sound_on_tag"`
    SoundOnMember    bool              `json:"sound_on_member"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:vlan status                # Show VLAN status
/ccbell:vlan add eth0.100          # Add VLAN to watch
/ccbell:vlan sound up <sound>
/ccbell:vlan test                  # Test VLAN sounds
```

### Output

```
$ ccbell:vlan status

=== Sound Event VLAN Monitor ===

Status: Enabled
Watch VLANs: all

VLAN Status:

[1] eth0.100 (VLAN 100)
    Status: UP
    Parent: eth0
    Tag: 100
    Members: 1
    Native: No
    Sound: bundled:vlan-eth0.100

[2] eth0.200 (VLAN 200)
    Status: UP
    Parent: eth0
    Tag: 200
    Members: 2
    Native: Yes
    Sound: bundled:vlan-eth0.200

[3] bond0.300 (VLAN 300)
    Status: DOWN
    Parent: bond0
    Tag: 300
    Members: 0
    Native: No
    Sound: bundled:vlan-bond0.300

Recent Events:

[1] eth0.200: VLAN Up (5 min ago)
       VLAN interface activated
       Sound: bundled:vlan-up
  [2] eth0.100: Member Added (10 min ago)
       eth1 added to VLAN 100
       Sound: bundled:vlan-member
  [3] eth0.200: Native VLAN Changed (30 min ago)
       Native VLAN set to 200
       Sound: bundled:vlan-native

VLAN Statistics:
  Total VLANs: 3
  Up: 2
  Down: 1
  Native VLANs: 1

Sound Settings:
  Up: bundled:vlan-up
  Down: bundled:vlan-down
  Tag: bundled:vlan-tag
  Member: bundled:vlan-member

[Configure] [Add VLAN] [Test All]
```

---

## Audio Player Compatibility

VLAN monitoring doesn't play sounds directly:
- Monitoring feature using ip, bridge, vconfig
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### VLAN Monitor

```go
type VLANMonitor struct {
    config        *VLANMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    vlanState     map[string]*VLANInfo
    lastEventTime map[string]time.Time
}

type VLANInfo struct {
    Name       string
    Parent     string
    Status     string // "up", "down"
    Tag        int
    Members    []string
    IsNative   bool
    Protocol   string // "802.1q"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ip | System Tool | Free | VLAN configuration |
| bridge | System Tool | Free | Bridge VLANs |
| vconfig | System Tool | Free | VLAN configuration |

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
| macOS | Limited | Limited VLAN support |
| Linux | Supported | Uses ip, bridge, vconfig |
