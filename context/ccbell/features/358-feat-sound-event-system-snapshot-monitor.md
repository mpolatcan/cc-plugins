# Feature: Sound Event System Snapshot Monitor

Play sounds for system snapshot/backup events and restore operations.

## Summary

Monitor system snapshot creation, backup completion, and restore operations, playing sounds for snapshot events.

## Motivation

- Backup awareness
- Snapshot completion feedback
- Restore operation alerts
- Data protection awareness
- Backup job confirmation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Snapshot Events

| Event | Description | Example |
|-------|-------------|---------|
| Snapshot Created | New snapshot created | LVM snap created |
| Snapshot Deleted | Snapshot removed | LVM snap removed |
| Backup Completed | Backup job finished | rsync backup done |
| Backup Failed | Backup job failed | rsync error |
| Restore Started | Restore operation began | Files restored |
| Restore Completed | Restore finished | Data restored |

### Configuration

```go
type SystemSnapshotMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchSnapshots     []string          `json:"watch_snapshots"` // "lvm", "btrfs", "zfs", "*"
    WatchBackups       []string          `json:"watch_backups"` // "backup", "home", "*"
    SoundOnCreate      bool              `json:"sound_on_create"`
    SoundOnDelete      bool              `json:"sound_on_delete"`
    SoundOnComplete    bool              `json:"sound_on_complete"`
    SoundOnFail        bool              `json:"sound_on_fail"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 60 default
}

type SystemSnapshotEvent struct {
    Type       string // "lvm", "btrfs", "zfs", "rsync"
    Name       string
    Source     string
    Target     string
    Size       int64 // bytes
    Status     string // "success", "failed", "in_progress"
    EventType  string // "create", "delete", "complete", "fail", "restore"
}
```

### Commands

```bash
/ccbell:snapshot status               # Show snapshot status
/ccbell:snapshot add lvm              # Add snapshot type to watch
/ccbell:snapshot remove lvm
/ccbell:snapshot sound create <sound>
/ccbell:snapshot sound complete <sound>
/ccbell:snapshot test                 # Test snapshot sounds
```

### Output

```
$ ccbell:snapshot status

=== Sound Event System Snapshot Monitor ===

Status: Enabled
Create Sounds: Yes
Complete Sounds: Yes
Fail Sounds: Yes

Watched Snapshot Types: 2
Watched Backups: 2

LVM Snapshots:
  [1] vg00/snap-home
      Size: 5 GB
      Status: ACTIVE
      Created: 2 hours ago
      Sound: bundled:snap-lvm

  [2] vg00/snap-var
      Size: 2 GB
      Status: REMOVED
      Sound: bundled:snap-lvm

Backup Jobs:
  [1] /backup/daily (rsync)
      Status: COMPLETED
      Last Run: 1 hour ago
      Size: 45 GB
      Sound: bundled:backup-daily

  [2] /backup/weekly (borg)
      Status: FAILED
      Last Run: 6 hours ago
      Error: Connection timeout
      Sound: bundled:backup-weekly

Recent Events:
  [1] LVM: Snapshot Created (5 min ago)
       vg00/snap-home (5 GB)
  [2] rsync: Backup Completed (1 hour ago)
       /backup/daily completed (45 GB)
  [3] borg: Backup Failed (2 hours ago)
       Connection timeout

Snapshot Statistics:
  Snapshots Today: 3
  Backups Today: 5
  Failed: 1

Sound Settings:
  Create: bundled:snap-create
  Delete: bundled:snap-delete
  Complete: bundled:snap-complete
  Fail: bundled:snap-fail

[Configure] [Add Type] [Test All]
```

---

## Audio Player Compatibility

Snapshot monitoring doesn't play sounds directly:
- Monitoring feature using lvs/btrfs/zfs commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Snapshot Monitor

```go
type SystemSnapshotMonitor struct {
    config          *SystemSnapshotMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    snapshotState   map[string]*SnapshotInfo
    backupState     map[string]*BackupInfo
    lastEventTime   map[string]time.Time
}

type SnapshotInfo struct {
    Name     string
    VG       string
    LV       string
    Size     int64
    Status   string // "active", "removed"
    Created  time.Time
}

type BackupInfo struct {
    Name     string
    Type     string // "rsync", "borg", "duply"
    Source   string
    Target   string
    Size     int64
    Status   string // "success", "failed", "running"
    LastRun  time.Time
}

func (m *SystemSnapshotMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.snapshotState = make(map[string]*SnapshotInfo)
    m.backupState = make(map[string]*BackupInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemSnapshotMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotStateState()

    for {
        select {
        case <-ticker.C:
            m.checkState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemSnapshotMonitor) snapshotStateState() {
    // Check LVM snapshots
    m.checkLVMSnapshots()

    // Check btrfs snapshots
    m.checkBTRFSSnapshots()

    // Check backup status
    m.checkBackupStatus()
}

func (m *SystemSnapshotMonitor) checkState() {
    m.snapshotStateState()
}

func (m *SystemSnapshotMonitor) checkLVMSnapshots() {
    cmd := exec.Command("lvs", "--noheadings", "-o", "lv_name,vg_name,lv_size,lv_snapshot_percent")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentSnapshots := make(map[string]*SnapshotInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        name := parts[0]
        vg := parts[1]

        // Check if it's a snapshot
        if !strings.Contains(name, "snap") && !strings.Contains(line, "/") {
            continue
        }

        key := fmt.Sprintf("lvm:%s:%s", vg, name)
        sizeStr := strings.TrimSuffix(parts[2], "g")
        size, _ := strconv.ParseInt(sizeStr, 10, 64)
        size = size * 1024 * 1024 * 1024 // Convert to bytes

        currentSnapshots[key] = &SnapshotInfo{
            Name:    name,
            VG:      vg,
            Size:    size,
            Status:  "active",
            Created: time.Now(),
        }

        if last, exists := m.snapshotState[key]; !exists {
            m.snapshotState[key] = currentSnapshots[key]
            m.onSnapshotCreated("lvm", currentSnapshots[key])
        }
    }

    // Check for removed snapshots
    for key, last := range m.snapshotState {
        if strings.HasPrefix(key, "lvm:") {
            if _, exists := currentSnapshots[key]; !exists {
                m.snapshotState[key].Status = "removed"
                m.onSnapshotDeleted("lvm", last)
                delete(m.snapshotState, key)
            }
        }
    }
}

func (m *SystemSnapshotMonitor) checkBTRFSSnapshots() {
    cmd := exec.Command("btrfs", "subvolume", "list", "-s", "/")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        re := regexp.MustCompile(`ID (\d+) gen (\d+) top level (\d+) parent (\d+) <FS_TREE>/(.+)`)
        match := re.FindStringSubmatch(line)
        if match == nil {
            continue
        }

        name := match[5]
        key := fmt.Sprintf("btrfs:%s", name)

        if _, exists := m.snapshotState[key]; !exists {
            m.snapshotState[key] = &SnapshotInfo{
                Name:    name,
                Status:  "active",
                Created: time.Now(),
            }
            m.onSnapshotCreated("btrfs", m.snapshotState[key])
        }
    }
}

func (m *SystemSnapshotMonitor) checkBackupStatus() {
    // Check backup job logs or status files
    backupLogPath := "/var/log/backup.log"
    if data, err := os.ReadFile(backupLogPath); err == nil {
        m.parseBackupLog(string(data))
    }
}

func (m *SystemSnapshotMonitor) parseBackupLog(logData string) {
    lines := strings.Split(logData, "\n")
    for _, line := range lines {
        if strings.Contains(line, "Backup completed") {
            m.onBackupComplete("rsync", "daily")
        } else if strings.Contains(line, "Backup failed") {
            m.onBackupFailed("rsync", "daily")
        }
    }
}

func (m *SystemSnapshotMonitor) shouldWatchSnapshot(snapType string) bool {
    if len(m.config.WatchSnapshots) == 0 {
        return true
    }

    for _, s := range m.config.WatchSnapshots {
        if s == "*" || s == snapType {
            return true
        }
    }

    return false
}

func (m *SystemSnapshotMonitor) onSnapshotCreated(snapType string, snapshot *SnapshotInfo) {
    if !m.config.SoundOnCreate {
        return
    }

    if !m.shouldWatchSnapshot(snapType) {
        return
    }

    key := fmt.Sprintf("create:%s:%s", snapType, snapshot.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["create"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemSnapshotMonitor) onSnapshotDeleted(snapType string, snapshot *SnapshotInfo) {
    if !m.config.SoundOnDelete {
        return
    }

    key := fmt.Sprintf("delete:%s:%s", snapType, snapshot.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["delete"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SystemSnapshotMonitor) onBackupComplete(backupType, name string) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s:%s", backupType, name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemSnapshotMonitor) onBackupFailed(backupType, name string) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s:%s", backupType, name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemSnapshotMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| lvs | System Tool | Free | LVM snapshot listing |
| btrfs | System Tool | Free | BTRFS snapshots |
| rsync | System Tool | Free | Backup utility |

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
| macOS | Supported | Uses rsync, Time Machine |
| Linux | Supported | Uses lvs, btrfs, zfs |
