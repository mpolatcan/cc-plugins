# Feature: Sound Event File Change Monitor

Play sounds for file modifications, deletions, and new file creation in watched directories.

## Summary

Monitor directories for file changes including modifications, deletions, and new files, playing sounds for file events.

## Motivation

- File change awareness
- Development feedback
- Download completion detection
- Document editing alerts
- Directory monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### File Change Events

| Event | Description | Example |
|-------|-------------|---------|
| File Created | New file detected | new.txt |
| File Modified | Content changed | existing.txt |
| File Deleted | File removed | deleted.log |
| File Moved | File renamed/moved | renamed.pdf |
| Directory Created | New folder | new_dir/ |
| Bulk Change | Multiple changes | > 10 files |

### Configuration

```go
type FileChangeMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "/Users/*/Downloads", "/var/log"
    IncludePatterns   []string          `json:"include_patterns"` // "*.log", "*.txt"
    ExcludePatterns   []string          `json:"exclude_patterns"` // "*.tmp", "*.bak"
    Recursive         bool              `json:"recursive"` // true default
    SoundOnCreate     bool              `json:"sound_on_create"`
    SoundOnModify     bool              `json:"sound_on_modify"`
    SoundOnDelete     bool              `json:"sound_on_delete"`
    Sounds            map[string]string `json:"sounds"`
    Cooldown          int               `json:"cooldown_sec"` // 5 default
}
```

### Commands

```bash
/ccbell:file status                  # Show file monitor status
/ccbell:file add ~/Downloads         # Add path to watch
/ccbell:file remove ~/Downloads
/ccbell:file sound create <sound>
/ccbell:file sound modify <sound>
/ccbell:file test                    # Test file sounds
```

### Output

```
$ ccbell:file status

=== Sound Event File Change Monitor ===

Status: Enabled
Create Sounds: Yes
Modify Sounds: Yes
Delete Sounds: Yes

Watched Paths: 3
Recursive: Yes

Watched Paths:

[1] ~/Downloads
    Status: ACTIVE
    Files Today: 15
    Last Change: 5 min ago
    Sound: bundled:file-download

[2] ~/Documents/Projects
    Status: ACTIVE
    Files Today: 8
    Last Change: 1 hour ago
    Sound: bundled:file-project

[3] /var/log
    Status: ACTIVE
    Files Today: 42
    Last Change: 2 min ago
    Sound: bundled:file-log

Recent File Events:

[1] ~/Downloads/report.pdf
    Event: CREATED
    Size: 2.5 MB
    5 min ago
    Sound: bundled:file-download

[2] ~/Documents/Projects/src/main.go
    Event: MODIFIED
    Size: 45 KB
    1 hour ago
    Sound: bundled:file-project

[3] /var/log/error.log
    Event: MODIFIED
    Size: 128 KB
    2 min ago
    Sound: bundled:file-log

File Statistics:
  Total Changes Today: 65
  Created: 20
  Modified: 40
  Deleted: 5

Sound Settings:
  Create: bundled:file-create
  Modify: bundled:file-modify
  Delete: bundled:file-delete

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

File change monitoring doesn't play sounds directly:
- Monitoring feature using fswatch/inotifywait
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Change Monitor

```go
type FileChangeMonitor struct {
    config          *FileChangeMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    watchedPaths    map[string]*WatchInfo
    lastEventTime   map[string]time.Time
}

type WatchInfo struct {
    Path       string
    Status     string
    EventCount int
    LastEvent  time.Time
}

func (m *FileChangeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.watchedPaths = make(map[string]*WatchInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FileChangeMonitor) monitor() {
    for _, path := range m.config.WatchPaths {
        expandedPath := m.expandPath(path)
        info := &WatchInfo{
            Path:   expandedPath,
            Status: "active",
        }
        m.watchedPaths[expandedPath] = info
        go m.watchPath(expandedPath)
    }

    <-m.stopCh
}

func (m *FileChangeMonitor) watchPath(path string) {
    // Try fswatch first (macOS)
    cmd := exec.Command("fswatch", "-r", "-e", ".*", "-i", "", path)
    if runtime.GOOS == "linux" {
        // Use inotifywait on Linux
        cmd = exec.Command("inotifywait", "-m", "-r", "-e", "create,modify,delete,moved_to", path)
    }

    output, err := cmd.StdoutPipe()
    if err != nil {
        return
    }

    scanner := bufio.NewScanner(output)
    go func() {
        for scanner.Scan() {
            line := scanner.Text()
            m.handleFileEvent(path, line)
        }
    }()

    cmd.Start()
    cmd.Wait()
}

func (m *FileChangeMonitor) handleFileEvent(watchPath, eventLine string) {
    // Parse event line
    // fswatch format: /path/to/file event_type
    // inotifywait format: /path/to/file EVENT

    parts := strings.Fields(eventLine)
    if len(parts) < 1 {
        return
    }

    filePath := parts[0]
    eventType := ""
    if len(parts) >= 2 {
        eventType = parts[1]
    }

    // Get just the filename
    filename := filepath.Base(filePath)

    // Check exclude patterns
    if m.shouldExclude(filename) {
        return
    }

    // Determine event category
    eventCategory := m.categorizeEvent(eventType)

    // Apply cooldown
    key := fmt.Sprintf("%s:%s", watchPath, eventCategory)
    if !m.shouldAlert(key, time.Duration(m.config.Cooldown)*time.Second) {
        return
    }

    // Play appropriate sound
    switch eventCategory {
    case "create":
        if m.config.SoundOnCreate {
            m.onFileCreated(filename, filePath)
        }
    case "modify":
        if m.config.SoundOnModify {
            m.onFileModified(filename, filePath)
        }
    case "delete":
        if m.config.SoundOnDelete {
            m.onFileDeleted(filename)
        }
    }

    // Update stats
    if info, exists := m.watchedPaths[watchPath]; exists {
        info.EventCount++
        info.LastEvent = time.Now()
    }
}

func (m *FileChangeMonitor) categorizeEvent(eventType string) string {
    eventType = strings.ToLower(eventType)

    createEvents := []string{"created", "createdirectory", "removed", "renamed"}
    modifyEvents := []string{"updated", "modified", "contents_modified"}
    deleteEvents := []string{"removed", "deleted", "destroyed"}

    for _, e := range createEvents {
        if strings.Contains(eventType, e) {
            return "create"
        }
    }

    for _, e := range modifyEvents {
        if strings.Contains(eventType, e) {
            return "modify"
        }
    }

    for _, e := range deleteEvents {
        if strings.Contains(eventType, e) {
            return "delete"
        }
    }

    return "modify" // default
}

func (m *FileChangeMonitor) shouldExclude(filename string) bool {
    for _, pattern := range m.config.ExcludePatterns {
        matched, _ := filepath.Match(pattern, filename)
        if matched {
            return true
        }
    }
    return false
}

func (m *FileChangeMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *FileChangeMonitor) onFileCreated(filename, path string) {
    sound := m.config.Sounds["create"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *FileChangeMonitor) onFileModified(filename, path string) {
    sound := m.config.Sounds["modify"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *FileChangeMonitor) onFileDeleted(filename string) {
    sound := m.config.Sounds["delete"]
    if sound != "" {
        m.player.Play(sound, 0.4)
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
| fswatch | System Tool | Free | File watching (macOS) |
| inotifywait | System Tool | Free | File watching (Linux) |

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
| macOS | Supported | Uses fswatch |
| Linux | Supported | Uses inotifywait |
