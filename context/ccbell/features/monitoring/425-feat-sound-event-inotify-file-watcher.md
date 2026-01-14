# Feature: Sound Event Inotify File Watcher

Play sounds for file system events using inotify on Linux for real-time file monitoring.

## Summary

Use Linux inotify subsystem for efficient real-time file and directory monitoring, playing sounds for file system events.

## Motivation

- Real-time file monitoring
- Efficient event detection
- Developer workflow feedback
- Download completion detection
- Log file change alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Inotify File Events

| Event | Description | Example |
|-------|-------------|---------|
| File Created | New file created | touched new.txt |
| File Modified | Content changed | saved file |
| File Deleted | File removed | rm file |
| File Accessed | File read | cat file |
| File Moved | Renamed/moved | mv old new |
| Directory Created | New folder | mkdir dir |

### Configuration

```go
type InotifyFileWatcherConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "/home/user/Downloads"
    WatchEvents       []string          `json:"watch_events"` // "create", "modify", "delete", "moved_to"
    ExcludePatterns   []string          `json:"exclude_patterns"` // "*.tmp", ".*"
    Recursive         bool              `json:"recursive"` // true default
    SoundOnCreate     bool              `json:"sound_on_create"`
    SoundOnModify     bool              `json:"sound_on_modify"`
    SoundOnDelete     bool              `json:"sound_on_delete"`
    Sounds            map[string]string `json:"sounds"`
    Cooldown          int               `json:"cooldown_ms"` // 500 default
}
```

### Commands

```bash
/ccbell:inotify status               # Show inotify status
/ccbell:inotify add ~/Downloads      # Add path to watch
/ccbell:inotify remove ~/Downloads
/ccbell:inotify events create,modify # Set events to watch
/ccbell:inotify sound create <sound>
/ccbell:inotify test                 # Test inotify sounds
```

### Output

```
$ ccbell:inotify status

=== Sound Event Inotify File Watcher ===

Status: Enabled
Recursive: Yes
Watch Events: create, modify, delete

Watched Paths:

[1] ~/Downloads
    Watches: 156
    Events/min: 12
    Last Event: CREATE backup.zip
    Sound: bundled:inotify-download

[2] ~/Documents
    Watches: 892
    Events/min: 5
    Last Event: MODIFY notes.txt
    Sound: bundled:inotify-doc

[3] /var/log
    Watches: 45
    Events/min: 25
    Last Event: MODIFY syslog
    Sound: bundled:inotify-log

Recent Events:

[1] ~/Downloads: CREATE (2 sec ago)
       backup.zip (2.5 MB)
       Sound: bundled:inotify-create

[2] ~/Documents: MODIFY (5 min ago)
       notes.txt
       Sound: bundled:inotify-modify

[3] /var/log: DELETE (1 hour ago)
       old.log.1
       Sound: bundled:inotify-delete

Inotify Statistics:
  Total Watches: 1093
  Events Today: 450
  Creates: 120
  Modifies: 280
  Deletes: 50

Sound Settings:
  Create: bundled:inotify-create
  Modify: bundled:inotify-modify
  Delete: bundled:inotify-delete
  Move: bundled:inotify-move

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Inotify monitoring doesn't play sounds directly:
- Monitoring feature using inotifywait
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Inotify File Watcher

```go
type InotifyFileWatcher struct {
    config          *InotifyFileWatcherConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    watchPaths      map[string]*WatchPathInfo
    lastEventTime   map[string]time.Time
}

type WatchPathInfo struct {
    Path        string
    Watches     int
    EventCount  int
    LastEvent   time.Time
    LastEventType string
}

func (m *InotifyFileWatcher) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.watchPaths = make(map[string]*WatchPathInfo)
    m.lastEventTime = make(map[string]time.Time)

    // Build event flags
    eventFlags := m.buildEventFlags()

    for _, path := range m.config.WatchPaths {
        expandedPath := m.expandPath(path)
        info := &WatchPathInfo{
            Path: expandedPath,
        }
        m.watchPaths[expandedPath] = info
        go m.watchWithInotify(expandedPath, eventFlags)
    }

    <-m.stopCh
}

func (m *InotifyFileWatcher) buildEventFlags() string {
    var events []string

    for _, event := range m.config.WatchEvents {
        switch strings.ToLower(event) {
        case "create", "created":
            events = append(events, "create")
        case "modify", "modified":
            events = append(events, "modify")
        case "delete", "deleted":
            events = append(events, "delete")
        case "moved_to", "move":
            events = append(events, "moved_to")
        case "access", "accessed":
            events = append(events, "access")
        case "close_write", "close":
            events = append(events, "close_write")
        }
    }

    if len(events) == 0 {
        return "create,modify,delete,moved_to"
    }

    return strings.Join(events, ",")
}

func (m *InotifyFileWatcher) watchWithInotify(path string, events string) {
    args := []string{"-m", "-r"}

    // Add event filters
    for _, event := range strings.Split(events, ",") {
        args = append(args, "-e", event)
    }

    // Add path
    args = append(args, path)

    cmd := exec.Command("inotifywait", args...)
    output, err := cmd.StdoutPipe()
    if err != nil {
        return
    }

    scanner := bufio.NewScanner(output)
    go func() {
        for scanner.Scan() {
            line := scanner.Text()
            m.handleInotifyEvent(path, line)
        }
    }()

    cmd.Start()
    cmd.Wait()
}

func (m *InotifyFileWatcher) handleInotifyEvent(watchPath, eventLine string) {
    // Parse event line
    // Format: /path/to/file EVENT
    parts := strings.SplitN(eventLine, " ", 2)
    if len(parts) < 2 {
        return
    }

    filePath := strings.TrimPrefix(parts[0], watchPath)
    eventType := parts[1]

    // Get filename
    filename := filepath.Base(filePath)
    if filename == "" {
        filename = filepath.Base(watchPath)
    }

    // Check exclude patterns
    if m.shouldExclude(filename) {
        return
    }

    // Categorize event
    eventCategory := m.categorizeEvent(eventType)

    // Apply cooldown
    key := fmt.Sprintf("%s:%s", watchPath, eventCategory)
    if !m.shouldAlert(key, time.Duration(m.config.Cooldown)*time.Millisecond) {
        return
    }

    // Play sound based on event type
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
    if info, exists := m.watchPaths[watchPath]; exists {
        info.EventCount++
        info.LastEvent = time.Now()
        info.LastEventType = eventCategory
    }
}

func (m *InotifyFileWatcher) categorizeEvent(eventType string) string {
    eventType = strings.ToLower(eventType)

    if strings.Contains(eventType, "create") || strings.Contains(eventType, "moved_to") {
        return "create"
    }
    if strings.Contains(eventType, "modify") || strings.Contains(eventType, "close_write") {
        return "modify"
    }
    if strings.Contains(eventType, "delete") || strings.Contains(eventType, "moved_from") {
        return "delete"
    }
    if strings.Contains(eventType, "access") {
        return "access"
    }

    return "other"
}

func (m *InotifyFileWatcher) shouldExclude(filename string) bool {
    for _, pattern := range m.config.ExcludePatterns {
        matched, _ := filepath.Match(pattern, filename)
        if matched {
            return true
        }
    }

    // Also check for hidden files if pattern includes them
    if strings.HasPrefix(filename, ".") {
        for _, pattern := range m.config.ExcludePatterns {
            if strings.Contains(pattern, ".*") {
                matched, _ := filepath.Match(pattern, filename)
                if matched {
                    return true
                }
            }
        }
    }

    return false
}

func (m *InotifyFileWatcher) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *InotifyFileWatcher) onFileCreated(filename, path string) {
    sound := m.config.Sounds["create"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *InotifyFileWatcher) onFileModified(filename, path string) {
    sound := m.config.Sounds["modify"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *InotifyFileWatcher) onFileDeleted(filename string) {
    sound := m.config.Sounds["delete"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *InotifyFileWatcher) shouldAlert(key string, interval time.Duration) bool {
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
| inotifywait | System Tool | Free | Inotify tools (Linux) |
| inotifywatch | System Tool | Free | Inotify statistics |

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
| macOS | Not Supported | No inotify (use fswatch) |
| Linux | Supported | Uses inotifywait |
