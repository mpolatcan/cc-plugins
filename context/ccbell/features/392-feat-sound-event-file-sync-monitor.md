# Feature: Sound Event File Sync Monitor

Play sounds for file synchronization completion, conflicts, and errors.

## Summary

Monitor file synchronization services for sync completion, conflict detection, and transfer status, playing sounds for sync events.

## Motivation

- Sync completion alerts
- Conflict detection
- Transfer progress
- Error notifications
- Backup verification

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### File Sync Events

| Event | Description | Example |
|-------|-------------|---------|
| Sync Complete | All files synced | done |
| Sync Started | Sync began | syncing |
| File Conflict | Conflict detected | conflict |
| Sync Error | Transfer failed | error |
| New File | New file synced | added |
| Large File | Big file synced | > 1GB |

### Configuration

```go
type FileSyncMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchServices     []string          `json:"watch_services"` // "dropbox", "nextcloud", "rsync", "*"
    WatchPaths        []string          `json:"watch_paths"` // "/home/user/Dropbox", "*"
    LargeFileMB       int               `json:"large_file_mb"` // 1024 default
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnConflict   bool              `json:"sound_on_conflict"`
    SoundOnError      bool              `json:"sound_on_error"`
    SoundOnNewFile    bool              `json:"sound_on_new_file"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:sync status                    # Show sync status
/ccbell:sync add ~/Dropbox             # Add sync path
/ccbell:sync remove ~/Dropbox
/ccbell:sync sound complete <sound>
/ccbell:sync sound conflict <sound>
/ccbell:sync test                      # Test sync sounds
```

### Output

```
$ ccbell:sync status

=== Sound Event File Sync Monitor ===

Status: Enabled
Complete Sounds: Yes
Conflict Sounds: Yes
Error Sounds: Yes

Watched Services: 3
Watched Paths: 2

Sync Status:

[1] ~/Dropbox (Dropbox)
    Status: Synced
    Files: 12,450
    Size: 45 GB
    Last Sync: 5 min ago
    Sound: bundled:sync-dropbox

[2] ~/Nextcloud (Nextcloud)
    Status: Syncing
    Files Synced: 15/50
    Size: 2.5 GB
    ETA: 10 min
    Sound: bundled:sync-nextcloud

[3] ~/Backups (rsync)
    Status: Idle
    Last Backup: 1 day ago
    Size: 250 GB
    Sound: bundled:sync-backup

Recent Events:
  [1] ~/Nextcloud: Sync Started (10 min ago)
       15/50 files synced
  [2] ~/Dropbox: New File (1 hour ago)
       document.pdf (2.5 MB)
  [3] ~/Backups: Sync Complete (1 day ago)
       Full backup completed

Conflict Files:
  [1] presentation.pptx
       Modified by you and another device
       Path: ~/Dropbox/conflicts/

Sync Statistics:
  Syncs Today: 8
  Completed: 7
  Conflicts: 1
  Errors: 0

Sound Settings:
  Complete: bundled:sync-complete
  Conflict: bundled:sync-conflict
  Error: bundled:sync-error
  New File: bundled:sync-new

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Sync monitoring doesn't play sounds directly:
- Monitoring feature using syncthing-cli/rsync/dropbox-cli
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Sync Monitor

```go
type FileSyncMonitor struct {
    config          *FileSyncMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    syncState       map[string]*SyncServiceInfo
    lastEventTime   map[string]time.Time
    lastCheckTime   time.Time
}

type SyncServiceInfo struct {
    Name       string
    Path       string
    Service    string // "dropbox", "nextcloud", "rsync"
    Status     string // "synced", "syncing", "idle", "error"
    FileCount  int64
    TotalSize  int64
    SyncedSize int64
    Conflicts  int
    LastSync   time.Time
}

func (m *FileSyncMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.syncState = make(map[string]*SyncServiceInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastCheckTime = time.Now()
    go m.monitor()
}

func (m *FileSyncMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSyncStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileSyncMonitor) checkSyncStatus() {
    for _, service := range m.config.WatchServices {
        switch service {
        case "dropbox":
            m.checkDropboxStatus()
        case "nextcloud":
            m.checkNextcloudStatus()
        case "rsync":
            m.checkRsyncStatus()
        case "syncthing":
            m.checkSyncthingStatus()
        }
    }

    m.lastCheckTime = time.Now()
}

func (m *FileSyncMonitor) checkDropboxStatus() {
    cmd := exec.Command("dropbox", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    status := strings.TrimSpace(string(output))
    path := m.getDropboxPath()

    id := "dropbox"

    info := &SyncServiceInfo{
        Name:     "Dropbox",
        Path:     path,
        Service:  "dropbox",
        LastSync: time.Now(),
    }

    if strings.Contains(status, "Up to date") || strings.Contains(status, "Synced") {
        info.Status = "synced"
    } else if strings.Contains(status, "Syncing") {
        info.Status = "syncing"
        // Parse progress
        re := regexp.MustEach(`(\d+)`)
    } else if strings.Contains(status, "Connecting") || strings.Contains(status, "Starting") {
        info.Status = "syncing"
    }

    m.processSyncStatus(id, info)
}

func (m *FileSyncMonitor) checkNextcloudStatus() {
    // Check nextcloudcmd or ncdu output
    cmd := exec.Command("nextcloudcmd", "--version")
    if err := cmd.Run(); err != nil {
        return
    }

    // Use ncdu or check sync log
    info := &SyncServiceInfo{
        Name:     "Nextcloud",
        Service:  "nextcloud",
        Status:   "idle",
        LastSync: time.Now(),
    }

    m.processSyncStatus("nextcloud", info)
}

func (m *FileSyncMonitor) checkRsyncStatus() {
    // Check if rsync is running
    cmd := exec.Command("pgrep", "-x", "rsync")
    _, err := cmd.Output()

    info := &SyncServiceInfo{
        Name:     "rsync",
        Service:  "rsync",
        Status:   "idle",
        LastSync: time.Now(),
    }

    if err == nil {
        info.Status = "syncing"
    }

    m.processSyncStatus("rsync", info)
}

func (m *FileSyncMonitor) checkSyncthingStatus() {
    // Use syncthing-cli if available
    cmd := exec.Command("syncthing", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    status := strings.TrimSpace(string(output))

    info := &SyncServiceInfo{
        Name:     "Syncthing",
        Service:  "syncthing",
        Status:   "idle",
        LastSync: time.Now(),
    }

    if strings.Contains(status, "Idle") || strings.Contains(status, "Up to Date") {
        info.Status = "synced"
    } else if strings.Contains(status, "Syncing") {
        info.Status = "syncing"
    }

    m.processSyncStatus("syncthing", info)
}

func (m *FileSyncMonitor) processSyncStatus(id string, info *SyncServiceInfo) {
    lastInfo := m.syncState[id]

    if lastInfo == nil {
        m.syncState[id] = info
        return
    }

    // Check status changes
    if lastInfo.Status != info.Status {
        if info.Status == "synced" {
            m.onSyncComplete(info)
        } else if info.Status == "syncing" && lastInfo.Status == "idle" {
            m.onSyncStarted(info)
        } else if info.Status == "error" {
            m.onSyncError(info)
        }
    }

    // Check for conflicts
    if info.Conflicts > 0 && lastInfo.Conflicts != info.Conflicts {
        m.onConflictDetected(info)
    }

    m.syncState[id] = info
}

func (m *FileSyncMonitor) onSyncComplete(info *SyncServiceInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s", info.Service)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileSyncMonitor) onSyncStarted(info *SyncServiceInfo) {
    // Optional: sound when sync starts
}

func (m *FileSyncMonitor) onSyncError(info *SyncServiceInfo) {
    if !m.config.SoundOnError {
        return
    }

    key := fmt.Sprintf("error:%s", info.Service)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileSyncMonitor) onConflictDetected(info *SyncServiceInfo) {
    if !m.config.SoundOnConflict {
        return
    }

    key := fmt.Sprintf("conflict:%s", info.Service)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["conflict"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *FileSyncMonitor) getDropboxPath() string {
    cmd := exec.Command("dropbox", "path")
    output, err := cmd.Output()
    if err != nil {
        return "~/Dropbox"
    }
    return strings.TrimSpace(string(output))
}

func (m *FileSyncMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| dropbox | System Tool | Free | Dropbox CLI |
| nextcloudcmd | System Tool | Free | Nextcloud CLI |
| syncthing | System Tool | Free | Syncthing |
| rsync | System Tool | Free | File sync |

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
| macOS | Supported | Uses dropbox, rsync, syncthing |
| Linux | Supported | Uses dropbox, nextcloudcmd, rsync |
