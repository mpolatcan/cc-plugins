# Feature: Sound Event System Backup Monitor

Play sounds for backup completion, failures, and progress milestones.

## Summary

Monitor system backups for completion status, error detection, and progress tracking, playing sounds for backup events.

## Motivation

- Backup completion alerts
- Failure detection
- Progress tracking
- Data protection
- Schedule verification

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
| Backup Complete | Finished successfully | done |
| Backup Failed | Error occurred | failed |
| Backup Started | Began execution | started |
| Progress Milestone | % reached | 50%, 75% |
| Incremental Done | Small backup | small change |
| Full Backup Done | Complete backup | full |

### Configuration

```go
type SystemBackupMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchBackups      []string          `json:"watch_backups"` // "home", "system", "*"
    BackupTools       []string          `json:"backup_tools"` // "borg", "rsync", "tar", "duplicati"
    Milestones        []int             `json:"milestones"` // [25, 50, 75, 100]
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnProgress   bool              `json:"sound_on_progress"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:backup status                  # Show backup status
/ccbell:backup add home                # Add backup to watch
/ccbell:backup remove home
/ccbell:backup milestones 50 75 100    # Set milestones
/ccbell:backup sound complete <sound>
/ccbell:backup sound fail <sound>
/ccbell:backup test                    # Test backup sounds
```

### Output

```
$ ccbell:backup status

=== Sound Event System Backup Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes
Progress Sounds: Yes

Watched Backups: 3
Watched Tools: 4

Backup Status:

[1] home (borg)
    Status: Completed
    Last Run: 2 hours ago
    Size: 250 GB
    Archives: 50
    Retention: 30 days
    Sound: bundled:backup-home

[2] system (tar)
    Status: Idle
    Last Run: 1 day ago
    Size: 45 GB
    Type: Full
    Sound: bundled:backup-system

[3] documents (rsync)
    Status: Running (45%)
    Progress: 45/100 GB
    ETA: 15 min
    Sound: bundled:backup-docs *** RUNNING ***

Recent Events:
  [1] documents: Progress 50% (10 min ago)
       Halfway done
  [2] home: Backup Complete (2 hours ago)
       Duration: 45 min
  [3] documents: Backup Started (30 min ago)
       Initializing

Backup Statistics:
  Completed Today: 1
  Failed Today: 0
  Total Backups: 150
  Success Rate: 99.3%

Sound Settings:
  Complete: bundled:backup-complete
  Fail: bundled:backup-fail
  Progress: bundled:backup-progress

[Configure] [Add Backup] [Test All]
```

---

## Audio Player Compatibility

Backup monitoring doesn't play sounds directly:
- Monitoring feature using borg/rsync/tar
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Backup Monitor

```go
type SystemBackupMonitor struct {
    config          *SystemBackupMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    backupState     map[string]*BackupInfo
    lastEventTime   map[string]time.Time
}

type BackupInfo struct {
    Name       string
    Tool       string // "borg", "rsync", "tar", "duplicati"
    Status     string // "idle", "running", "completed", "failed"
    Progress   int    // percentage
    Size       int64  // bytes
    Archives   int
    LastRun    time.Time
    LastStatus string
}

func (m *SystemBackupMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.backupState = make(map[string]*BackupInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemBackupMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBackups()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemBackupMonitor) checkBackups() {
    for _, backup := range m.config.WatchBackups {
        m.checkBackup(backup)
    }
}

func (m *SystemBackupMonitor) checkBackup(name string) {
    info := &BackupInfo{
        Name:    name,
        LastRun: time.Now(),
    }

    // Detect which backup tool is used
    tool := m.detectBackupTool(name)
    info.Tool = tool

    switch tool {
    case "borg":
        m.checkBorgBackup(name, info)
    case "rsync":
        m.checkRsyncBackup(name, info)
    case "tar":
        m.checkTarBackup(name, info)
    case "duplicati":
        m.checkDuplicatiBackup(name, info)
    }

    m.processBackupStatus(name, info)
}

func (m *SystemBackupMonitor) detectBackupTool(name string) string {
    // Check for borg repository
    if _, err := os.Stat(filepath.Join(name, "config")); err == nil {
        return "borg"
    }

    // Check for rsync backup log
    logPath := filepath.Join(name, ".backup.log")
    if _, err := os.Stat(logPath); err == nil {
        return "rsync"
    }

    // Default to rsync
    return "rsync"
}

func (m *SystemBackupMonitor) checkBorgBackup(name string, info *BackupInfo) {
    // Check if borg is running
    cmd := exec.Command("pgrep", "-x", "borg")
    _, err := cmd.Output()
    if err == nil {
        info.Status = "running"
        return
    }

    // Check last backup
    cmd = exec.Command("borg", "list", name, "--last", "1", "--json")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "idle"
        return
    }

    // Parse output for last archive
    if strings.Contains(string(output), "archive") {
        info.Status = "completed"
        info.Archives = m.countBorgArchives(name)
    }
}

func (m *SystemBackupMonitor) checkRsyncBackup(name string, info *BackupInfo) {
    // Check if rsync is running
    cmd := exec.Command("pgrep", "-x", "rsync")
    _, err := cmd.Output()
    if err == nil {
        info.Status = "running"
        return
    }

    // Check last backup time
    logPath := filepath.Join(name, ".backup.log")
    if data, err := os.ReadFile(logPath); err == nil {
        lines := strings.Split(string(data), "\n")
        for _, line := range lines {
            if strings.Contains(line, "Backup complete") {
                info.Status = "completed"
                break
            }
        }
    }
}

func (m *SystemBackupMonitor) checkTarBackup(name string, info *BackupInfo) {
    // Check if tar is running
    cmd := exec.Command("pgrep", "-x", "tar")
    _, err := cmd.Output()
    if err == nil {
        info.Status = "running"
        return
    }

    info.Status = "idle"
}

func (m *SystemBackupMonitor) checkDuplicatiBackup(name string, info *BackupInfo) {
    // Check duplicati service
    cmd := exec.Command("pgrep", "-x", "Duplicati")
    _, err := cmd.Output()
    if err == nil {
        info.Status = "running"
        return
    }

    info.Status = "idle"
}

func (m *SystemBackupMonitor) countBorgArchives(name string) int {
    cmd := exec.Command("borg", "list", name, "--count")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    count, _ := strconv.Atoi(strings.TrimSpace(string(output)))
    return count
}

func (m *SystemBackupMonitor) processBackupStatus(name string, info *BackupInfo) {
    lastInfo := m.backupState[name]

    if lastInfo == nil {
        m.backupState[name] = info
        return
    }

    // Check status changes
    if lastInfo.Status != info.Status {
        switch info.Status {
        case "completed":
            if lastInfo.Status == "running" {
                m.onBackupComplete(name, info)
            }
        case "failed":
            m.onBackupFailed(name, info)
        case "running":
            if lastInfo.Status == "idle" {
                m.onBackupStarted(name, info)
            }
        }
    }

    // Check progress milestones
    if info.Status == "running" && m.config.SoundOnProgress {
        for _, milestone := range m.config.Milestones {
            if info.Progress >= milestone && (lastInfo == nil || lastInfo.Progress < milestone) {
                m.onProgressMilestone(name, info, milestone)
            }
        }
    }

    m.backupState[name] = info
}

func (m *SystemBackupMonitor) onBackupStarted(name string, info *BackupInfo) {
    // Optional: sound when backup starts
}

func (m *SystemBackupMonitor) onBackupComplete(name string, info *BackupInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s", name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemBackupMonitor) onBackupFailed(name string, info *BackupInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemBackupMonitor) onProgressMilestone(name string, info *BackupInfo, milestone int) {
    key := fmt.Sprintf("progress:%s:%d", name, milestone)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["progress"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SystemBackupMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| borg | System Tool | Free | Backup tool |
| rsync | System Tool | Free | File sync |
| tar | System Tool | Free | Archive tool |
| duplicati | System Tool | Free | Backup tool |

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
| macOS | Supported | Uses rsync, tar, duplicati |
| Linux | Supported | Uses borg, rsync, tar, duplicati |
