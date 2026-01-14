# Feature: Sound Event File Download Monitor

Play sounds for file download and transfer events.

## Summary

Monitor file downloads, transfer progress, and completion, playing sounds for download events.

## Motivation

- Download completion alerts
- Large file warnings
- Transfer feedback
- Speed notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### File Download Events

| Event | Description | Example |
|-------|-------------|---------|
| Download Started | Download began | curl started |
| Download Complete | Download finished | 100% received |
| Download Failed | Download errored | Connection reset |
| Large File | Large download | > 1GB |
| Fast Download | High speed detected | > 100 MB/s |
| Paused | Download paused | User paused |

### Configuration

```go
type FileDownloadMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchFolders    []string          `json:"watch_folders"` // ~/Downloads
    LargeThreshold  int64             `json:"large_threshold_mb"` // 1024 MB
    SoundOnComplete bool              `json:"sound_on_complete"`
    SoundOnFail     bool              `json:"sound_on_fail"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 5 default
}

type FileDownloadEvent struct {
    FileName   string
    FileSize   int64
    Downloaded int64
    Speed      float64 // bytes/sec
    EventType  string // "started", "complete", "failed", "paused"
}
```

### Commands

```bash
/ccbell:download status           # Show download status
/ccbell:download add ~/Downloads  # Add folder to watch
/ccbell:download threshold 1000   # Set large file threshold
/ccbell:download sound complete <sound>
/ccbell:download sound failed <sound>
/ccbell:download test             # Test download sounds
```

### Output

```
$ ccbell:download status

=== Sound Event File Download Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes
Large File Threshold: 1 GB

Watched Folders: 1

[1] ~/Downloads
    Active Downloads: 3
    Total Progress: 67%

[1] ubuntu-22.04.iso
    Size: 3.2 GB
    Progress: 45%
    Speed: 45 MB/s
    ETA: 4 min
    Status: Downloading
    Sound: bundled:stop

[2] document.pdf
    Size: 15 MB
    Progress: 100%
    Status: COMPLETED
    Sound: bundled:stop

[3] archive.zip
    Size: 1.5 GB
    Progress: 88%
    Speed: 12 MB/s
    ETA: 1 min
    Status: Downloading
    Sound: bundled:stop

Recent Events:
  [1] document.pdf: Download Complete (5 min ago)
  [2] ubuntu-22.04.iso: Large File Detected (10 min ago)
  [3] archive.zip: Download Started (30 min ago)

Sound Settings:
  Complete: bundled:stop
  Failed: bundled:stop
  Large File: bundled:stop

[Configure] [Add Folder] [Test All]
```

---

## Audio Player Compatibility

File download monitoring doesn't play sounds directly:
- Monitoring feature using file system and process tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Download Monitor

```go
type FileDownloadMonitor struct {
    config           *FileDownloadMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    activeDownloads  map[string]*DownloadInfo
}

type DownloadInfo struct {
    FileName   string
    TotalSize  int64
    Downloaded int64
    StartTime  time.Time
    LastCheck  time.Time
}

func (m *FileDownloadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeDownloads = make(map[string]*DownloadInfo)
    go m.monitor()
}

func (m *FileDownloadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDownloads()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileDownloadMonitor) checkDownloads() {
    for _, folder := range m.config.WatchFolders {
        m.scanDownloads(folder)
    }
}

func (m *FileDownloadMonitor) scanDownloads(folder string) {
    // Expand home directory
    if strings.HasPrefix(folder, "~") {
        folder = filepath.Join(os.Getenv("HOME"), folder[1:])
    }

    // Look for incomplete downloads
    entries, err := os.ReadDir(folder)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if entry.IsDir() {
            continue
        }

        name := entry.Name()

        // Check for download patterns
        if m.isDownloadFile(name) {
            info := m.getDownloadInfo(folder, name)
            m.evaluateDownload(name, info)
        }
    }
}

func (m *FileDownloadMonitor) isDownloadFile(name string) bool {
    patterns := []string{
        ".download", ".part", ".crdownload", ".tmp",
    }

    for _, pattern := range patterns {
        if strings.HasSuffix(name, pattern) {
            return true
        }
    }

    return false
}

func (m *FileDownloadMonitor) getDownloadInfo(folder, name string) *DownloadInfo {
    path := filepath.Join(folder, name)

    info := &DownloadInfo{
        FileName:   name,
        Downloaded: 0,
        LastCheck:  time.Now(),
    }

    // Get file size
    fileInfo, err := os.Stat(path)
    if err == nil {
        info.Downloaded = fileInfo.Size()
    }

    // Check for .crdownload (Chrome) pattern
    if strings.HasSuffix(name, ".crdownload") {
        // Get base name without extension
        baseName := strings.TrimSuffix(name, ".crdownload")
        info.FileName = baseName
    }

    // Check for .download pattern
    if strings.HasSuffix(name, ".download") {
        baseName := strings.TrimSuffix(name, ".download")
        info.FileName = baseName
    }

    // Try to determine total size from metadata
    totalSize := m.estimateTotalSize(folder, name)
    if totalSize > 0 {
        info.TotalSize = totalSize
    }

    return info
}

func (m *FileDownloadMonitor) estimateTotalSize(folder, name string) int64 {
    // Try common patterns for total size files
    patterns := []string{
        name + ".size",
        name + ".meta",
        strings.TrimSuffix(name, ".download") + ".size",
    }

    for _, pattern := range patterns {
        path := filepath.Join(folder, pattern)
        if data, err := os.ReadFile(path); err == nil {
            if size, err := strconv.ParseInt(string(data), 10, 64); err == nil {
                return size
            }
        }
    }

    return 0
}

func (m *FileDownloadMonitor) evaluateDownload(name string, info *DownloadInfo) {
    key := name

    lastInfo := m.activeDownloads[key]

    if lastInfo == nil {
        // New download
        m.activeDownloads[key] = info
        m.onDownloadStarted(info)
        return
    }

    m.activeDownloads[key] = info

    // Check if download is complete
    if info.Downloaded > 0 && info.TotalSize > 0 &&
       info.Downloaded >= info.TotalSize {
        delete(m.activeDownloads, key)
        m.onDownloadComplete(info)
        return
    }

    // Check for large file
    if info.Downloaded > int64(m.config.LargeThreshold)*1024*1024 &&
       lastInfo.Downloaded <= int64(m.config.LargeThreshold)*1024*1024 {
        m.onLargeFile(info)
    }
}

func (m *FileDownloadMonitor) onDownloadStarted(info *DownloadInfo) {
    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *FileDownloadMonitor) onDownloadComplete(info *DownloadInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *FileDownloadMonitor) onDownloadFailed(info *DownloadInfo) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *FileDownloadMonitor) onLargeFile(info *DownloadInfo) {
    sound := m.config.Sounds["large_file"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| os | Go Stdlib | Free | File operations |
| filepath | Go Stdlib | Free | Path operations |

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
| macOS | Supported | Uses file system |
| Linux | Supported | Uses file system |
| Windows | Not Supported | ccbell only supports macOS/Linux |
