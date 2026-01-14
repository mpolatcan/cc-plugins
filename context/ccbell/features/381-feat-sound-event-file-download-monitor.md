# Feature: Sound Event File Download Monitor

Play sounds for completed downloads, transfer progress, and download errors.

## Summary

Monitor file downloads, transfer progress, and completion events, playing sounds for download events.

## Motivation

- Download completion alerts
- Transfer progress tracking
- Error detection
- Large file awareness
- Download queue management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### File Download Events

| Event | Description | Example |
|-------|-------------|---------|
| Download Complete | File finished | 100% |
| Download Failed | Transfer error | network error |
| Progress Milestone | 25/50/75% reached | half done |
| Download Started | New download | curl start |
| Speed Dropped | Speed dropped low | throttled |

### Configuration

```go
type FileDownloadMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDir          string            `json:"watch_dir"` // "$HOME/Downloads"
    WatchProcesses    []string          `json:"watch_processes"` // "curl", "wget", "aria2c"
    Milestones        []int             `json:"milestones"` // [25, 50, 75, 100]
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnProgress   bool              `json:"sound_on_progress"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}
```

### Commands

```bash
/ccbell:download status                # Show download status
/ccbell:download dir ~/Downloads       # Set watch directory
/ccbell:download milestones 50 100     # Set milestones
/ccbell:download sound complete <sound>
/ccbell:download test                  # Test download sounds
```

### Output

```
$ ccbell:download status

=== Sound Event File Download Monitor ===

Status: Enabled
Watch Directory: ~/Downloads
Complete Sounds: Yes
Fail Sounds: Yes

Active Downloads: 3

[1] ubuntu-22.04.iso
    Progress: 75%
    Size: 2.5 GB / 3.4 GB
    Speed: 15 MB/s
    ETA: 1 min
    Source: http://archive.ubuntu.com
    Sound: bundled:download-iso

[2] large-file.zip
    Progress: 50%
    Size: 1.0 GB / 2.0 GB
    Speed: 5 MB/s
    ETA: 3 min
    Source: https://example.com
    Sound: bundled:download-zip

[3] backup.tar.gz
    Progress: 25%
    Size: 500 MB / 2.0 GB
    Speed: 20 MB/s
    ETA: 1 min
    Source: /mnt/backup
    Destination: ~/backups
    Sound: bundled:download-backup

Recent Events:
  [1] ubuntu-22.04.iso: Progress 75% (1 min ago)
       Next milestone: 100%
  [ [2] large-file.zip: Progress 50% (5 min ago)
       Halfway there!
  [3] ubuntu-22.04.iso: Download Started (10 min ago)

Download Statistics:
  Completed Today: 5
  Failed Today: 1
  Total Downloaded: 12.5 GB

Sound Settings:
  Complete: bundled:download-complete
  Fail: bundled:download-fail
  Progress: bundled:download-progress

[Configure] [Test All]
```

---

## Audio Player Compatibility

Download monitoring doesn't play sounds directly:
- Monitoring feature using lsof/inotifywait
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Download Monitor

```go
type FileDownloadMonitor struct {
    config          *FileDownloadMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    downloadState   map[string]*DownloadInfo
    lastEventTime   map[string]time.Time
}

type DownloadInfo struct {
    Name       string
    PID        int
    Source     string
    DestPath   string
    TotalSize  int64
    CurrentSize int64
    Progress   int
    Speed      int64 // bytes per second
    Status     string // "downloading", "complete", "failed"
    Started    time.Time
}

func (m *FileDownloadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.downloadState = make(map[string]*DownloadInfo)
    m.lastEventTime = make(map[string]time.Time)
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
    // Find active downloads by process
    m.findActiveDownloads()

    // Check download directory for new partial files
    m.checkDownloadDirectory()
}

func (m *FileDownloadMonitor) findActiveDownloads() {
    for _, proc := range m.config.WatchProcesses {
        cmd := exec.Command("pgrep", "-x", proc)
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            line = strings.TrimSpace(line)
            if line == "" {
                continue
            }

            pid, _ := strconv.Atoi(line)
            m.checkDownloadProcess(proc, pid)
        }
    }
}

func (m *FileDownloadMonitor) checkDownloadProcess(proc string, pid int) {
    // Get file descriptors for network connections
    cmd := exec.Command("lsof", "-p", strconv.Itoa(pid), "-n")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        // Look for HTTP/HTTPS connections and downloaded files
        if strings.Contains(line, "REG") && strings.Contains(line, m.config.WatchDir) {
            parts := strings.Fields(line)
            if len(parts) >= 9 {
                filePath := parts[8]
                m.updateDownloadProgress(filePath, pid)
            }
        }
    }
}

func (m *FileDownloadMonitor) checkDownloadDirectory() {
    watchDir := m.expandPath(m.config.WatchDir)

    cmd := exec.Command("ls", "-la", watchDir)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Look for partially downloaded files
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, ".part") || strings.Contains(line, ".tmp") ||
           strings.HasPrefix(line, ".") && !strings.HasPrefix(line, "..") {
            parts := strings.Fields(line)
            if len(parts) >= 9 {
                fileName := parts[8]
                filePath := filepath.Join(watchDir, fileName)
                m.updateDownloadProgress(filePath, 0)
            }
        }
    }
}

func (m *FileDownloadMonitor) updateDownloadProgress(filePath string, pid int) {
    // Get current file size
    fileInfo, err := os.Stat(filePath)
    if err != nil {
        return
    }

    currentSize := fileInfo.Size()

    // Create or update download info
    id := fmt.Sprintf("%s-%d", filepath.Base(filePath), pid)
    info := m.downloadState[id]

    if info == nil {
        info = &DownloadInfo{
            Name:       filepath.Base(filePath),
            PID:        pid,
            DestPath:   filePath,
            Started:    time.Now(),
            Status:     "downloading",
        }
        m.downloadState[id] = info
        m.onDownloadStarted(info)
    }

    // Calculate progress if total size known
    if info.TotalSize > 0 {
        newProgress := int((currentSize * 100) / info.TotalSize)
        if newProgress > info.Progress {
            info.Progress = newProgress
            m.onProgressMilestone(info, newProgress)
        }
    }

    info.CurrentSize = currentSize

    // Calculate speed
    elapsed := time.Since(info.Started)
    if elapsed > 0 {
        info.Speed = currentSize / int64(elapsed.Seconds())
    }
}

func (m *FileDownloadMonitor) onDownloadStarted(info *DownloadInfo) {
    // Optional: sound when download starts
}

func (m *FileDownloadMonitor) onProgressMilestone(info *DownloadInfo, progress int) {
    if !m.config.SoundOnProgress {
        return
    }

    // Check if this is a configured milestone
    for _, milestone := range m.config.Milestones {
        if progress == milestone {
            key := fmt.Sprintf("progress:%s:%d", info.Name, progress)
            if m.shouldAlert(key, 5*time.Minute) {
                sound := m.config.Sounds["progress"]
                if sound != "" {
                    m.player.Play(sound, 0.3)
                }
            }
            break
        }
    }

    // Check for completion
    if progress >= 100 {
        m.onDownloadComplete(info)
    }
}

func (m *FileDownloadMonitor) onDownloadComplete(info *DownloadInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    info.Status = "complete"

    key := fmt.Sprintf("complete:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }

    // Clean up state
    delete(m.downloadState, fmt.Sprintf("%s-%d", info.Name, info.PID))
}

func (m *FileDownloadMonitor) onDownloadFailed(info *DownloadInfo) {
    if !m.config.SoundOnFail {
        return
    }

    info.Status = "failed"

    key := fmt.Sprintf("fail:%s", info.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileDownloadMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *FileDownloadMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| lsof | System Tool | Free | Open files |
| pgrep | System Tool | Free | Process listing |
| ls | System Tool | Free | Directory listing |

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
| macOS | Supported | Uses lsof, pgrep, ls |
| Linux | Supported | Uses lsof, pgrep, ls |
