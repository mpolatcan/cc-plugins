# Feature: Sound Cache Management

Manage and optimize the local sound file cache.

## Summary

Tools to view, clean, and optimize the sound file cache for better performance.

## Motivation

- Clear corrupted cache files
- Free disk space
- View cache statistics
- Optimize cache performance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Cache Structure

Current ccbell uses:
- `~/.claude/ccbell.config.json` - Config
- `~/.claude/ccbell.state` - State
- Sound files in plugin directory

**Key Finding**: Cache management can be added for temporary files.

### Cache Operations

```go
type CacheManager struct {
    cacheDir    string
    maxSizeMB   int64
    maxAgeDays  int
}

type CacheEntry struct {
    Path       string
    SizeBytes  int64
    Created    time.Time
    Accessed   time.Time
    LastUsed   time.Time
}
```

### Commands

```bash
/ccbell:cache status              # Show cache statistics
/ccbell:cache list                # List cache files
/ccbell:cache clean               # Clean old entries
/ccbell:cache clean --older 7d    # Clean entries older than 7 days
/ccbell:cache optimize            # Optimize cache layout
/ccbell:cache size                # Show cache size
/ccbell:cache limit 100MB         # Set cache size limit
```

### Output

```
$ ccbell:cache status

=== Cache Status ===

Cache directory: /Users/me/.claude/ccbell/cache
Current size: 15.2 MB
Max size: 100 MB
Files: 45

Cache breakdown:
  TTS cache:       8.5 MB (12 files)
  Mixed sounds:    4.2 MB (8 files)
  Temp files:      2.5 MB (25 files)

$ ccbell:cache list

[1]  tts/voice_abc123.wav  1.2 MB  Created: Jan 10
[2]  tts/voice_def456.wav  0.8 MB  Created: Jan 11
[3]  mix/combined_xyz.wav  2.1 MB  Created: Jan 12
...
```

### Cache Cleaning

```go
func (m *CacheManager) Clean(olderThan time.Duration) error {
    cutoff := time.Now().Add(-olderThan)

    entries, _ := m.ListEntries()
    for _, entry := range entries {
        if entry.Created.Before(cutoff) {
            os.Remove(entry.Path)
            m.cleanedCount++
        }
    }

    return nil
}

func (m *CacheManager) CleanBySize(maxSizeMB int64) error {
    entries, _ := m.ListEntries()
    sortBySizeDescending(entries)

    currentSize := m.GetCurrentSize()
    targetSize := maxSizeMB * 1024 * 1024

    for currentSize > targetSize && len(entries) > 0 {
        os.Remove(entries[0].Path)
        currentSize -= entries[0].SizeBytes
        entries = entries[1:]
    }

    return nil
}
```

---

## Audio Player Compatibility

Cache management doesn't interact with audio playback:
- File management operations
- No player changes required
- Affects cache, not playback

---

## Implementation

### Cache Stats

```go
func (m *CacheManager) GetStats() CacheStats {
    entries, _ := m.ListEntries()

    stats := CacheStats{
        FileCount:   len(entries),
        TotalSize:   m.GetCurrentSize(),
        CacheDir:    m.cacheDir,
    }

    // Categorize files
    for _, entry := range entries {
        if strings.HasPrefix(entry.Path, "tts/") {
            stats.TTSCount++
            stats.TTSSize += entry.SizeBytes
        } else if strings.HasPrefix(entry.Path, "mix/") {
            stats.MixCount++
            stats.MixSize += entry.SizeBytes
        }
    }

    return stats
}
```

### Auto-Clean on Startup

```go
func (c *CCBell) autoCleanCache() {
    if c.cacheConfig.MaxSizeMB > 0 {
        currentSize := cacheManager.GetCurrentSize()
        maxSize := c.cacheConfig.MaxSizeMB * 1024 * 1024

        if currentSize > maxSize {
            log.Info("Cache size (%s) exceeds limit, cleaning...", formatSize(currentSize))
            cacheManager.CleanBySize(c.cacheConfig.MaxSizeMB)
        }
    }
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State file patterns
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config directory handling
- [File operations](https://pkg.go.dev/os) - Go file management

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | File management |
| Linux | ✅ Supported | File management |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
