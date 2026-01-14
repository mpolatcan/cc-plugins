# Feature: Sound Event File Change Monitor

Play sounds for file modifications, deletions, and new file creation.

## Summary

Monitor directories and files for changes using inotify/fsevents for real-time detection of modifications, deletions, and new files, playing sounds for change events.

## Motivation

- Change detection
- File integrity
- Intrusion detection
- Modification alerts
- Audit logging

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
| File Modified | Content changed | modified |
| File Created | New file | created |
| File Deleted | File removed | deleted |
| File Moved | File renamed | moved |
| Attribute Changed | Metadata changed | attr changed |
| Close Write | Write completed | closed |

### Configuration

```go
type FileChangeMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchPaths       []string          `json:"watch_paths"` // paths to monitor
    ExcludePatterns  []string          `json:"exclude_patterns"` // "*.log", "*.tmp"
    SoundOnModify    bool              `json:"sound_on_modify"`
    SoundOnCreate    bool              `json:"sound_on_create"`
    SoundOnDelete    bool              `json:"sound_on_delete"`
    SoundOnMove      bool              `json:"sound_on_move"`
    Sounds           map[string]string `json:"sounds"`
}
```

### Commands

```bash
/ccbell:change status               # Show change status
/ccbell:change add /etc             # Add path to watch
/ccbell:change sound modify <sound>
/ccbell:change test                 # Test change sounds
```

### Output

```
$ ccbell:change status

=== Sound Event File Change Monitor ===

Status: Enabled
Watch Paths: /etc, /var/www

Change Events (Last 1 hour):

[1] /etc/nginx/nginx.conf
    Event: MODIFIED
    Time: 5 min ago
    User: root
    Sound: bundled:change-modify

[2] /var/www/html/index.html
    Event: CREATED
    Time: 30 min ago
    User: www-data
    Sound: bundled:change-create

[3] /var/log/old.log
    Event: DELETED
    Time: 1 hour ago
    User: admin
    Sound: bundled:change-delete

[4] /etc/config.yml
    Event: MOVED
    Time: 2 hours ago
    User: root
    From: /etc/config.yml.bak
    Sound: bundled:change-move

Recent Events:

[1] /etc/nginx/nginx.conf: Modified (5 min ago)
       Content changed by root
       Sound: bundled:change-modify
  [2] /var/www/html/index.html: Created (30 min ago)
       New file created by www-data
       Sound: bundled:change-create
  [3] /var/log/old.log: Deleted (1 hour ago)
       File deleted by admin
       Sound: bundled:change-delete

Change Statistics:
  Total Events: 12
  Modified: 8
  Created: 3
  Deleted: 1
  Moved: 0

Sound Settings:
  Modify: bundled:change-modify
  Create: bundled:change-create
  Delete: bundled:change-delete
  Move: bundled:change-move

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

File change monitoring doesn't play sounds directly:
- Monitoring feature using inotifywait, fswatch
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### File Change Monitor

```go
type FileChangeMonitor struct {
    config        *FileChangeMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    changeState   map[string]*ChangeInfo
    lastEventTime map[string]time.Time
}

type ChangeInfo struct {
    Path      string
    Event     string // "modify", "create", "delete", "move"
    User      string
    Time      time.Time
    From      string // for move events
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| inotifywait | System Tool | Free | Linux file events |
| fswatch | System Tool | Free | macOS file events |

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
