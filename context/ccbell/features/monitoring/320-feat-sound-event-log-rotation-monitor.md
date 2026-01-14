# Feature: Sound Event Log Rotation Monitor

Play sounds for log file rotation and cleanup events.

## Summary

Monitor log file rotation, compression, and cleanup events, playing sounds for rotation events.

## Motivation

- Log management awareness
- Disk space feedback
- Rotation detection
- Archive completion alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Log Rotation Events

| Event | Description | Example |
|-------|-------------|---------|
| Rotated | Log file rotated | log -> log.1 |
| Compressed | Rotated log compressed | log.1.gz |
| Deleted | Old log deleted | log.7.gz deleted |
| Truncated | Log truncated | size limit |

### Configuration

```go
type LogRotationMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchPaths      []string          `json:"watch_paths"` // "/var/log", "/home/*/logs"
    FilePatterns    []string          `json:"file_patterns"` // "*.log", "syslog*"
    MaxVersions     int               `json:"max_versions"` // 5 default
    SoundOnRotate   bool              `json:"sound_on_rotate"]
    SoundOnDelete   bool              `json:"sound_on_delete"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 60 default
}

type LogRotationEvent struct {
    Path      string
    FileName  string
    OldSize   int64
    NewSize   int64
    EventType string // "rotate", "compress", "delete", "truncate"
}
```

### Commands

```bash
/ccbell:logrot status                 # Show log rotation status
/ccbell:logrot add /var/log           # Add path to watch
/ccbell:logrot remove /var/log
/ccbell:logrot sound rotate <sound>
/ccbell:logrot sound delete <sound>
/ccbell:logrot test                   # Test log rotation sounds
```

### Output

```
$ ccbell:logrot status

=== Sound Event Log Rotation Monitor ===

Status: Enabled
Rotate Sounds: Yes
Delete Sounds: Yes

Watched Paths: 2

[1] /var/log
    Files: 45
    Rotations today: 12
    Space freed: 500 MB
    Sound: bundled:stop

[2] /home/user/logs
    Files: 8
    Rotations today: 3
    Space freed: 50 MB
    Sound: bundled:logrot-rotate

Recent Events:
  [1] /var/log/syslog: Rotated (5 min ago)
       100 MB -> 0 (new log created)
  [2] /var/log/syslog.1.gz: Compressed (5 min ago)
       100 MB -> 10 MB
  [3] /var/log/alternatives.log: Deleted (1 hour ago)
       log.7.gz removed

Log Rotation Statistics:
  Total rotations: 15
  Total compressed: 10
  Total deleted: 5

Sound Settings:
  Rotate: bundled:logrot-rotate
  Compress: bundled:stop
  Delete: bundled:logrot-delete

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Log rotation monitoring doesn't play sounds directly:
- Monitoring feature using filesystem
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Log Rotation Monitor

```go
type LogRotationMonitor struct {
    config          *LogRotationMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    fileState       map[string]*LogFileInfo
    lastEventTime   map[string]time.Time
}

type LogFileInfo struct {
    Path       string
    Name       string
    Size       int64
    Modified   time.Time
    IsGzipped  bool
}

func (m *LogRotationMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fileState = make(map[string]*LogFileInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *LogRotationMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotLogFiles()

    for {
        select {
        case <-ticker.C:
            m.checkLogRotation()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LogRotationMonitor) snapshotLogFiles() {
    for _, path := range m.config.WatchPaths {
        m.scanLogPath(path, false)
    }
}

func (m *LogRotationMonitor) scanLogPath(path string, reportChanges bool) {
    entries, err := os.ReadDir(path)
    if err != nil {
        return
    }

    currentFiles := make(map[string]*LogFileInfo)

    for _, entry := range entries {
        if !m.shouldWatchFile(entry.Name()) {
            continue
        }

        fullPath := filepath.Join(path, entry.Name())
        info, err := entry.Info()
        if err != nil {
            continue
        }

        fileInfo := &LogFileInfo{
            Path:      fullPath,
            Name:      entry.Name(),
            Size:      info.Size(),
            Modified:  info.ModTime(),
            IsGzipped: strings.HasSuffix(entry.Name(), ".gz"),
        }

        currentFiles[fullPath] = fileInfo

        if reportChanges {
            m.checkLogFile(fullPath, fileInfo)
        }
    }

    if reportChanges {
        m.checkDeletedRotations(currentFiles)
    }

    m.fileState = currentFiles
}

func (m *LogRotationMonitor) checkLogRotation() {
    for _, path := range m.config.WatchPaths {
        m.scanLogPath(path, true)
    }
}

func (m *LogRotationMonitor) checkLogFile(path string, current *LogFileInfo) {
    last, exists := m.fileState[path]

    // New file appeared (rotation happened)
    if !exists {
        // Check if this is a rotated file (e.g., log.1, log.1.gz)
        if m.isRotatedFile(current.Name) {
            m.onLogRotated(path, current)
        }
        return
    }

    // File was gzipped (compression after rotation)
    if !last.IsGzipped && current.IsGzipped {
        m.onLogCompressed(path, current)
    }

    // File was truncated (size reset)
    if last.Size > 0 && current.Size == 0 {
        m.onLogTruncated(path, last)
    }
}

func (m *LogRotationMonitor) checkDeletedRotations(currentFiles map[string]*LogFileInfo) {
    for path, last := range m.fileState {
        if _, exists := currentFiles[path]; !exists {
            // File deleted (old rotation removed)
            if m.isRotatedFile(last.Name) {
                m.onLogDeleted(path, last)
            }
        }
    }
}

func (m *LogRotationMonitor) shouldWatchFile(name string) bool {
    // Check patterns
    for _, pattern := range m.config.FilePatterns {
        matched, _ := filepath.Match(pattern, name)
        if matched {
            return true
        }
    }

    // Also watch rotated files
    if m.isRotatedFile(name) {
        return true
    }

    return false
}

func (m *LogRotationMonitor) isRotatedFile(name string) bool {
    // Check for rotation patterns: name.1, name.1.gz, name.20240101, etc.
    // Pattern: base.ext.N or base.ext.N.gz or base.YYYYMMDD

    // Remove .gz extension
    baseName := strings.TrimSuffix(name, ".gz")

    // Check for numeric suffix
    if idx := strings.LastIndex(baseName, "."); idx != -1 {
        suffix := baseName[idx+1:]
        if _, err := strconv.Atoi(suffix); err == nil {
            return true
        }
    }

    // Check for date pattern YYYYMMDD
    if len(baseName) >= 8 {
        datePart := baseName[len(baseName)-8:]
        if _, err := strconv.Atoi(datePart); err == nil {
            // Could be a date rotation
            return true
        }
    }

    return false
}

func (m *LogRotationMonitor) onLogRotated(path string, info *LogFileInfo) {
    if !m.config.SoundOnRotate {
        return
    }

    key := fmt.Sprintf("rotate:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["rotate"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LogRotationMonitor) onLogCompressed(path string, info *LogFileInfo) {
    sound := m.config.Sounds["compress"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *LogRotationMonitor) onLogDeleted(path string, last *LogFileInfo) {
    if !m.config.SoundOnDelete {
        return
    }

    key := fmt.Sprintf("delete:%s", last.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["delete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LogRotationMonitor) onLogTruncated(path string, last *LogFileInfo) {
    sound := m.config.Sounds["truncate"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *LogRotationMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /var/log | Directory | Free | Log files |

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
| macOS | Supported | Uses os.ReadDir |
| Linux | Supported | Uses os.ReadDir |
| Windows | Not Supported | ccbell only supports macOS/Linux |
