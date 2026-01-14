# Feature: Sound Event File Change Monitor

Play sounds for important file modifications and access events.

## Summary

Monitor file system changes for watched files and directories, playing sounds for file modification events.

## Motivation

- File change awareness
- Configuration drift detection
- Security monitoring
- Development feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### File Change Events

| Event | Description | Example |
|-------|-------------|---------|
| File Modified | Content changed | config.yaml |
| File Created | New file | new.log |
| File Deleted | File removed | temp.tmp |
| File Accessed | File read | secret.txt |

### Configuration

```go
type FileChangeMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchPaths    []string          `json:"watch_paths"` // "/etc", "/home/user"
    IgnorePaths   []string          `json:"ignore_paths"]
    FilePatterns  []string          `json:"file_patterns"` // "*.conf", "*.yaml"
    SoundOnModify bool              `json:"sound_on_modify"]
    SoundOnCreate bool              `json:"sound_on_create"]
    SoundOnDelete bool              `json:"sound_on_delete"]
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 5 default
}

type FileChangeEvent struct {
    Path      string
    FileName  string
    ChangeType string // "modify", "create", "delete", "access"
    Size      int64
    Modified  time.Time
}
```

### Commands

```bash
/ccbell:file status                   # Show file watch status
/ccbell:file add /etc/nginx           # Add path to watch
/ccbell:file remove /etc/nginx
/ccbell:file sound modify <sound>
/ccbell:file sound create <sound>
/ccbell:file test                     # Test file sounds
```

### Output

```
$ ccbell:file status

=== Sound Event File Change Monitor ===

Status: Enabled
Modify Sounds: Yes
Create Sounds: Yes

Watched Paths: 2

[1] /etc/nginx
    Files: 15
    Last Change: 5 min ago
    Sound: bundled:stop

[2] /home/user/.ssh
    Files: 5
    Last Change: 1 hour ago
    Sound: bundled:ssh-change

Recent Events:
  [1] /etc/nginx/nginx.conf: Modified (5 min ago)
       Size: 4.2 KB
  [2] /home/user/.ssh/known_hosts: Modified (1 hour ago)
       Size: 1.2 KB
  [3] /etc/nginx/sites-enabled: Created (2 hours ago)
       New symlink

File Statistics (Last Hour):
  Modifications: 10
  Creations: 2
  Deletions: 1

Sound Settings:
  Modify: bundled:file-modify
  Create: bundled:stop
  Delete: bundled:file-delete

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

File change monitoring doesn't play sounds directly:
- Monitoring feature using filesystem tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Change Monitor

```go
type FileChangeMonitor struct {
    config         *FileChangeMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    fileState      map[string]*FileInfo
    lastEventTime  map[string]time.Time
}

type FileInfo struct {
    Path     string
    Name     string
    Size     int64
    Modified time.Time
    Mode     os.FileMode
}

func (m *FileChangeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fileState = make(map[string]*FileInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FileChangeMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotFileState()

    for {
        select {
        case <-ticker.C:
            m.checkFileChanges()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileChangeMonitor) snapshotFileState() {
    for _, path := range m.config.WatchPaths {
        m.scanPath(path, false)
    }
}

func (m *FileChangeMonitor) scanPath(path string, reportChanges bool) {
    entries, err := os.ReadDir(path)
    if err != nil {
        return
    }

    currentFiles := make(map[string]*FileInfo)

    for _, entry := range entries {
        if m.shouldIgnore(entry.Name()) {
            continue
        }

        fullPath := filepath.Join(path, entry.Name())

        if entry.IsDir() {
            // Recursively scan subdirectories
            m.scanSubDir(fullPath, currentFiles, reportChanges)
            continue
        }

        info, err := entry.Info()
        if err != nil {
            continue
        }

        fileInfo := &FileInfo{
            Path:     fullPath,
            Name:     entry.Name(),
            Size:     info.Size(),
            Modified: info.ModTime(),
            Mode:     info.Mode(),
        }

        currentFiles[fullPath] = fileInfo

        if reportChanges {
            m.checkFile(fullPath, fileInfo)
        }
    }

    if reportChanges {
        // Check for deleted files
        m.checkDeletedFiles(currentFiles)
    }

    m.fileState = currentFiles
}

func (m *FileChangeMonitor) scanSubDir(path string, currentFiles map[string]*FileInfo, reportChanges bool) {
    entries, err := os.ReadDir(path)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if m.shouldIgnore(entry.Name()) {
            continue
        }

        fullPath := filepath.Join(path, entry.Name())

        if entry.IsDir() {
            m.scanSubDir(fullPath, currentFiles, reportChanges)
            continue
        }

        info, err := entry.Info()
        if err != nil {
            continue
        }

        fileInfo := &FileInfo{
            Path:     fullPath,
            Name:     entry.Name(),
            Size:     info.Size(),
            Modified: info.ModTime(),
            Mode:     info.Mode(),
        }

        currentFiles[fullPath] = fileInfo

        if reportChanges {
            m.checkFile(fullPath, fileInfo)
        }
    }
}

func (m *FileChangeMonitor) checkFileChanges() {
    for _, path := range m.config.WatchPaths {
        m.scanPath(path, true)
    }
}

func (m *FileChangeMonitor) checkFile(path string, current *FileInfo) {
    last, exists := m.fileState[path]

    if !exists {
        // File created
        m.onFileCreated(current)
    } else if current.Modified != last.Modified {
        // File modified
        m.onFileModified(current, last)
    } else if current.Size != last.Size {
        // Size changed (but mod time might be same)
        m.onFileModified(current, last)
    }
}

func (m *FileChangeMonitor) checkDeletedFiles(currentFiles map[string]*FileInfo) {
    for path, last := range m.fileState {
        if _, exists := currentFiles[path]; !exists {
            // File deleted
            m.onFileDeleted(last)
        }
    }
}

func (m *FileChangeMonitor) shouldIgnore(name string) bool {
    for _, pattern := range m.config.IgnorePaths {
        if name == pattern {
            return true
        }
    }

    // Check if it matches file patterns
    for _, pattern := range m.config.FilePatterns {
        matched, _ := filepath.Match(pattern, name)
        if matched {
            return false
        }
    }

    return false
}

func (m *FileChangeMonitor) onFileModified(current *FileInfo, last *FileInfo) {
    if !m.config.SoundOnModify {
        return
    }

    // Check for significant changes
    if current.Size-last.Size < 100 {
        return
    }

    key := fmt.Sprintf("modify:%s", current.Path)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["modify"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileChangeMonitor) onFileCreated(current *FileInfo) {
    if !m.config.SoundOnCreate {
        return
    }

    key := fmt.Sprintf("create:%s", current.Path)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["create"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileChangeMonitor) onFileDeleted(last *FileInfo) {
    if !m.config.SoundOnDelete {
        return
    }

    key := fmt.Sprintf("delete:%s", last.Path)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["delete"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileChangeMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc | File System | Free | File info access |

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
