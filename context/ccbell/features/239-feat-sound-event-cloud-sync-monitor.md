# Feature: Sound Event Cloud Sync Monitor

Play sounds for cloud storage sync events.

## Summary

Monitor cloud storage sync status, file synchronization, and upload/download progress, playing sounds for sync events.

## Motivation

- Sync completion alerts
- Upload feedback
- Conflict detection
- Offline/online awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Cloud Sync Events

| Event | Description | Example |
|-------|-------------|---------|
| Sync Started | Sync began | Files uploading |
| Sync Complete | Sync finished | All synced |
| File Synced | Single file synced | document.txt |
| Conflict | Sync conflict detected | Duplicate file |
| Upload Complete | Upload finished | 100% uploaded |
| Download Complete | Download finished | Files received |

### Configuration

```go
type CloudSyncMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    Services         []string          `json:"services"` // "dropbox", "drive", "icloud"
    SoundOnSync      bool              `json:"sound_on_sync"`
    SoundOnComplete  bool              `json:"sound_on_complete"`
    SoundOnConflict  bool              `json:"sound_on_conflict"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type CloudSyncEvent struct {
    Service   string
    EventType string // "started", "complete", "file_synced", "conflict"
    FileName  string
    Progress  float64
}
```

### Commands

```bash
/ccbell:cloud-sync status         # Show sync status
/ccbell:cloud-sync add dropbox    # Add service
/ccbell:cloud-sync remove icloud  # Remove service
/ccbell:cloud-sync sound sync <sound>
/ccbell:cloud-sync sound complete <sound>
/ccbell:cloud-sync test           # Test sync sounds
```

### Output

```
$ ccbell:cloud-sync status

=== Sound Event Cloud Sync Monitor ===

Status: Enabled
Sync Sounds: Yes
Complete Sounds: Yes

Monitored Services: 3

[1] Dropbox
    Status: Synced
    Last Sync: 5 min ago
    Files: 1,234
    Progress: 100%
    Sound: bundled:stop

[2] Google Drive
    Status: Syncing
    Files Syncing: 5
    Progress: 67%
    Sound: bundled:stop

[3] iCloud Drive
    Status: Offline
    Last Sync: 2 hours ago
    Sound: bundled:stop

Recent Events:
  [1] Dropbox: Sync Complete (5 min ago)
  [2] Google Drive: 3 files synced (10 min ago)
  [3] iCloud: Conflict detected (1 hour ago)

Sound Settings:
  Sync Started: bundled:stop
  Sync Complete: bundled:stop
  Conflict: bundled:stop

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Cloud sync monitoring doesn't play sounds directly:
- Monitoring feature using CLI tools and APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cloud Sync Monitor

```go
type CloudSyncMonitor struct {
    config      *CloudSyncMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    syncStates  map[string]string
    lastProgress map[string]float64
}

func (m *CloudSyncMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.syncStates = make(map[string]string)
    m.lastProgress = make(map[string]float64)
    go m.monitor()
}

func (m *CloudSyncMonitor) monitor() {
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

func (m *CloudSyncMonitor) checkSyncStatus() {
    for _, service := range m.config.Services {
        status := m.getSyncStatus(service)
        m.evaluateService(service, status)
    }
}

func (m *CloudSyncMonitor) getSyncStatus(service string) CloudSyncEvent {
    event := CloudSyncEvent{
        Service: service,
    }

    switch strings.ToLower(service) {
    case "dropbox":
        return m.getDropboxStatus(event)
    case "drive", "google drive":
        return m.getGoogleDriveStatus(event)
    case "icloud", "icloud drive":
        return m.getiCloudStatus(event)
    case "onedrive":
        return m.getOneDriveStatus(event)
    }

    return event
}

func (m *CloudSyncMonitor) getDropboxStatus(event CloudSyncEvent) CloudSyncEvent {
    cmd := exec.Command("dropbox", "status")
    output, err := cmd.Output()
    if err != nil {
        event.EventType = "offline"
        return event
    }

    status := string(output)

    if strings.Contains(status, "Up to date") {
        event.EventType = "complete"
        event.Progress = 100
    } else if strings.Contains(status, "Syncing") {
        event.EventType = "syncing"
        // Parse progress
        match := regexp.MustCompile(`(\d+) files`).FindStringSubmatch(status)
        if match != nil {
            event.Progress = 50 // Simplified
        }
    } else if strings.Contains(status, "Connecting") {
        event.EventType = "connecting"
    }

    return event
}

func (m *CloudSyncMonitor) getGoogleDriveStatus(event CloudSyncEvent) CloudSyncEvent {
    // Use rclone or drive CLI
    cmd := exec.Command("drive", "status")
    output, err := cmd.Output()
    if err != nil {
        // Try rclone
        cmd = exec.Command("rclone", "lsd", "drive:")
        _, err = cmd.Output()
        if err != nil {
            event.EventType = "offline"
            return event
        }
    }

    status := string(output)

    if strings.Contains(status, "syncing") {
        event.EventType = "syncing"
    } else if strings.Contains(status, "done") {
        event.EventType = "complete"
        event.Progress = 100
    }

    return event
}

func (m *CloudSyncMonitor) getiCloudStatus(event CloudSyncEvent) CloudSyncEvent {
    // Check if iCloud is available
    cmd := exec.Command("ls", os.Getenv("HOME")+"/Library/Mobile Documents")
    _, err := cmd.Output()
    if err != nil {
        event.EventType = "offline"
        return event
    }

    // Check for icloud.com documents
    event.EventType = "idle"
    return event
}

func (m *CloudSyncMonitor) getOneDriveStatus(event CloudSyncEvent) CloudSyncEvent {
    // Check for onedrive process
    cmd := exec.Command("pgrep", "-x", "onedrive")
    err := cmd.Run()

    if err != nil {
        event.EventType = "offline"
        return event
    }

    event.EventType = "syncing"
    return event
}

func (m *CloudSyncMonitor) evaluateService(service string, event CloudSyncEvent) {
    lastState := m.syncStates[service]
    m.syncStates[service] = event.EventType

    // Detect state changes
    if event.EventType == "syncing" && lastState != "syncing" && lastState != "syncing" {
        m.onSyncStarted(service)
    } else if event.EventType == "complete" && lastState != "complete" {
        m.onSyncComplete(service)
    } else if event.EventType == "conflict" {
        m.onConflict(service)
    }

    m.lastProgress[service] = event.Progress
}

func (m *CloudSyncMonitor) onSyncStarted(service string) {
    if !m.config.SoundOnSync {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CloudSyncMonitor) onSyncComplete(service string) {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CloudSyncMonitor) onConflict(service string) {
    if !m.config.SoundOnConflict {
        return
    }

    sound := m.config.Sounds["conflict"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dropbox | CLI Tool | Free | Dropbox client |
| drive | Go Module | Free | Google Drive CLI |
| rclone | Binary | Free | Cloud sync tool |
| onedrive | APT | Free | OneDrive Linux |

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
| macOS | Supported | Uses CLI tools |
| Linux | Supported | Uses CLI tools |
| Windows | Not Supported | ccbell only supports macOS/Linux |
