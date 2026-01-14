# Feature: Sound Event File Watcher

Play sounds when files or directories change.

## Summary

Play different sounds when watched files or directories are created, modified, or deleted.

## Motivation

- File change alerts
- Build notifications
- Download complete sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### File Watch Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Created | File/dir created | New file appeared |
| Modified | File modified | Content changed |
| Deleted | File/dir deleted | File removed |
| Renamed | File renamed | File moved |
| Attribute | Permissions changed | chmod executed |

### Configuration

```go
type FileWatcherConfig struct {
    Enabled     bool              `json:"enabled"`
    Watches     map[string]*FileWatch `json:"watches"`
}

type FileWatch struct {
    ID          string   `json:"id"`
    Path        string   `json:"path"` // File or directory
    Recursive   bool     `json:"recursive"` // Watch subdirectories
    Events      []string `json:"events"` // ["create", "modify", "delete", "rename"]
    Pattern     string   `json:"pattern,omitempty"` // File glob pattern
    Exclude     string   `json:"exclude,omitempty"` // Exclude pattern
    Sound       string   `json:"sound"`
    Volume      float64  `json:"volume,omitempty"`
    DebounceMs  int      `json:"debounce_ms"` // 100 default
    Enabled     bool     `json:"enabled"`
}
```

### Commands

```bash
/ccbell:watch list                  # List file watches
/ccbell:watch add /path/to/dir --events create,modify
/ccbell:watch add "~/Downloads" --pattern "*.zip" --sound bundled:stop
/ccbell:watch delete <id>           # Remove watch
/ccbell:watch enable <id>           # Enable watch
/ccbell:watch disable <id>          # Disable watch
/ccbell:watch test <id>             # Test watch
```

### Output

```
$ ccbell:watch list

=== Sound Event File Watcher ===

Status: Enabled

Watches: 3

[1] Downloads
    Path: /Users/user/Downloads
    Events: create
    Pattern: *.{zip,dmg,pkg}
    Status: Active
    Triggers: 12 today
    [Edit] [Disable] [Delete]

[2] Project Build
    Path: /Users/project/build
    Events: modify
    Pattern: *.out
    Debounce: 500ms
    Status: Active
    Triggers: 5 today
    [Edit] [Disable] [Delete]

[3] Logs
    Path: /Users/project/logs
    Events: create,modify
    Pattern: *.log
    Status: Active
    Triggers: 156 today
    [Edit] [Disable] [Delete]

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

File watching doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### File Watcher

```go
type FileWatcherManager struct {
    config   *FileWatcherConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    watches  map[string]*fsnotify.Watcher
    mutex    sync.Mutex
}

func (m *FileWatcherManager) Start() error {
    m.running = true
    m.stopCh = make(chan struct{})
    m.watches = make(map[string]*fsnotify.Watcher)

    for _, watch := range m.config.Watches {
        if !watch.Enabled {
            continue
        }

        if err := m.addWatch(watch); err != nil {
            log.Debug("Failed to add watch %s: %v", watch.Path, err)
        }
    }

    <-m.stopCh
    return nil
}

func (m *FileWatcherManager) addWatch(watch *FileWatch) error {
    watcher, err := fsnotify.NewWatcher()
    if err != nil {
        return err
    }

    go func() {
        for {
            select {
            case event, ok := <-watcher.Events:
                if !ok {
                    return
                }
                if m.shouldTrigger(watch, event) {
                    m.playFileEvent(watch, event)
                }
            case err, ok := <-watcher.Errors:
                if !ok {
                    return
                }
                log.Debug("Watch error: %v", err)
            case <-m.stopCh:
                watcher.Close()
                return
            }
        }
    }()

    if watch.Recursive {
        if err := m.addRecursive(watcher, watch.Path); err != nil {
            return err
        }
    } else {
        if err := watcher.Add(watch.Path); err != nil {
            return err
        }
    }

    m.watches[watch.ID] = watcher
    return nil
}

func (m *FileWatcherManager) shouldTrigger(watch *FileWatch, event fsnotify.Event) bool {
    // Check event type
    for _, e := range watch.Events {
        if (e == "create" && event.Has(fsnotify.Create)) ||
           (e == "modify" && event.Has(fsnotify.Write)) ||
           (e == "delete" && event.Has(fsnotify.Remove)) ||
           (e == "rename" && event.Has(fsnotify.Rename)) {
            // Check pattern
            if watch.Pattern != "" {
                if matched, _ := filepath.Match(watch.Pattern, filepath.Base(event.Name)); matched {
                    return true
                }
            }
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
| fsnotify | Go Module | Free | File system notifications |
| inotify | Kernel | Free | Linux native |
| FSEvents | API | Free | macOS native |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses FSEvents |
| Linux | ✅ Supported | Uses inotify |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
