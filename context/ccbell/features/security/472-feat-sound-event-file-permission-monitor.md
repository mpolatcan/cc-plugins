# Feature: Sound Event File Permission Monitor

Play sounds for file permission changes and insecure permission detections.

## Summary

Monitor files and directories for permission changes, insecure configurations, and ownership modifications, playing sounds for permission events.

## Motivation

- Security monitoring
- Permission awareness
- Compliance checking
- Audit trail
- Intrusion detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### File Permission Events

| Event | Description | Example |
|-------|-------------|---------|
| Permission Changed | Mode changed | 755->777 |
| Owner Changed | Owner changed | root->user |
| Group Changed | Group changed | staff->wheel |
| World Writable | Insecure mode | 777 detected |
| SUID Bit Set | Elevated bit | suid detected |
| No Execute | No exec bit | noexec detected |

### Configuration

```go
type FilePermissionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // paths to monitor
    InsecurePatterns  []string          `json:"insecure_patterns"` // "777", "suid"
    SoundOnChange     bool              `json:"sound_on_change"`
    SoundOnInsecure   bool              `json:"sound_on_insecure"`
    SoundOnOwner      bool              `json:"sound_on_owner"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:perm status                 # Show permission status
/ccbell:perm add /etc               # Add path to watch
/ccbell:perm sound change <sound>
/ccbell:perm test                   # Test permission sounds
```

### Output

```
$ ccbell:perm status

=== Sound Event File Permission Monitor ===

Status: Enabled
Watch Paths: /etc, /var/www

Path Status:

[1] /etc/passwd
    Mode: 644
    Owner: root:wheel
    Status: SECURE
    Sound: bundled:perm-secure

[2] /etc/shadow
    Mode: 640
    Owner: root:shadow
    Status: SECURE
    Sound: bundled:perm-secure

[3] /var/www/html/config.php
    Mode: 777 *** INSECURE ***
    Owner: www-data:www-data
    Status: WORLD WRITABLE
    Sound: bundled:perm-insecure *** FAILED ***

[4] /usr/bin/sudo
    Mode: 4111 *** SUID ***
    Owner: root:root
    Status: SUID BIT SET
    Sound: bundled:perm-suid

Recent Events:

[1] /var/www/html/config.php: Insecure Permission (5 min ago)
       Mode 777 detected
       Sound: bundled:perm-insecure
  [2] /etc/nginx/nginx.conf: Permission Changed (1 hour ago)
       644 -> 640
       Sound: bundled:perm-change
  [3] /etc/sudoers: Owner Changed (2 hours ago)
       root:root -> admin:wheel
       Sound: bundled:perm-owner

Permission Statistics:
  Total Paths: 4
  Secure: 2
  Insecure: 1
  SUID: 1

Sound Settings:
  Change: bundled:perm-change
  Insecure: bundled:perm-insecure
  Owner: bundled:perm-owner
  SUID: bundled:perm-suid

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Permission monitoring doesn't play sounds directly:
- Monitoring feature using stat, ls
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### File Permission Monitor

```go
type FilePermissionMonitor struct {
    config        *FilePermissionMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    permState     map[string]*PermInfo
    lastEventTime map[string]time.Time
}

type PermInfo struct {
    Path      string
    Mode      string
    Owner     string
    Group     string
    Status    string // "secure", "insecure", "suid", "changed"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| stat | System Tool | Free | File status |
| ls | System Tool | Free | Directory listing |

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
| macOS | Supported | Uses stat, ls |
| Linux | Supported | Uses stat, ls |
