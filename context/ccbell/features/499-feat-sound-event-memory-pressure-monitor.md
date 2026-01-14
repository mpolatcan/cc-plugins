# Feature: Sound Event Memory Pressure Monitor

Play sounds for low memory conditions, swap usage warnings, and OOM events.

## Summary

Monitor system memory and swap usage for warning thresholds, critical levels, and out-of-memory conditions, playing sounds for memory pressure events.

## Motivation

- Memory awareness
- Performance protection
- OOM prevention
- Swap monitoring
- System stability

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Memory Pressure Events

| Event | Description | Example |
|-------|-------------|---------|
| Low Memory | < 10% free | 8% free |
| Swap Warning | > 50% swap used | 60% swap |
| High Pressure | macOS pressure | 2 seconds |
| OOM Warning | OOM killer active | killed |
| Memory Full | 100% used | full |
| Cache Pressure | Low available memory | 500MB free |

### Configuration

```go
type MemoryPressureMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WarningPercent   int               `json:"warning_percent"` // 85 used
    CriticalPercent  int               `json:"critical_percent"` // 95 used
    SwapWarningPercent int             `json:"swap_warning_percent"` // 50
    SoundOnWarning   bool              `json:"sound_on_warning"`
    SoundOnCritical  bool              `json:"sound_on_critical"`
    SoundOnOOM       bool              `json:"sound_on_oom"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 15 default
}
```

### Commands

```bash
/ccbell:memory status               # Show memory status
/ccbell:memory warning 85           # Set warning threshold
/ccbell:memory sound warning <sound>
/ccbell:memory test                 # Test memory sounds
```

### Output

```
$ ccbell:memory status

=== Sound Event Memory Pressure Monitor ===

Status: Enabled
Warning: 85% used
Critical: 95% used
Swap Warning: 50% used

Memory Status:

[1] System Memory
    Total: 16 GB
    Used: 14.5 GB (91%) *** WARNING ***
    Free: 1.5 GB (9%)
    Available: 1.2 GB
    Buffers: 200 MB
    Cached: 3 GB
    Sound: bundled:memory *** WARNING ***

[2] Swap
    Total: 8 GB
    Used: 5 GB (62%) *** WARNING ***
    Free: 3 GB
    Sound: bundled:memory-swap *** WARNING ***

[3] Memory Pressure (macOS)
    System Pressure: Moderate
    Memory Pressure: 2 seconds
    Compressed: 500 MB
    Apps Using Memory: 45

Recent Events:

[1] System: Memory Warning (5 min ago)
       91% used (14.5/16 GB)
       Sound: bundled:memory-warning
  [2] Swap: Swap Warning (10 min ago)
       62% used (5/8 GB)
       Sound: bundled:memory-swap-warning
  [3] System: Memory Critical (30 min ago)
       96% used, OOM killer invoked
       Sound: bundled:memory-critical

Memory Statistics:
  Total Memory: 16 GB
  Used: 14.5 GB (91%)
  Free: 1.5 GB
  Swap Used: 5 GB (62%)
  Pressure Events: 3

Sound Settings:
  Warning: bundled:memory-warning
  Critical: bundled:memory-critical
  Swap Warning: bundled:memory-swap-warning
  OOM: bundled:memory-oom

[Configure] [Test All]
```

---

## Audio Player Compatibility

Memory monitoring doesn't play sounds directly:
- Monitoring feature using vm_stat, sysctl, free
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Memory Pressure Monitor

```go
type MemoryPressureMonitor struct {
    config        *MemoryPressureMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    memoryState   *MemoryInfo
    lastEventTime time.Time
}

type MemoryInfo struct {
    TotalBytes     int64
    UsedBytes      int64
    FreeBytes      int64
    AvailableBytes int64
    SwapTotalBytes int64
    SwapUsedBytes  int64
    UsedPercent    float64
    SwapPercent    float64
    Status         string // "healthy", "warning", "critical"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| vm_stat | System Tool | Free | macOS virtual memory |
| sysctl | System Tool | Free | System configuration |
| free | System Tool | Free | Linux memory stats |
| top | System Tool | Free | Process memory usage |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82) - GOOS-based detection

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses vm_stat, sysctl |
| Linux | Supported | Uses free, /proc/meminfo |
