# Feature: Sound Event Notification Sync

Sync notifications across devices.

## Summary

Synchronize notification settings and sounds across multiple machines.

## Motivation

- Cross-device consistency
- Unified notification experience
- Team configuration sync

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Sync Types

| Type | Description | Example |
|-------|-------------|---------|
| Config | Sync configuration | Settings only |
| Sounds | Sync sound files | Sounds folder |
| All | Complete sync | Config + sounds |
| Selective | Sync selected items | Choose what to sync |

### Configuration

```go
type NotificationSyncConfig struct {
    Enabled       bool              `json:"enabled"`
    Mode          string            `json:"mode"` // "file", "network", "cloud"
    SourcePath    string            `json:"source_path"` // Local path or network share
    TargetPath    string            `json:"target_path"` // Sync destination
    Include       []string          `json:"include"` // What to include
    Exclude       []string          `json:"exclude"` // What to exclude
    SyncOnStart   bool              `json:"sync_on_start"`
    AutoSync      bool              `json:"auto_sync"`
    SyncInterval  int              `json:"sync_interval_minutes"` // 60 default
    ConflictMode  string            `json:"conflict_mode"` // "local", "remote", "newest"
}

type SyncStatus struct {
    LastSync     time.Time
    Status       string // "idle", "syncing", "error"
    ItemsSynced  int
    Errors       []string
}
```

### Commands

```bash
/ccbell:sync status                 # Show sync status
/ccbell:sync mode file /path/to/share
/ccbell:sync mode network //server/share
/ccbell:sync include config sounds
/ccbell:sync exclude "*.wav"
/ccbell:sync now                    # Force sync now
/ccbell:sync dry-run                # Preview sync changes
/ccbell:sync interval 30            # Set sync interval
/ccbell:sync conflict local         # Resolve conflicts
```

### Output

```
$ ccbell:sync status

=== Sound Event Notification Sync ===

Status: Enabled
Mode: Network Share
Sync Interval: 60 min
Last Sync: 30 min ago

Source: //server/share/ccbell
Target: /Users/user/.claude

Sync Items:
  [x] Configuration (ccbell.config.json)
  [x] State (ccbell.state)
  [x] Sounds (sounds/*.aiff)
  [ ] Logs (ccbell.log)

Status: Idle
Items Synced: 15
Errors: 0

[Sync Now] [Preview] [Configure]
```

---

## Audio Player Compatibility

Notification sync doesn't play sounds:
- Sync feature
- No player changes required

---

## Implementation

### Sync Manager

```go
type SyncManager struct {
    config   *NotificationSyncConfig
    cfg      *config.Config
    running  bool
    stopCh   chan struct{}
    status   *SyncStatus
}

func (m *SyncManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.status = &SyncStatus{Status: "idle"}

    if m.config.SyncOnStart {
        go m.syncAll()
    }

    if m.config.AutoSync {
        go m.syncLoop()
    }
}

func (m *SyncManager) syncLoop() {
    ticker := time.NewTicker(time.Duration(m.config.SyncInterval) * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.syncAll()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SyncManager) syncAll() {
    m.status.Status = "syncing"
    m.status.Errors = []string{}

    switch m.config.Mode {
    case "file":
        m.syncFromFile()
    case "network":
        m.syncFromNetwork()
    case "cloud":
        m.syncFromCloud()
    }

    m.status.LastSync = time.Now()
    m.status.Status = "idle"
}

func (m *SyncManager) syncFromFile() {
    source := m.config.SourcePath
    target := m.getTargetPath()

    // Get list of files to sync
    files := m.getFilesToSync(source)

    for _, file := range files {
        if err := m.syncFile(source, target, file); err != nil {
            m.status.Errors = append(m.status.Errors, err.Error())
        } else {
            m.status.ItemsSynced++
        }
    }
}

func (m *SyncManager) getFilesToSync(source string) []string {
    var files []string

    for _, pattern := range m.config.Include {
        matches := filepath.Glob(filepath.Join(source, pattern))
        files = append(files, matches...)
    }

    return files
}

func (m *SyncManager) syncFile(source, target, file string) error {
    relPath, err := filepath.Rel(source, file)
    if err != nil {
        return err
    }

    destPath := filepath.Join(target, relPath)

    // Check if should skip
    if m.shouldSkip(relPath) {
        return nil
    }

    // Check for conflict
    if m.hasConflict(file, destPath) {
        switch m.config.ConflictMode {
        case "local":
            return m.copyFile(file, destPath)
        case "remote":
            return m.copyFile(destPath, file)
        case "newest":
            return m.syncNewest(file, destPath)
        }
    }

    // Simple copy
    return m.copyFile(file, destPath)
}

func (m *SyncManager) copyFile(src, dst string) error {
    data, err := os.ReadFile(src)
    if err != nil {
        return err
    }

    // Create parent directories
    os.MkdirAll(filepath.Dir(dst), 0755)

    return os.WriteFile(dst, data, 0644)
}

func (m *SyncManager) hasConflict(local, remote string) bool {
    localInfo, localErr := os.Stat(local)
    remoteInfo, remoteErr := os.Stat(remote)

    // No remote = no conflict
    if os.IsNotExist(remoteErr) {
        return false
    }

    // One doesn't exist = no conflict
    if os.IsNotExist(localErr) || localErr != nil {
        return false
    }

    // Compare modification times
    return localInfo.ModTime() != remoteInfo.ModTime()
}

func (m *SyncManager) syncNewest(local, remote string) error {
    localInfo, _ := os.Stat(local)
    remoteInfo, _ := os.Stat(remote)

    if localInfo.ModTime().After(remoteInfo.ModTime()) {
        return m.copyFile(local, remote)
    } else {
        return m.copyFile(remote, local)
    }
}

func (m *SyncManager) shouldSkip(path string) bool {
    for _, pattern := range m.config.Exclude {
        matched, _ := filepath.Match(pattern, filepath.Base(path))
        if matched {
            return true
        }
    }
    return false
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| filepath | Go Stdlib | Free | Path operations |
| os | Go Stdlib | Free | File operations |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config sync
- [Export feature](features/189-feat-sound-event-export.md) - Export for sync
- [Import feature](features/190-feat-sound-event-import.md) - Import for sync

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
