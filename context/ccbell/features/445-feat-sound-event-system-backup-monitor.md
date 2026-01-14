# Feature: Sound Event System Backup Monitor

Play sounds for backup completion, failures, and verification results.

## Summary

Monitor backup operations (rsync, tar, Borg, Time Machine) for completion, errors, and restoration events, playing sounds for backup events.

## Motivation

- Backup completion awareness
- Failure alerts
- Verification feedback
- Restore confirmation
- Data protection

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
| Backup Complete | Successful backup | done |
| Backup Started | Backup began | syncing |
| Backup Failed | Error during backup | error |
| Backup Verification | Check passed | verified |
| Backup Warning | Non-fatal issue | warning |
| Restore Complete | Restoration done | restored |

### Configuration

```go
type BackupMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchBackups      []string          `json:"watch_backups"` // backup names or paths
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnStarted    bool              `json:"sound_on_started"`
    SoundOnVerified   bool              `json:"sound_on_verified"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:backup status               # Show backup status
/ccbell:backup add "~/backup.sh"    # Add backup script to monitor
/ccbell:backup sound complete <sound>
/ccbell:backup test                 # Test backup sounds
```

### Output

```
$ ccbell:backup status

=== Sound Event System Backup Monitor ===

Status: Enabled
Watch Backups: 3

Backup Status:

[1] System Backup (~/backup.sh)
    Status: COMPLETED
    Last Run: Jan 14 02:00
    Duration: 2h 15m
    Size: 450 GB
    Sound: bundled:backup-complete

[2] Documents (rsync ~/Documents /mnt/backup)
    Status: COMPLETED
    Last Run: Jan 14 03:00
    Duration: 15m
    Size: 50 GB
    Sound: bundled:backup-rsync

[3] Photos (borg ~/Photos /mnt/backup)
    Status: RUNNING *** RUNNING ***
    Progress: 75%
    Started: Jan 14 04:00
    Sound: bundled:backup-started

Recent Events:

[1] System Backup: Complete (8 hours ago)
       450 GB backed up successfully
       Sound: bundled:backup-complete
  [2] Photos: Started (1 hour ago)
       Borg backup in progress
       Sound: bundled:backup-started
  [3] Documents: Verification Passed (10 hours ago)
       Integrity check passed
       Sound: bundled:backup-verified

Backup Statistics:
  Total Backups: 3
  Completed Today: 2
  Failed Today: 0
  Total Size: 500 GB

Sound Settings:
  Complete: bundled:backup-complete
  Failed: bundled:backup-failed
  Started: bundled:backup-started
  Verified: bundled:backup-verified

[Configure] [Add Backup] [Test All]
```

---

## Audio Player Compatibility

Backup monitoring doesn't play sounds directly:
- Monitoring feature using pgrep, ps, script output
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### System Backup Monitor

```go
type BackupMonitor struct {
    config        *BackupMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    backupState   map[string]*BackupInfo
    lastEventTime map[string]time.Time
}

type BackupInfo struct {
    Name        string
    Type        string // "rsync", "tar", "borg", "tmux", "script"
    Status      string // "idle", "running", "completed", "failed", "verified"
    LastRun     time.Time
    LastSuccess time.Time
    Size        int64
    Duration    time.Duration
    Progress    int
}

func (m *BackupMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.backupState = make(map[string]*BackupInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *BackupMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotBackupState()

    for {
        select {
        case <-ticker.C:
            m.checkBackupState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BackupMonitor) snapshotBackupState() {
    m.checkBackupState()
}

func (m *BackupMonitor) checkBackupState() {
    for _, backup := range m.config.WatchBackups {
        info := m.checkBackup(backup)
        if info != nil {
            m.processBackupStatus(info)
        }
    }
}

func (m *BackupMonitor) checkBackup(backup string) *BackupInfo {
    info := &BackupInfo{
        Name: backup,
    }

    // Detect backup type and check status
    if strings.HasPrefix(backup, "rsync") {
        info.Type = "rsync"
        m.checkRsyncBackup(info, backup)
    } else if strings.HasPrefix(backup, "borg") {
        info.Type = "borg"
        m.checkBorgBackup(info, backup)
    } else if strings.Contains(backup, "Time Machine") || strings.Contains(backup, "tmutil") {
        info.Type = "time-machine"
        m.checkTimeMachineBackup(info)
    } else {
        info.Type = "script"
        m.checkScriptBackup(info, backup)
    }

    return info
}

func (m *BackupMonitor) checkRsyncBackup(info *BackupInfo, backup string) {
    // Check if rsync is running
    cmd := exec.Command("pgrep", "-x", "rsync")
    err := cmd.Run()

    if err == nil {
        info.Status = "running"
        info.Progress = m.getRsyncProgress()
        return
    }

    // Check last run from log
    info.Status = "idle"

    cmd = exec.Command("stat", "-c", "%Y", strings.Fields(backup)[1])
    output, _ := cmd.Output()

    if len(output) > 0 {
        lastRun := time.Unix(0, 0)
        info.LastRun = lastRun
    }
}

func (m *BackupMonitor) getRsyncProgress() int {
    // Try to get rsync progress via ps
    cmd := exec.Command("ps", "aux")
    output, _ := cmd.Output()

    re := regexp.MustEach(`rsync.*--progress.*(\d+)%`)
    matches := re.FindStringSubmatch(string(output))
    if len(matches) >= 2 {
        pct, _ := strconv.Atoi(matches[1])
        return pct
    }
    return 0
}

func (m *BackupMonitor) checkBorgBackup(info *BackupInfo, backup string) {
    // Check if borg is running
    cmd := exec.Command("pgrep", "-x", "borg")
    err := cmd.Run()

    if err == nil {
        info.Status = "running"
        info.Progress = 75 // approximate
        return
    }

    info.Status = "idle"

    // Check last backup info
    cmd = exec.Command("borg", "list", "--last", "1", strings.Fields(backup)[1])
    output, _ := cmd.Output()

    if len(output) > 0 {
        info.LastRun = time.Now()
        info.Status = "completed"
    }
}

func (m *BackupMonitor) checkTimeMachineBackup(info *BackupInfo) {
    // Check Time Machine status
    cmd := exec.Command("tmutil", "status")
    output, err := cmd.Output()

    if err != nil {
        info.Status = "idle"
        return
    }

    outputStr := string(output)

    if strings.Contains(outputStr, "Running") {
        info.Status = "running"
        info.Progress = 50 // approximate
    } else if strings.Contains(outputStr, "Backup completed") {
        info.Status = "completed"
        info.LastSuccess = time.Now()
    } else {
        info.Status = "idle"
    }
}

func (m *BackupMonitor) checkScriptBackup(info *BackupInfo, backup string) {
    // Parse script path
    parts := strings.Fields(backup)
    if len(parts) < 2 {
        return
    }

    scriptPath := parts[1]

    // Check if script is running
    cmd := exec.Command("pgrep", "-f", scriptPath)
    err := cmd.Run()

    if err == nil {
        info.Status = "running"
        info.Progress = 50
        return
    }

    info.Status = "idle"

    // Check last run time
    fileInfo, err := os.Stat(scriptPath)
    if err == nil {
        info.LastRun = fileInfo.ModTime()
    }
}

func (m *BackupMonitor) processBackupStatus(info *BackupInfo) {
    lastInfo := m.backupState[info.Name]

    if lastInfo == nil {
        m.backupState[info.Name] = info

        if info.Status == "running" && m.config.SoundOnStarted {
            m.onBackupStarted(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "completed":
            if lastInfo.Status == "running" {
                m.onBackupComplete(info)
            }
        case "failed":
            if m.config.SoundOnFailed {
                m.onBackupFailed(info)
            }
        case "running":
            if lastInfo.Status == "idle" || lastInfo.Status == "completed" {
                if m.config.SoundOnStarted {
                    m.onBackupStarted(info)
                }
            }
        }
    }

    m.backupState[info.Name] = info
}

func (m *BackupMonitor) onBackupComplete(info *BackupInfo) {
    key := fmt.Sprintf("complete:%s", info.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        if m.config.SoundOnComplete {
            sound := m.config.Sounds["complete"]
            if sound != "" {
                m.player.Play(sound, 0.4)
            }
        }
    }
}

func (m *BackupMonitor) onBackupStarted(info *BackupInfo) {
    key := fmt.Sprintf("started:%s", info.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        if m.config.SoundOnStarted {
            sound := m.config.Sounds["started"]
            if sound != "" {
                m.player.Play(sound, 0.3)
            }
        }
    }
}

func (m *BackupMonitor) onBackupFailed(info *BackupInfo) {
    key := fmt.Sprintf("failed:%s", info.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        if m.config.SoundOnFailed {
            sound := m.config.Sounds["failed"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    }
}

func (m *BackupMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| rsync | System Tool | Free | File sync tool |
| borgbackup | System Tool | Free | Deduplicating backup |
| tmutil | System Tool | Free | Time Machine utility |
| pgrep | System Tool | Free | Process listing |

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
| macOS | Supported | Uses rsync, tmutil |
| Linux | Supported | Uses rsync, borgbackup |
