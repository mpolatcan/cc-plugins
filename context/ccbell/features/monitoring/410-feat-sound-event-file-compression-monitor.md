# Feature: Sound Event File Compression Monitor

Play sounds for compression operations, archive creation, and extraction events.

## Summary

Monitor file compression operations for completion, progress, and errors, playing sounds for compression events.

## Motivation

- Compression completion alerts
- Archive creation feedback
- Extraction notifications
- Error detection
- Large file handling

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### File Compression Events

| Event | Description | Example |
|-------|-------------|---------|
| Compression Started | Compression began | tar.gz |
| Compression Complete | Done successfully | finished |
| Extraction Started | Archive extraction | unzip |
| Extraction Complete | Extracted successfully | done |
| Large Archive | Size > threshold | > 1GB |
| Compression Failed | Error occurred | failed |

### Configuration

```go
type FileCompressionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchFormats      []string          `json:"watch_formats"` // "tar.gz", "zip", "7z", "*"
    LargeThresholdMB  int               `json:"large_threshold_mb"` // 1024 default
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnLarge      bool              `json:"sound_on_large"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:compress status                # Show compression status
/ccbell:compress add tar.gz            # Add format to watch
/ccbell:compress threshold 1024        # Set size threshold
/ccbell:compress sound complete <sound>
/ccbell:compress sound fail <sound>
/ccbell:compress test                  # Test compression sounds
```

### Output

```
$ ccbell:compress status

=== Sound Event File Compression Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes
Large Sounds: Yes

Watched Formats: 4
Large File Threshold: 1 GB

Recent Compression Operations:

[1] backup.tar.gz (Compress)
    Status: COMPLETED
    Original: 5.2 GB
    Compressed: 1.8 GB (65% reduction)
    Duration: 5 min
    Sound: bundled:compress-backup

[2] documents.zip (Extract)
    Status: COMPLETED
    Extracted: 450 MB
    Files: 1,250
    Duration: 30 sec
    Sound: bundled:compress-zip

[3] archive.7z (Compress)
    Status: COMPLETED (LARGE)
    Original: 2.5 GB
    Compressed: 800 MB (68% reduction)
    Duration: 15 min
    Sound: bundled:compress-7z *** LARGE ***

[4] log-files.tar.xz (Compress)
    Status: FAILED
    Error: Write error (disk full)
    Original: 500 MB
    Sound: bundled:compress-fail *** FAILED ***

Recent Events:
  [1] archive.7z: Large Archive (5 min ago)
       2.5 GB compressed
  [2] log-files.tar.xz: Compression Failed (1 hour ago)
       Disk full error
  [3] backup.tar.gz: Compression Complete (2 hours ago)
       65% compression ratio

Compression Statistics:
  Operations Today: 12
  Completed: 10
  Failed: 2
  Total Compressed: 15 GB

Sound Settings:
  Complete: bundled:compress-complete
  Fail: bundled:compress-fail
  Large: bundled:compress-large

[Configure] [Test All]
```

---

## Audio Player Compatibility

Compression monitoring doesn't play sounds directly:
- Monitoring feature using tar/zip/7z
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Compression Monitor

```go
type FileCompressionMonitor struct {
    config          *FileCompressionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    operationState  map[string]*CompressionInfo
    lastEventTime   map[string]time.Time
}

type CompressionInfo struct {
    Name       string
    Type       string // "compress", "extract"
    Format     string
    OriginalSize int64
    CompressedSize int64
    Status     string // "running", "completed", "failed"
    Duration   time.Duration
    Error      string
    StartedAt  time.Time
}

func (m *FileCompressionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.operationState = make(map[string]*CompressionInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FileCompressionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkOperations()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileCompressionMonitor) checkOperations() {
    // Check for running compression processes
    m.findCompressionProcesses()

    // Check watched directories for new archives
    m.checkWatchedDirectories()
}

func (m *FileCompressionMonitor) findCompressionProcesses() {
    processes := []string{"tar", "gzip", "bzip2", "xz", "zip", "7z", "rar"}

    for _, proc := range processes {
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
            m.checkProcessOperation(pid, proc)
        }
    }
}

func (m *FileCompressionMonitor) checkProcessOperation(pid int, procName string) {
    // Get command line
    cmd := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "args=")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    args := strings.TrimSpace(string(output))
    operationType := m.detectOperationType(args, procName)
    format := m.detectFormat(args, procName)

    if operationType == "unknown" {
        return
    }

    id := fmt.Sprintf("%d", pid)
    if _, exists := m.operationState[id]; exists {
        return // Already tracking
    }

    fileName := m.extractFileName(args)

    info := &CompressionInfo{
        Name:      fileName,
        Type:      operationType,
        Format:    format,
        Status:    "running",
        StartedAt: time.Now(),
    }

    m.operationState[id] = info
    m.onOperationStarted(info)
}

func (m *FileCompressionMonitor) detectOperationType(args, procName string) string {
    argsLower := strings.ToLower(args)

    // Extraction indicators
    if strings.Contains(argsLower, "-x") || strings.Contains(argsLower, "--extract") ||
       strings.Contains(argsLower, "-e") || strings.HasPrefix(argsLower, "un") {
        return "extract"
    }

    // Compression indicators
    if strings.Contains(argsLower, "-c") || strings.Contains(argsLower, "--create") ||
       strings.Contains(argsLower, "-a") || strings.HasPrefix(argsLower, procName) {
        return "compress"
    }

    return "unknown"
}

func (m *FileCompressionMonitor) detectFormat(args, procName string) string {
    argsLower := strings.ToLower(args)

    if strings.HasSuffix(argsLower, ".tar.gz") || strings.Contains(argsLower, ".tgz") {
        return "tar.gz"
    } else if strings.HasSuffix(argsLower, ".tar.bz2") {
        return "tar.bz2"
    } else if strings.HasSuffix(argsLower, ".tar.xz") {
        return "tar.xz"
    } else if strings.HasSuffix(argsLower, ".zip") {
        return "zip"
    } else if strings.HasSuffix(argsLower, ".7z") || strings.HasSuffix(argsLower, ".7zip") {
        return "7z"
    } else if strings.HasSuffix(argsLower, ".rar") {
        return "rar"
    } else if strings.HasSuffix(argsLower, ".gz") {
        return "gz"
    } else if strings.HasSuffix(argsLower, ".bz2") {
        return "bz2"
    }

    return procName
}

func (m *FileCompressionMonitor) extractFileName(args string) string {
    parts := strings.Fields(args)
    for i, part := range parts {
        if strings.HasPrefix(part, "/") || strings.HasPrefix(part, ".") {
            if i+1 < len(parts) && !strings.HasPrefix(parts[i+1], "-") {
                return parts[i+1]
            }
            return part
        }
    }
    return "unknown"
}

func (m *FileCompressionMonitor) checkWatchedDirectories() {
    // Check for newly created archives in common locations
    dirs := []string{"~/Downloads", "~/Documents", "/tmp"}

    for _, dir := range dirs {
        expandedDir := m.expandPath(dir)

        entries, err := os.ReadDir(expandedDir)
        if err != nil {
            continue
        }

        for _, entry := range entries {
            if entry.IsDir() {
                continue
            }

            name := entry.Name()
            ext := m.getExtension(name)

            if m.shouldWatchFormat(ext) {
                // Check if recently modified (within last minute)
                info, _ := entry.Info()
                if time.Since(info.ModTime()) < time.Minute {
                    m.detectArchiveOperation(name, expandedDir)
                }
            }
        }
    }
}

func (m *FileCompressionMonitor) detectArchiveOperation(name, dir string) {
    fullPath := filepath.Join(dir, name)

    // Check if this is a new archive
    info, err := os.Stat(fullPath)
    if err != nil {
        return
    }

    id := fullPath

    if _, exists := m.operationState[id]; exists {
        return
    }

    format := m.getExtension(name)
    infoStruct := &CompressionInfo{
        Name:           name,
        Format:         format,
        OriginalSize:   info.Size(),
        Status:         "completed",
        CompressedSize: info.Size(),
        StartedAt:      info.ModTime(),
        Duration:       time.Since(info.ModTime()),
    }

    // Check if large
    if infoStruct.OriginalSize >= int64(m.config.LargeThresholdMB)*1024*1024 {
        infoStruct.Status = "completed_large"
        if m.config.SoundOnLarge {
            m.onLargeArchive(infoStruct)
        }
    }

    if m.config.SoundOnComplete {
        m.onOperationComplete(infoStruct)
    }

    // Auto-cleanup old state
    go func() {
        time.Sleep(5 * time.Minute)
        delete(m.operationState, id)
    }()
}

func (m *FileCompressionMonitor) getExtension(name string) string {
    exts := []string{".tar.gz", ".tar.bz2", ".tar.xz", ".zip", ".7z", ".rar", ".gz", ".bz2", ".xz"}

    for _, ext := range exts {
        if strings.HasSuffix(strings.ToLower(name), ext) {
            return ext
        }
    }

    return filepath.Ext(name)
}

func (m *FileCompressionMonitor) shouldWatchFormat(format string) bool {
    if len(m.config.WatchFormats) == 0 {
        return true
    }

    for _, f := range m.config.WatchFormats {
        if f == "*" || f == format || strings.Contains(format, f) {
            return true
        }
    }

    return false
}

func (m *FileCompressionMonitor) onOperationStarted(info *CompressionInfo) {
    // Optional: sound when compression starts
}

func (m *FileCompressionMonitor) onOperationComplete(info *CompressionInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s", info.Format)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileCompressionMonitor) onLargeArchive(info *CompressionInfo) {
    if !m.config.SoundOnLarge {
        return
    }

    key := fmt.Sprintf("large:%s", info.Format)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["large"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileCompressionMonitor) onOperationFailed(info *CompressionInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", info.Format)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileCompressionMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *FileCompressionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| pgrep | System Tool | Free | Process listing |
| ps | System Tool | Free | Process status |
| tar | System Tool | Free | Archive tool |
| zip | System Tool | Free | Archive tool |

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
| macOS | Supported | Uses pgrep, ps, tar, zip |
| Linux | Supported | Uses pgrep, ps, tar, zip |
