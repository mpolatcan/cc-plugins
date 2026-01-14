# Feature: Sound Event SSH Key Expiry Monitor

Play sounds for SSH key expiration, rotation requirements, and deprecated algorithm warnings.

## Summary

Monitor SSH keys (authorized_keys, known_hosts, certificates) for expiration dates, deprecated algorithms, and rotation needs, playing sounds for SSH key events.

## Motivation

- Key security
- Expiration alerts
- Algorithm updates
- Certificate tracking
- Compliance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSH Key Events

| Event | Description | Example |
|-------|-------------|---------|
| Key Expiring Soon | < 30 days | 15 days left |
| Key Expired | Key expired | past expiry |
| Deprecated Algo | Old algorithm | RSA-1024 |
| Key Added | New key added | added |
| Key Removed | Key removed | removed |
| Cert Expiring | Certificate expiring | 7 days |

### Configuration

```go
type SSHKeyExpiryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "~/.ssh", "/etc/ssh", "*"
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    CheckAlgorithms   bool              `json:"check_algorithms"` // true default
    SoundOnExpiring   bool              `json:"sound_on_expiring"`
    SoundOnExpired    bool              `json:"sound_on_expired"`
    SoundOnDeprecated bool              `json:"sound_on_deprecated"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_hours"` // 24 default
}
```

### Commands

```bash
/ccbell:sshkey status               # Show SSH key status
/ccbell:sshkey add ~/.ssh           # Add path to watch
/ccbell:sshkey warning 30           # Set warning days
/ccbell:sshkey sound expiring <sound>
/ccbell:sshkey test                 # Test SSH key sounds
```

### Output

```
$ ccbell:sshkey status

=== Sound Event SSH Key Expiry Monitor ===

Status: Enabled
Warning: 30 days
Critical: 7 days

SSH Key Status:

[1] ~/.ssh/id_rsa
    Status: VALID
    Type: RSA 2048
    Expires: Never
    Comment: user@host
    Sound: bundled:sshkey-rsa

[2] ~/.ssh/id_ed25519
    Status: VALID
    Type: ED25519
    Expires: Never
    Comment: user@host
    Sound: bundled:sshkey-ed25519

[3] /etc/ssh/ssh_host_rsa_key
    Status: EXPIRING SOON *** WARNING ***
    Type: RSA 3072
    Expires: Feb 14, 2026 (15 days)
    Days Left: 15
    Sound: bundled:sshkey-host *** WARNING ***

[4] ~/.ssh/old_key.pem
    Status: DEPRECATED *** DEPRECATED ***
    Type: RSA 1024
    Algorithm: DEPRECATED
    Warning: Use ED25519 or RSA 2048+
    Sound: bundled:sshkey-deprecated *** FAILED ***

Recent Events:

[1] /etc/ssh/ssh_host_rsa_key: Expiring Soon (5 min ago)
       15 days remaining
       Sound: bundled:sshkey-expiring
  [2] ~/.ssh/old_key.pem: Deprecated Algorithm (1 hour ago)
       RSA 1024 is deprecated
       Sound: bundled:sshkey-deprecated
  [3] ~/.ssh/id_ed25519: New Key Added (2 days ago)
       ED25519 key added
       Sound: bundled:sshkey-added

SSH Key Statistics:
  Total Keys: 4
  Valid: 2
  Expiring: 1
  Deprecated: 1

Sound Settings:
  Expiring: bundled:sshkey-expiring
  Expired: bundled:sshkey-expired
  Deprecated: bundled:sshkey-deprecated
  Added: bundled:sshkey-added

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

SSH key monitoring doesn't play sounds directly:
- Monitoring feature using ssh-keygen
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### SSH Key Expiry Monitor

```go
type SSHKeyExpiryMonitor struct {
    config        *SSHKeyExpiryMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    keyState      map[string]*SSHKeyInfo
    lastEventTime map[string]time.Time
}

type SSHKeyInfo struct {
    Path        string
    Type        string
    Bits        int
    Algorithm   string // "deprecated", "valid"
    Expires     time.Time
    DaysLeft    int
    Status      string // "valid", "expiring", "expired", "deprecated"
    Comment     string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ssh-keygen | System Tool | Free | SSH key management |
| ssh-keyscan | System Tool | Free | Host key gathering |

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
| macOS | Supported | Uses ssh-keygen |
| Linux | Supported | Uses ssh-keygen |
