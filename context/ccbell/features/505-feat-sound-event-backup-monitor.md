# Feature: Sound Event Backup Monitor

Play sounds for backup completion, failure, and verification events.

## Summary

Monitor backup operations for completion status, failure detection, and verification results, playing sounds for backup events.

## Motivation

- Backup awareness
- Failure detection
- Verification tracking
- Data protection
- Schedule monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Backup Events

| Event | Description | Example |
|-------|-------------|---------|
| Backup Completed | Backup finished | success |
| Backup Failed | Backup error | failed |
| Backup Started | Backup initiated | started |
| Verification Passed | Checksum OK | verified |
| Verification Failed | Checksum bad | mismatch |
| Space Warning | Low backup space | 80% full |

### Configuration

```go
type BackupMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchBackups       []BackupSpec      `json:"watch_backups"`
    SoundOnComplete    bool              `json:"sound_on_complete"`
    SoundOnFail        bool              `json:"sound_on_fail"`
    SoundOnVerifyFail  bool              `json:"sound_on_verify_fail"`
    SpaceWarningPercent int              `json:"space_warning_percent"` // 80
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 300 default
}

type BackupSpec struct {
    Name      string // "daily-backup"
    Type      string // "rsync", "borg", "tar", "duplicati"
    Path      string // backup destination or log
    Schedule  string // cron expression
}
```

### Commands

```bash
/ccbell:backup status               # Show backup status
/ccbell:backup add /backup/daily    # Add backup to watch
/ccbell:backup sound complete <sound>
/ccbell:backup test                 # Test backup sounds
```

### Output

```
$ ccbell:backup status

=== Sound Event Backup Monitor ===

Status: Enabled
Watch Backups: all

Backup Status:

[1] daily-backup (rsync)
    Status: COMPLETED *** ACTIVE ***
    Last Run: 2 hours ago
    Duration: 15 min
    Size: 500 GB
    Files: 1,234,567
    Sound: bundled:backup-daily *** ACTIVE ***

[2] weekly-backup (borg)
    Status: SCHEDULED
    Next Run: Tomorrow 2:00 AM
    Last Run: 1 week ago
    Duration: 2 hours
    Size: 2 TB
    Sound: bundled:backup-weekly

[3] database-backup (pg_dump)
    Status: FAILED *** FAILED ***
    Last Run: 5 min ago
    Error: connection refused
    Duration: 0 sec
    Sound: bundled:backup-db *** FAILED ***

[4] system-image (tar)
    Status: VERIFICATION PASSED
    Last Run: 1 day ago
    Duration: 45 min
    Size: 100 GB
    Checksum: Valid
    Sound: bundled:backup-image

Backup Destinations:

[1] /backup/external
    Total: 4 TB
    Used: 3.2 TB (80%)
    Status: HEALTHY
    Sound: bundled:backup-dest-external

[2] /backup/cloud
    Total: 1 TB
    Used: 950 GB (95%) *** NEAR FULL ***
    Status: WARNING
    Sound: bundled:backup-dest-cloud *** WARNING ***

Recent Events:

[1] database-backup: Backup Failed (5 min ago)
       connection refused to localhost:5432
       Sound: bundled:backup-fail
  [2] daily-backup: Backup Completed (2 hours ago)
       500 GB synced successfully
       Sound: bundled:backup-complete
  [3] system-image: Verification Passed (1 day ago)
       Checksum verification successful
       Sound: bundled:backup-verify
  [4] backup-cloud: Space Warning (1 week ago)
       90% full (950 GB / 1 TB)
       Sound: bundled:backup-space-warning

Backup Statistics:
  Total Backups: 4
  Completed: 2
  Failed: 1
  Scheduled: 1
  Total Size: 2.6 TB

Sound Settings:
  Complete: bundled:backup-complete
  Fail: bundled:backup-fail
  Verify Pass: bundled:backup-verify
  Verify Fail: bundled:backup-verify-fail

[Configure] [Add Backup] [Test All]
```

---

## Audio Player Compatibility

Backup monitoring doesn't play sounds directly:
- Monitoring feature using rsync, borg, log files
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Backup Monitor

```go
type BackupMonitor struct {
    config        *BackupMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    backupState   map[string]*BackupInfo
    lastEventTime time.Time
}

type BackupInfo struct {
    Name        string
    Type        string
    Status      string // "completed", "failed", "running", "scheduled"
    LastRun     time.Time
    Duration    time.Duration
    SizeBytes   int64
    FileCount   int64
    ErrorMsg    string
    Checksum    string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| rsync | System Tool | Free | File synchronization |
| borg | System Tool | Free | Deduplicating backup |
| du | System Tool | Free | Disk usage |
| sha256sum | System Tool | Free | Checksum verification |

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
| macOS | Supported | Uses rsync, du, sha256sum |
| Linux | Supported | Uses rsync, borg, du, sha256sum |
