# Feature: Sound Cache

Cache sounds for faster loading.

## Summary

Implement a caching system to speed up sound loading and reduce disk I/O.

## Motivation

- Faster sound loading
- Reduce disk I/O
- Offline sound access

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Cache Types

| Type | Description | Use Case |
|------|-------------|----------|
| Memory | RAM cache | Fast access |
| Disk | Persistent cache | Offline use |
| Hybrid | Memory + disk | Best of both |

### Configuration

```go
type CacheConfig struct {
    Enabled        bool    `json:"enabled"`
    Type           string  `json:"type"`           // "memory", "disk", "hybrid"
    MaxMemoryMB    int     `json:"max_memory_mb"`  // memory cache size
    MaxDiskMB      int     `json:"max_disk_mb"`    // disk cache size
    TTLHours       int     `json:"ttl_hours"`      // cache TTL
    PreloadBundled bool    `json:"preload_bundled"` // preload bundled
    ClearOnExit    bool    `json:"clear_on_exit"`  // clear on exit
}

type CacheEntry struct {
    SoundPath   string    `json:"sound_path"`
    CachedAt    time.Time `json:"cached_at"`
    SizeBytes   int64     `json:"size_bytes"`
    AccessCount int       `json:"access_count"`
    LastAccess  time.Time `json:"last_access"`
}
```

### Commands

```bash
/ccbell:cache enable               # Enable caching
/ccbell:cache disable              # Disable caching
/ccbell:cache status               # Show cache status
/ccbell:cache clear                # Clear cache
/ccbell:cache clear memory         # Clear memory cache
/ccbell:cache clear disk           # Clear disk cache
/ccbell:cache size 100             # Set max size 100MB
/ccbell:cache preload              # Preload all sounds
/ccbell:cache stats                # Show cache statistics
```

### Output

```
$ ccbell:cache status

=== Sound Cache ===

Status: Enabled
Type: Hybrid (Memory + Disk)

Memory Cache:
  Used: 15.2 MB / 50 MB
  Entries: 24
  Hit Rate: 89%

Disk Cache:
  Used: 45.3 MB / 200 MB
  Entries: 48
  Hit Rate: 94%

Preload: Enabled (bundled sounds)
TTL: 24 hours

[Clear] [Configure] [Stats] [Disable]
```

---

## Audio Player Compatibility

Cache doesn't play sounds:
- Performance optimization
- No player changes required
- Works with all audio players

---

## Implementation

### Memory Cache

```go
type MemoryCache struct {
    mu      sync.RWMutex
    items   map[string]*CacheEntry
    maxSize int // bytes
    current int // bytes
}

func (m *MemoryCache) Get(soundPath string) ([]byte, error) {
    m.mu.RLock()
    defer m.mu.RUnlock()

    entry, exists := m.items[soundPath]
    if !exists {
        return nil, fmt.Errorf("not in cache")
    }

    // Check TTL
    if time.Since(entry.CachedAt) > m.ttl {
        return nil, fmt.Errorf("expired")
    }

    entry.AccessCount++
    entry.LastAccess = time.Now()

    data, err := os.ReadFile(m.getCachePath(soundPath))
    if err != nil {
        return nil, err
    }

    return data, nil
}

func (m *MemoryCache) Put(soundPath string, data []byte) error {
    m.mu.Lock()
    defer m.mu.Unlock()

    // Evict if needed
    for m.current+len(data) > m.maxSize {
        m.evictOldest()
    }

    // Write to disk cache
    cachePath := m.getCachePath(soundPath)
    os.MkdirAll(filepath.Dir(cachePath), 0755)
    os.WriteFile(cachePath, data, 0644)

    m.items[soundPath] = &CacheEntry{
        SoundPath:  soundPath,
        CachedAt:   time.Now(),
        SizeBytes:  int64(len(data)),
        AccessCount: 1,
        LastAccess: time.Now(),
    }

    m.current += len(data)
    return nil
}
```

### Preloading

```go
func (c *CacheManager) PreloadBundled() error {
    sounds, err := c.listBundledSounds()
    if err != nil {
        return err
    }

    for _, sound := range sounds {
        data, err := os.ReadFile(sound.Path)
        if err != nil {
            continue
        }

        if err := c.memoryCache.Put(sound.Path, data); err != nil {
            log.Debug("Failed to cache %s: %v", sound.Path, err)
        }
    }

    return nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Player initialization](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L73-79) - Player creation
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Sound path resolution

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
