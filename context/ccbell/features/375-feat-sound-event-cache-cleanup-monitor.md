# Feature: Sound Event Cache Cleanup Monitor

Play sounds for cache cleanup events and disk space reclamation.

## Summary

Monitor system cache cleanup operations, memory cache clearing, and disk space reclamation events, playing sounds for cache events.

## Motivation

- Cache awareness
- Cleanup completion feedback
- Memory optimization alerts
- Disk space recovery
- System performance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Cache Cleanup Events

| Event | Description | Example |
|-------|-------------|---------|
| Cache Cleared | System cache cleared | Page cache freed |
| Memory Cache | Memory cache dropped | echo 3 > /proc/sys/vm/drop_caches |
| Package Cache | Package cache cleaned | apt clean |
| Thumbnail Cache | Thumbnails cleared | ~/.cache/thumbnails |
| Browser Cache | Browser cache cleared | Chrome cache |

### Configuration

```go
type CacheCleanupMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "/var/cache", "~/.cache", "*"
    WatchProcesses    []string          `json:"watch_processes"` // "apt", "dnf", "chrome"
    SoundOnClean      bool              `json:"sound_on_clean"`
    SoundOnComplete   bool              `json:"sound_on_complete"]
    SoundOnSpace      bool              `json:"sound_on_space"]
    MinCleanedMB      int               `json:"min_cleaned_mb"` // 100 default
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}

type CacheCleanupEvent struct {
    Process    string
    Path       string
    FreedMB    int
    BeforeSize int64
    AfterSize  int64
    EventType  string // "cache_cleaned", "memory_cleared", "package_clean", "thumbnail_clean"
}
```

### Commands

```bash
/ccbell:cache status                  # Show cache status
/ccbell:cache add /var/cache          # Add cache path
/ccbell:cache remove /var/cache
/ccbell:cache sound clean <sound>
/ccbell:cache sound complete <sound>
/ccbell:cache test                    # Test cache sounds
```

### Output

```
$ ccbell:cache status

=== Sound Event Cache Cleanup Monitor ===

Status: Enabled
Clean Sounds: Yes
Complete Sounds: Yes
Minimum Clean: 100 MB

Watched Paths: 3
Watched Processes: 2

Cache Status:

[1] /var/cache/apt
    Size: 2.5 GB
    Last Clean: 2 days ago
    Sound: bundled:cache-apt

[2] ~/.cache/thumbnails
    Size: 450 MB
    Last Clean: 1 week ago
    Sound: bundled:cache-thumbnails

[3] ~/.cache/google-chrome
    Size: 1.2 GB
    Last Clean: 3 days ago
    Sound: bundled:cache-chrome

Recent Events:
  [1] apt: Cache Cleaned (5 min ago)
       Freed: 1.2 GB
       Before: 3.7 GB -> After: 2.5 GB
  [2] systemd: Memory Cache Cleared (1 hour ago)
       Freed: ~500 MB
  [3] bleachbit: Cleanup Completed (2 hours ago)
       Total Freed: 2.5 GB

Cache Statistics:
  Total Monitored: 3 paths
  Freed Today: 3.7 GB
  Cleanup Events: 5

Sound Settings:
  Clean: bundled:cache-clean
  Complete: bundled:cache-complete
  Space: bundled:cache-space

[Configure] [Add Path] [Clean All]
```

---

## Audio Player Compatibility

Cache monitoring doesn't play sounds directly:
- Monitoring feature using du/df commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cache Cleanup Monitor

```go
type CacheCleanupMonitor struct {
    config          *CacheCleanupMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    cacheState      map[string]*CacheInfo
    lastEventTime   map[string]time.Time
}

type CacheInfo struct {
    Path       string
    Size       int64 // bytes
    LastClean  time.Time
    Process    string
}

func (m *CacheCleanupMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cacheState = make(map[string]*CacheInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CacheCleanupMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCacheState()

    for {
        select {
        case <-ticker.C:
            m.checkCacheState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CacheCleanupMonitor) snapshotCacheState() {
    for _, path := range m.config.WatchPaths {
        expandedPath := m.expandPath(path)
        info := m.getCacheSize(expandedPath)
        if info != nil {
            info.Path = path
            m.cacheState[path] = info
        }
    }
}

func (m *CacheCleanupMonitor) checkCacheState() {
    for _, path := range m.config.WatchPaths {
        expandedPath := m.expandPath(path)
        info := m.getCacheSize(expandedPath)
        if info == nil {
            continue
        }

        info.Path = path
        lastInfo := m.cacheState[path]

        if lastInfo == nil {
            m.cacheState[path] = info
            continue
        }

        // Check if cache was cleaned
        if info.Size < lastInfo.Size {
            freed := (lastInfo.Size - info.Size) / (1024 * 1024)
            if freed >= int64(m.config.MinCleanedMB) {
                m.onCacheCleaned(path, info, lastInfo, int(freed))
            }
        }

        m.cacheState[path] = info
    }

    // Check for cleanup processes
    m.checkCleanupProcesses()
}

func (m *CacheCleanupMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *CacheCleanupMonitor) getCacheSize(path string) *CacheInfo {
    cmd := exec.Command("du", "-sm", path)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    parts := strings.Fields(string(output))
    size, _ := strconv.ParseInt(parts[0], 10, 64)

    return &CacheInfo{
        Size:      size * 1024 * 1024, // Convert to bytes
        LastClean: time.Now(),
    }
}

func (m *CacheCleanupMonitor) checkCleanupProcesses() {
    for _, proc := range m.config.WatchProcesses {
        cmd := exec.Command("pgrep", "-x", proc)
        _, err := cmd.Output()
        if err == nil {
            // Process is running
            m.onCleanupStarted(proc)
        }
    }
}

func (m *CacheCleanupMonitor) onCacheCleaned(path string, newInfo *CacheInfo, lastInfo *CacheInfo, freedMB int) {
    if !m.config.SoundOnClean {
        return
    }

    key := fmt.Sprintf("clean:%s", path)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["clean"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }

    // Also trigger complete sound
    if !m.config.SoundOnComplete {
        return
    }

    key = fmt.Sprintf("complete:%s", path)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *CacheCleanupMonitor) onMemoryCacheCleared() {
    if !m.config.SoundOnClean {
        return
    }

    key := "memory_cache"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["memory_clean"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CacheCleanupMonitor) onCleanupStarted(process string) {
    // Optional: sound when cleanup process starts
}

func (m *CacheCleanupMonitor) onSpaceReclaimed(path string, freedMB int) {
    if !m.config.SoundOnSpace {
        return
    }

    key := fmt.Sprintf("space:%s:%d", path, freedMB)
    if m.shouldAlert(key, 2*time.Hour) {
        sound := m.config.Sounds["space"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *CacheCleanupMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| du | System Tool | Free | Disk usage |
| pgrep | System Tool | Free | Process listing |

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
| macOS | Supported | Uses du, pgrep |
| Linux | Supported | Uses du, pgrep |
