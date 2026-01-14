# Feature: Sound Event DHCP Lease Monitor

Play sounds for DHCP lease changes, expiration warnings, and address assignments.

## Summary

Monitor DHCP leases for status changes, expiration warnings, renewal failures, and new address assignments, playing sounds for DHCP events.

## Motivation

- IP address awareness
- Lease tracking
- Network reliability
- Renewal alerts
- Address management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### DHCP Lease Events

| Event | Description | Example |
|-------|-------------|---------|
| Lease Acquired | New IP assigned | 192.168.1.100 |
| Lease Renewed | Lease extended | renewed |
| Lease Expired | IP expired | expired |
| Lease Released | Manual release | released |
| Renewal Warning | < 1 hour left | warning |
| Bound | DHCP client bound | bound |

### Configuration

```go
type DHCPLeaseMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchInterfaces  []string          `json:"watch_interfaces"` // "eth0", "*"
    WarningMinutes   int               `json:"warning_minutes"` // 60 default
    SoundOnAcquire   bool              `json:"sound_on_acquire"`
    SoundOnExpire    bool              `json:"sound_on_expire"`
    SoundOnWarning   bool              `json:"sound_on_warning"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:dhcp status                # Show DHCP lease status
/ccbell:dhcp add eth0              # Add interface to watch
/ccbell:dhcp sound acquire <sound>
/ccbell:dhcp test                  # Test DHCP sounds
```

### Output

```
$ ccbell:dhcp status

=== Sound Event DHCP Lease Monitor ===

Status: Enabled
Warning: 60 minutes before expiry
Watch Interfaces: all

DHCP Lease Status:

[1] eth0
    Status: BOUND *** ACTIVE ***
    IP Address: 192.168.1.100
    Gateway: 192.168.1.1
    DNS: 8.8.8.8, 8.8.4.4
    Lease Time: 24 hours
    Remaining: 18 hours
    Expires: Tomorrow 10:30 AM
    Sound: bundled:dhcp-eth0 *** ACTIVE ***

[2] wlan0
    Status: RENEWING
    IP Address: 192.168.0.105
    Gateway: 192.168.0.1
    DNS: 192.168.0.1
    Lease Time: 12 hours
    Remaining: 2 hours *** WARNING ***
    Expires: Today 4:30 PM
    Sound: bundled:dhcp-wlan0 *** WARNING ***

[3] docker0
    Status: UNBOUND
    IP Address: 172.17.0.1
    Gateway: N/A
    DNS: N/A
    Lease Time: N/A
    Remaining: N/A
    Sound: bundled:dhcp-docker0

Recent Events:

[1] eth0: Lease Acquired (5 min ago)
       IP 192.168.1.100 assigned
       Sound: bundled:dhcp-acquire
  [2] wlan0: Renewal Warning (10 min ago)
       Lease expires in 2 hours
       Sound: bundled:dhcp-warning
  [3] eth0: Lease Renewed (1 hour ago)
       Lease extended for 24 hours
       Sound: bundled:dhcp-renew

DHCP Statistics:
  Total Interfaces: 3
  Bound: 1
  Renewing: 1
  Unbound: 1
  Warnings: 1

Sound Settings:
  Acquire: bundled:dhcp-acquire
  Expire: bundled:dhcp-expire
  Warning: bundled:dhcp-warning
  Renew: bundled:dhcp-renew

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

DHCP monitoring doesn't play sounds directly:
- Monitoring feature using dhclient, networksetup, nmcli
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### DHCP Lease Monitor

```go
type DHCPLeaseMonitor struct {
    config        *DHCPLeaseMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    leaseState    map[string]*LeaseInfo
    lastEventTime map[string]time.Time
}

type LeaseInfo struct {
    Interface   string
    Status      string // "bound", "renewing", "rebinding", "unbound"
    IPAddress   string
    Gateway     string
    DNS         []string
    LeaseTime   int // seconds
    Remaining   int // seconds
    ExpiresAt   time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dhclient | System Tool | Free | DHCP client |
| networksetup | System Tool | Free | macOS network config |
| nmcli | System Tool | Free | NetworkManager |
| systemd-resolve | System Tool | Free | DNS resolution |

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
| macOS | Supported | Uses networksetup, dhclient |
| Linux | Supported | Uses dhclient, nmcli, systemd-resolve |
