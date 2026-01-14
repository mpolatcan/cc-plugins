# Feature: Sound Event Cloud Storage Monitor

Play sounds for cloud storage sync and file changes.

## Summary

Monitor cloud storage services (iCloud, Dropbox, Google Drive), playing sounds for sync events and file changes.

## Motivation

- Sync completion alerts
- Upload/download feedback
- Conflict detection
- Storage full warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Cloud Storage Events

| Event | Description | Example |
|-------|-------------|---------|
| Sync Started | Sync initiated | File changed |
| Sync Complete | Sync finished | All synced |
| Upload Complete | Upload finished | File uploaded |
| Download Complete | Download finished | File downloaded |
| Conflict Detected | File conflict | Sync conflict |
| Storage Full | Quota exceeded | 100% used |

### Configuration

```go
type CloudStorageMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchServices     []string          `json:"watch_services"` // "icloud", "dropbox", "gdrive"
    SoundOnSync       bool              `json:"sound_on_sync"`
    SoundOnUpload     bool              `json:"sound_on_upload"`
    SoundOnDownload   bool              `json:"sound_on_download"`
    SoundOnConflict   bool              `json:"sound_on_conflict"`
    SoundOnFull       bool              `json:"sound_on_full"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type CloudStorageEvent struct {
    ServiceName string
    EventType   string // "sync_start", "sync_complete", "upload", "download", "conflict", "full"
    FileName    string
    FileSize    int64
}
```

### Commands

```bash
/ccbell:cloud status                 # Show cloud sync status
/ccbell:cloud add icloud             # Add service to watch
/ccbell:cloud remove icloud
/ccbell:cloud sound sync <sound>
/ccbell:cloud sound upload <sound>
/ccbell:cloud test                   # Test cloud sounds
```

### Output

```
$ ccbell:cloud status

=== Sound Event Cloud Storage Monitor ===

Status: Enabled
Sync Sounds: Yes
Upload Sounds: Yes

Watched Services: 2

[1] iCloud Drive
    Status: Synced
    Files: 1,234
    Storage: 45 GB / 50 GB (90%)
    Last Sync: 5 min ago
    Sound: bundled:stop

[2] Dropbox
    Status: Synced
    Files: 567
    Storage: 2.1 GB / 2.0 GB (98%) - Nearly Full
    Last Sync: 10 min ago
    Sound: bundled:stop

Recent Events:
  [1] iCloud: Sync Complete (5 min ago)
       5 files synced
  [2] Dropbox: Upload Complete (15 min ago)
       document.pdf (2.5 MB)
  [3] Dropbox: Storage Full (1 hour ago)
       98% used

Sound Settings:
  Sync Complete: bundled:stop
  Upload: bundled:stop
  Download: bundled:stop
  Conflict: bundled:stop
  Storage Full: bundled:stop

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Cloud storage monitoring doesn't play sounds directly:
- Monitoring feature using file system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cloud Storage Monitor

```go
type CloudStorageMonitor struct {
    config         *CloudStorageMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    syncState      map[string]*SyncStatus
}

type SyncStatus struct {
    ServiceName    string
    Syncing        bool
    LastSync       time.Time
    PendingFiles   int
    StorageUsed    int64
    StorageTotal   int64
}
```

```go
func (m *CloudStorageMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.syncState = make(map[string]*SyncStatus)
    go m.monitor()
}

func (m *CloudStorageMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSync()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CloudStorageMonitor) checkSync() {
    for _, service := range m.config.WatchServices {
        m.checkService(service)
    }
}

func (m *CloudStorageMonitor) checkService(service string) {
    switch service {
    case "icloud":
        m.checkiCloud()
    case "dropbox":
        m.checkDropbox()
    case "gdrive":
        m.checkGoogleDrive()
    }
}

func (m *CloudStorageMonitor) checkiCloud() {
    // Check iCloud Drive folder
    icloudPath := filepath.Join(os.Getenv("HOME"), "Library/Mobile Documents")

    // Check for in-progress sync markers
    m.checkSyncStatus("icloud", icloudPath)
}

func (m *CloudStorageMonitor) checkDropbox() {
    // Check Dropbox status file
    dropboxPath := filepath.Join(os.Getenv("HOME"), "Dropbox")

    // Check for status file
    statusFile := filepath.Join(dropboxPath, ".dropbox.cache/status")

    if data, err := os.ReadFile(statusFile); err == nil {
        status := string(data)
        m.evaluateSyncStatus("dropbox", status)
    }

    // Check for .dropbox file (sync in progress)
    if _, err := os.Stat(filepath.Join(dropboxPath, ".dropbox")); err == nil {
        m.onSyncStarted("dropbox")
    }

    m.checkSyncStatus("dropbox", dropboxPath)
}

func (m *CloudStorageMonitor) checkGoogleDrive() {
    // Check Google Drive folder
    gdrivePath := filepath.Join(os.Getenv("HOME"), "Google Drive")

    m.checkSyncStatus("gdrive", gdrivePath)
}

func (m *CloudStorageMonitor) checkSyncStatus(service, path string) {
    status := m.syncState[service]
    if status == nil {
        status = &SyncStatus{ServiceName: service}
        m.syncState[service] = status
    }

    // Check for in-progress markers
    inProgress := m.detectInProgressSync(path)

    if inProgress && !status.Syncing {
        // Sync started
        status.Syncing = true
        m.onSyncStarted(service)
    } else if !inProgress && status.Syncing {
        // Sync completed
        status.Syncing = false
        status.LastSync = time.Now()
        m.onSyncComplete(service)
    }

    // Check storage usage
    used, total := m.getStorageUsage(path)
    status.StorageUsed = used
    status.StorageTotal = total

    if total > 0 && float64(used)/float64(total) > 0.95 {
        m.onStorageFull(service)
    }
}

func (m *CloudStorageMonitor) detectInProgressSync(path string) bool {
    // Look for sync markers
    markers := []string{
        ".sync_in_progress",
        ".dropbox",
        ".tmp",
        ".syncing",
    }

    for _, marker := range markers {
        markerPath := filepath.Join(path, marker)
        if _, err := os.Stat(markerPath); err == nil {
            return true
        }
    }

    return false
}

func (m *CloudStorageMonitor) getStorageUsage(path string) (used, total int64) {
    var statfs syscall.Statfs_t
    if err := syscall.Statfs(path, &statfs); err != nil {
        return 0, 0
    }

    total = int64(statfs.Bsize) * int64(statfs.Blocks)
    free := int64(statfs.Bfree) * int64(statfs.Bsize)
    used = total - free

    return used, total
}

func (m *CloudStorageMonitor) onSyncStarted(service string) {
    if !m.config.SoundOnSync {
        return
    }

    sound := m.config.Sounds["sync_start"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *CloudStorageMonitor) onSyncComplete(service string) {
    if !m.config.SoundOnSync {
        return
    }

    sound := m.config.Sounds["sync_complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CloudStorageMonitor) onUploadComplete(service, filename string) {
    if !m.config.SoundOnUpload {
        return
    }

    sound := m.config.Sounds["upload"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CloudStorageMonitor) onDownloadComplete(service, filename string) {
    if !m.config.SoundOnDownload {
        return
    }

    sound := m.config.Sounds["download"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CloudStorageMonitor) onConflictDetected(service, filename string) {
    if !m.config.SoundOnConflict {
        return
    }

    sound := m.config.Sounds["conflict"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *CloudStorageMonitor) onStorageFull(service string) {
    if !m.config.SoundOnFull {
        return
    }

    sound := m.config.Sounds["full"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ~/Library/Mobile Documents | File | Free | iCloud storage |
| ~/Dropbox | File | Free | Dropbox storage |
| ~/Google Drive | File | Free | Google Drive storage |
| syscall | Go Stdlib | Free | System calls |

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
| macOS | Supported | Uses native folders |
| Linux | Supported | Uses native folders |
| Windows | Not Supported | ccbell only supports macOS/Linux |
