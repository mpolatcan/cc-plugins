# Feature: Sound Event File Sync Monitor

Play sounds for file sync completion, conflicts, and sync errors.

## Summary

Monitor file synchronization services (Dropbox, rsync, syncthing, etc.) for sync status and events, playing sounds for sync events.

## Motivation

- Sync completion awareness
- Conflict detection
- Sync error alerts
- Transfer feedback
- Data consistency

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
| Sync Started | Transfer began | syncing |
| Conflict Detected | File conflict | conflict |
| Sync Error | Transfer failed | error |
| New Files | New files detected | +5 files |
| Large Transfer | Big sync | > 1GB |

### Configuration

```go
type FileSyncMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchServices     []string          `json:"watch_services"` // "dropbox", "rsync", "syncthing", "*"
    SyncPaths         []string          `json:"sync_paths"` // paths to monitor
    LargeTransferMB   int               `json:"large_transfer_mb"` // 1024 default
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnConflict   bool              `json:"sound_on_conflict"`
    SoundOnError      bool              `json:"sound_on_error"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:sync status                 # Show sync status
/ccbell:sync add dropbox            # Add service to watch
/ccbell:sync sound complete <sound>
/ccbell:sync sound conflict <sound>
/ccbell:sync test                   # Test sync sounds
```

### Output

```
$ ccbell:sync status

=== Sound Event File Sync Monitor ===

Status: Enabled
Large Transfer: 1024 MB

Sync Service Status:

[1] Dropbox (~/Dropbox)
    Status: UP TO DATE
    Synced: 5,234 files
    Last Sync: 2 min ago
    Changes Pending: 0
    Speed: 0 KB/s
    Sound: bundled:sync-dropbox

[2] Syncthing (~/Sync)
    Status: SYNCHRONIZING
    Synced: 1,892 files
    In Sync: 45 files
    Download: 2.5 MB/s
    Upload: 500 KB/s
    Sound: bundled:sync-syncthing *** SYNCING ***

[3] rsync (~/backup)
    Status: IDLE
    Last Run: Jan 14, 2026 02:00
    Status: Completed successfully
    Files: 12,450
    Sound: bundled:sync-rsync

Sync Activity:

  [1] Syncthing: Sync Started (5 min ago)
       45 files pending
       Sound: bundled:sync-start
  [2] Syncthing: Large Transfer (1 hour ago)
       2.5 GB synced
       Sound: bundled:sync-large
  [3] rsync: Sync Complete (8 hours ago)
       12,450 files synchronized
       Sound: bundled:sync-complete

Recent Conflicts:
  [1] Dropbox: document.docx
       Conflict with another device
       Sound: bundled:sync-conflict

Sync Statistics:
  Total Services: 3
  Up to Date: 2
  Syncing: 1
  Conflicts Today: 1

Sound Settings:
  Complete: bundled:sync-complete
  Conflict: bundled:sync-conflict
  Error: bundled:sync-error
  Start: bundled:sync-start

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Sync monitoring doesn't play sounds directly:
- Monitoring feature using rsync/syncthing CLI
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
}

type SyncServiceInfo struct {
    Name        string
    Type        string // "dropbox", "rsync", "syncthing"
    Status      string // "idle", "syncing", "up_to_date", "error", "conflict"
    FilesSynced int
    FilesPending int
    LastSync    time.Time
    TransferSize int64
    Speed       int64 // bytes/sec
}

func (m *FileSyncMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.syncState = make(map[string]*SyncServiceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FileSyncMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSyncState()

    for {
        select {
        case <-ticker.C:
            m.checkSyncState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileSyncMonitor) snapshotSyncState() {
    m.checkSyncState()
}

func (m *FileSyncMonitor) checkSyncState() {
    for _, service := range m.config.WatchServices {
        info := m.checkService(service)
        if info != nil {
            m.processSyncStatus(info)
        }
    }
}

func (m *FileSyncMonitor) checkService(service string) *SyncServiceInfo {
    info := &SyncServiceInfo{
        Name: service,
        Type: service,
    }

    switch strings.ToLower(service) {
    case "dropbox":
        m.checkDropbox(info)
    case "syncthing":
        m.checkSyncthing(info)
    case "rsync":
        m.checkRsync(info)
    default:
        m.checkGenericSync(info, service)
    }

    return info
}

func (m *FileSyncMonitor) checkDropbox(info *SyncServiceInfo) {
    // Check if Dropbox is running
    cmd := exec.Command("pgrep", "-x", "Dropbox")
    err := cmd.Run()

    if err != nil {
        info.Status = "stopped"
        return
    }

    // Get status using dropbox CLI if available
    cmd = exec.Command("dropbox", "status")
    output, err := cmd.Output()

    if err != nil {
        info.Status = "unknown"
        return
    }

    outputStr := string(output)
    info.LastSync = time.Now()

    if strings.Contains(outputStr, "Up to date") {
        info.Status = "up_to_date"
    } else if strings.Contains(outputStr, "Syncing") {
        info.Status = "syncing"
        // Parse pending files
        re := regexp.MustEach(`(\d+) files`)
        matches := re.FindStringSubmatch(outputStr)
        if len(matches) >= 2 {
            info.FilesPending, _ = strconv.Atoi(matches[1])
        }
    } else if strings.Contains(outputStr, "error") || strings.Contains(outputStr, "offline") {
        info.Status = "error"
    } else {
        info.Status = "idle"
    }
}

func (m *FileSyncMonitor) checkSyncthing(info *SyncServiceInfo) {
    // Check if syncthing is running
    cmd := exec.Command("pgrep", "-x", "syncthing")
    err := cmd.Run()

    if err != nil {
        info.Status = "stopped"
        return
    }

    // Get status via API (default port 8384)
    cmd = exec.Command("curl", "-s", "http://127.0.0.1:8384/rest/system/config")
    output, err := cmd.Output()

    if err != nil {
        info.Status = "unknown"
        return
    }

    // Check sync status
    cmd = exec.Command("curl", "-s", "http://127.0.0.1:8384/rest/syncthing/status")
    statusOutput, _ := cmd.Output()

    outputStr := string(statusOutput)
    info.LastSync = time.Now()

    if strings.Contains(outputStr, "\"paused\":true") {
        info.Status = "paused"
    } else if strings.Contains(outputStr, "\"totalItems\":0") {
        info.Status = "up_to_date"
    } else {
        info.Status = "syncing"
        // Parse progress
        re := regexp.MustEach(`"need\":\s*(\d+)`)
        matches := re.FindStringSubmatch(outputStr)
        if len(matches) >= 2 {
            info.FilesPending, _ = strconv.Atoi(matches[1])
        }
    }
}

func (m *FileSyncMonitor) checkRsync(info *SyncServiceInfo) {
    // Check for running rsync processes
    cmd := exec.Command("pgrep", "-x", "rsync")
    err := cmd.Run()

    if err == nil {
        info.Status = "syncing"
        return
    }

    // Check last run from logs or status file
    info.Status = "idle"
    info.LastSync = time.Now()

    // Check for recent completion
    cmd = exec.Command("rsync", "--version")
    if err := cmd.Run(); err == nil {
        // rsync is available
    }
}

func (m *FileSyncMonitor) checkGenericSync(info *SyncServiceInfo, service string) {
    // Check for any running sync process
    cmd := exec.Command("pgrep", "-lf", service)
    output, err := cmd.Output()

    if err == nil && len(output) > 0 {
        info.Status = "syncing"
    } else {
        info.Status = "idle"
    }
}

func (m *FileSyncMonitor) processSyncStatus(info *SyncServiceInfo) {
    lastInfo := m.syncState[info.Name]

    if lastInfo == nil {
        m.syncState[info.Name] = info
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "syncing":
            if info.FilesPending > 0 && lastInfo.FilesPending == 0 {
                m.onSyncStarted(info)
            }
        case "up_to_date":
            if lastInfo.Status == "syncing" {
                m.onSyncComplete(info)
            }
        case "error":
            if m.config.SoundOnError {
                m.onSyncError(info)
            }
        case "conflict":
            if m.config.SoundOnConflict {
                m.onConflictDetected(info)
            }
        }
    }

    // Check for large transfers
    if info.TransferSize >= int64(m.config.LargeTransferMB)*1024*1024 {
        if lastInfo.TransferSize < int64(m.config.LargeTransferMB)*1024*1024 {
            m.onLargeTransfer(info)
        }
    }

    m.syncState[info.Name] = info
}

func (m *FileSyncMonitor) onSyncStarted(info *SyncServiceInfo) {
    key := fmt.Sprintf("start:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *FileSyncMonitor) onSyncComplete(info *SyncServiceInfo) {
    key := fmt.Sprintf("complete:%s", info.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileSyncMonitor) onSyncError(info *SyncServiceInfo) {
    key := fmt.Sprintf("error:%s", info.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileSyncMonitor) onConflictDetected(info *SyncServiceInfo) {
    key := fmt.Sprintf("conflict:%s", info.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["conflict"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileSyncMonitor) onLargeTransfer(info *SyncServiceInfo) {
    key := fmt.Sprintf("large:%s", info.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["large"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
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
| syncthing | System Tool | Free | Syncthing daemon |
| rsync | System Tool | Free | File sync tool |
| curl | System Tool | Free | HTTP client |

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
| macOS | Supported | Uses dropbox, syncthing, rsync |
| Linux | Supported | Uses dropbox, syncthing, rsync |
