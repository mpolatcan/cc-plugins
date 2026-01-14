# Feature: Sound Event Cache Monitor

Play sounds for cache eviction and cleanup events.

## Summary

Monitor cache eviction, cleanup operations, and memory pressure events, playing sounds for cache activity.

## Motivation

- Cache awareness
- Memory pressure alerts
- Cleanup feedback
- Performance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Cache Events

| Event | Description | Example |
|-------|-------------|---------|
| Cache Evicted | Item removed from cache | Key expired |
| Cache Cleaned | Bulk cleanup occurred | Redis FLUSHDB |
| Memory Pressure | Low memory condition | OOM warning |
| Cache Hit | High hit rate | 95% hit rate |

### Configuration

```go
type CacheMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    CacheType       string            `json:"cache_type"` // "redis", "memcached", "filesystem"
    WatchKeys       []string          `json:"watch_keys"`
    SoundOnEvict    bool              `json:"sound_on_evict"`
    SoundOnClean    bool              `json:"sound_on_clean"`
    SoundOnPressure bool              `json:"sound_on_pressure"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 30 default
}

type CacheEvent struct {
    CacheType   string
    Key         string
    EventType   string // "evict", "clean", "pressure"
    ItemsCount  int
    MemoryUsage int64
}
```

### Commands

```bash
/ccbell:cache status                  # Show cache status
/ccbell:cache type redis              # Set cache type
/ccbell:cache add mykey               # Add key to watch
/ccbell:cache sound evict <sound>
/ccbell:cache sound pressure <sound>
/ccbell:cache test                    # Test cache sounds
```

### Output

```
$ ccbell:cache status

=== Sound Event Cache Monitor ===

Status: Enabled
Type: redis
Evict Sounds: Yes
Pressure Sounds: Yes

[1] redis-server (localhost:6379)
    Keys: 1,234
    Memory: 256 MB / 512 MB
    Hit Rate: 95%
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] Cache Pressure (5 min ago)
       Memory at 90%
  [2] Cache Cleaned (1 hour ago)
       FLUSHDB executed
  [3] Cache Evicted (2 hours ago)
       50 keys expired

Cache Statistics:
  Evictions/min: 10
  Keys expire/sec: 5

Sound Settings:
  Evict: bundled:stop
  Clean: bundled:stop
  Pressure: bundled:cache-pressure

[Configure] [Set Type] [Test All]
```

---

## Audio Player Compatibility

Cache monitoring doesn't play sounds directly:
- Monitoring feature using cache tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cache Monitor

```go
type CacheMonitor struct {
    config           *CacheMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    cacheStats       map[string]interface{}
    lastEvictionCount int
    lastCleanTime    time.Time
}

func (m *CacheMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cacheStats = make(map[string]interface{})
    go m.monitor()
}

func (m *CacheMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCacheStats()

    for {
        select {
        case <-ticker.C:
            m.checkCacheStats()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CacheMonitor) snapshotCacheStats() {
    switch m.config.CacheType {
    case "redis":
        m.snapshotRedisStats()
    case "memcached":
        m.snapshotMemcachedStats()
    case "filesystem":
        m.snapshotFilesystemCache()
    default:
        m.snapshotRedisStats()
    }
}

func (m *CacheMonitor) checkCacheStats() {
    switch m.config.CacheType {
    case "redis":
        m.checkRedisStats()
    case "memcached":
        m.checkMemcachedStats()
    case "filesystem":
        m.checkFilesystemCache()
    default:
        m.checkRedisStats()
    }
}

func (m *CacheMonitor) snapshotRedisStats() {
    cmd := exec.Command("redis-cli", "INFO", "stats", "memory", "clients")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseRedisInfo(string(output))
}

func (m *CacheMonitor) checkRedisStats() {
    cmd := exec.Command("redis-cli", "INFO", "stats", "memory")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseRedisInfo(string(output))
}

func (m *CacheMonitor) parseRedisInfo(info string) {
    lines := strings.Split(info, "\n")
    stats := make(map[string]string)

    for _, line := range lines {
        if strings.Contains(line, ":") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) == 2 {
                stats[parts[0]] = strings.TrimSpace(parts[1])
            }
        }
    }

    // Check for eviction increase
    if evicted, ok := stats["expired_keys"]; ok {
        currentEvicted, _ := strconv.Atoi(evicted)
        if currentEvicted > m.lastEvictionCount {
            evictedCount := currentEvicted - m.lastEvictionCount
            if evictedCount > 10 {
                m.onCacheEvicted(evictedCount)
            }
        }
        m.lastEvictionCount = currentEvicted
    }

    // Check memory pressure
    if usedMemory, ok := stats["used_memory"]; ok {
        if maxMemory, ok := stats["maxmemory"]; ok {
            used, _ := strconv.ParseFloat(usedMemory, 64)
            max, _ := strconv.ParseFloat(maxMemory, 64)
            if max > 0 && used/max > 0.9 {
                m.onMemoryPressure()
            }
        }
    }

    m.cacheStats = stats
}

func (m *CacheMonitor) snapshotMemcachedStats() {
    cmd := exec.Command("memcached-tool", "localhost:11211", "stats")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseMemcachedStats(string(output))
}

func (m *CacheMonitor) checkMemcachedStats() {
    m.snapshotMemcachedStats()
}

func (m *CacheMonitor) parseMemcachedStats(stats string) {
    lines := strings.Split(stats, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "  #") {
            continue
        }
        if strings.Contains(line, "evictions") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                evicted, _ := strconv.Atoi(parts[2])
                if evicted > m.lastEvictionCount {
                    m.onCacheEvicted(evicted - m.lastEvictionCount)
                }
                m.lastEvictionCount = evicted
            }
        }
    }
}

func (m *CacheMonitor) snapshotFilesystemCache() {
    // Check system memory for cache pressure
    cmd := exec.Command("sysctl", "vm.loadavg")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse load average for pressure detection
    if strings.Contains(string(output), "5.00") {
        m.onMemoryPressure()
    }
}

func (m *CacheMonitor) checkFilesystemCache() {
    m.snapshotFilesystemCache()
}

func (m *CacheMonitor) onCacheEvicted(count int) {
    if !m.config.SoundOnEvict {
        return
    }

    // Only alert on significant evictions
    if count < 10 {
        return
    }

    sound := m.config.Sounds["evict"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *CacheMonitor) onCacheCleaned() {
    if !m.config.SoundOnClean {
        return
    }

    // Debounce: only alert once per 5 minutes
    if time.Since(m.lastCleanTime) < 5*time.Minute {
        return
    }
    m.lastCleanTime = time.Now()

    sound := m.config.Sounds["clean"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CacheMonitor) onMemoryPressure() {
    if !m.config.SoundOnPressure {
        return
    }

    sound := m.config.Sounds["pressure"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| redis-cli | Tool | Free | Redis management |
| memcached-tool | Tool | Free | Memcached stats |
| sysctl | System Tool | Free | System metrics |

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
| macOS | Supported | Uses redis-cli, sysctl |
| Linux | Supported | Uses redis-cli, sysctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
