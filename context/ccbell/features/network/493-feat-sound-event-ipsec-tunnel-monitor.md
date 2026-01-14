# Feature: Sound Event IPsec Tunnel Monitor

Play sounds for IPsec tunnel status changes, negotiation events, and security associations.

## Summary

Monitor IPsec tunnels (SAs, SPs) for status changes, key renegotiation, and tunnel up/down events, playing sounds for IPsec events.

## Motivation

- VPN awareness
- Security monitoring
- Tunnel status
- Key management
- Encryption status

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### IPsec Tunnel Events

| Event | Description | Example |
|-------|-------------|---------|
| Tunnel Up | SA established | up |
| Tunnel Down | SA deleted | down |
| Rekey | Key renegotiation | rekey |
| DPD Failure | Dead peer detection | dpd fail |
| Child SA Up | Child SA created | child sa |
| Child SA Down | Child SA deleted | child down |

### Configuration

```go
type IPsecTunnelMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchTunnels     []string          `json:"watch_tunnels"` // "tunnel1", "*"
    SoundOnUp        bool              `json:"sound_on_up"`
    SoundOnDown      bool              `json:"sound_on_down"`
    SoundOnRekey     bool              `json:"sound_on_rekey"`
    SoundOnDPD       bool              `json:"sound_on_dpd"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:ipsec status               # Show IPsec status
/ccbell:ipsec add tunnel1          # Add tunnel to watch
/ccbell:ipsec sound up <sound>
/ccbell:ipsec test                 # Test IPsec sounds
```

### Output

```
$ ccbell:ipsec status

=== Sound Event IPsec Tunnel Monitor ===

Status: Enabled
Watch Tunnels: all

IPsec Tunnel Status:

[1] office-vpn (IKEv2)
    Status: UP *** ACTIVE ***
    Remote: 203.0.113.1
    Local: 192.168.1.100
    Encryption: AES-256-GCM
    Lifetime: 3600 sec
    Traffic: 1.2 GB in, 500 MB out
    Sound: bundled:ipsec-office-vpn *** ACTIVE ***

[2] home-vpn (IKEv1)
    Status: DOWN
    Remote: 198.51.100.2
    Local: 192.168.1.101
    Encryption: AES-128
    Lifetime: 28800 sec
    Traffic: 0
    Sound: bundled:ipsec-home-vpn

[3] cloud-tunnel (IKEv2)
    Status: UP
    Remote: 203.0.113.5
    Local: 192.168.1.102
    Encryption: ChaCha20-Poly1305
    Lifetime: 3600 sec
    Traffic: 500 MB in, 200 MB out
    Sound: bundled:ipsec-cloud

Recent Events:

[1] office-vpn: Tunnel Up (5 min ago)
       IKE SA established
       Sound: bundled:ipsec-up
  [2] home-vpn: Tunnel Down (10 min ago)
       IKE SA deleted
       Sound: bundled:ipsec-down
  [3] office-vpn: Rekey (30 min ago)
       Key renegotiation successful
       Sound: bundled:ipsec-rekey

IPsec Statistics:
  Total Tunnels: 3
  Up: 2
  Down: 1
  Rekeys: 15

Sound Settings:
  Up: bundled:ipsec-up
  Down: bundled:ipsec-down
  Rekey: bundled:ipsec-rekey
  DPD: bundled:ipsec-dpd

[Configure] [Add Tunnel] [Test All]
```

---

## Audio Player Compatibility

IPsec monitoring doesn't play sounds directly:
- Monitoring feature using ipsec, setkey, swanctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### IPsec Tunnel Monitor

```go
type IPsecTunnelMonitor struct {
    config        *IPsecTunnelMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    tunnelState   map[string]*TunnelInfo
    lastEventTime map[string]time.Time
}

type TunnelInfo struct {
    Name       string
    Status     string // "up", "down"
    Remote     string
    Local      string
    Encryption string
    Protocol   string // "IKEv1", "IKEv2"
    Lifetime   int // seconds
    TrafficIn  int64
    TrafficOut int64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ipsec | System Tool | Free | IPsec tools (strongSwan/libreswan) |
| setkey | System Tool | Free | IPsec key management |
| swanctl | System Tool | Free | strongSwan management |

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
| macOS | Supported | Uses native IPsec or strongSwan |
| Linux | Supported | Uses ipsec, setkey, swanctl |
