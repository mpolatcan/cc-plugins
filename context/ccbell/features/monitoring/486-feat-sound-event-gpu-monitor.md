# Feature: Sound Event GPU Monitor

Play sounds for GPU temperature, utilization, memory usage, and thermal throttling.

## Summary

Monitor GPU (NVIDIA, AMD, Intel) for temperature, utilization, memory consumption, and performance events, playing sounds for GPU events.

## Motivation

- GPU awareness
- Temperature alerts
- Performance monitoring
- Thermal throttling detection
- Memory usage tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### GPU Events

| Event | Description | Example |
|-------|-------------|---------|
| High Temperature | > 80C | 85C detected |
| Critical Temperature | > 90C | 92C critical |
| Thermal Throttling | GPU throttled | throttled |
| High Utilization | > 90% | 95% GPU |
| High Memory | > 80% | 85% memory |
| Process Attached | New compute process | attached |

### Configuration

```go
type GPUMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WatchGPU            int               `json:"watch_gpu"` // 0 for first GPU
    WarningTemp         int               `json:"warning_temp_c"` // 80 default
    CriticalTemp        int               `json:"critical_temp_c"` // 90 default
    UtilizationThreshold int              `json:"utilization_threshold"` // 90 default
    MemoryThreshold     int               `json:"memory_threshold"` // 80 default
    SoundOnWarning      bool              `json:"sound_on_warning"`
    SoundOnCritical     bool              `json:"sound_on_critical"`
    SoundOnThrottle     bool              `json:"sound_on_throttle"`
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:gpu status                  # Show GPU status
/ccbell:gpu warning 80              # Set warning threshold
/ccbell:gpu sound warning <sound>
/ccbell:gpu test                    # Test GPU sounds
```

### Output

```
$ ccbell:gpu status

=== Sound Event GPU Monitor ===

Status: Enabled
Warning: 80C
Critical: 90C
Utilization Threshold: 90%

GPU Status:

[1] NVIDIA GeForce RTX 3080
    Status: HEALTHY
    Temperature: 65C
    Utilization: 45%
    Memory: 8 GB / 10 GB (80%)
    Power: 200W / 320W (62%)
    Fans: 45%
    Sound: bundled:gpu-nvidia

[2] AMD Radeon RX 6800
    Status: WARNING *** WARNING ***
    Temperature: 82C *** HIGH ***
    Utilization: 88%
    Memory: 12 GB / 16 GB (75%)
    Power: 180W / 250W (72%)
    Fans: 65%
    Sound: bundled:gpu-amd *** WARNING ***

Recent Events:

[1] AMD Radeon RX 6800: High Temperature (5 min ago)
       82C > 80C threshold
       Sound: bundled:gpu-warning
  [2] NVIDIA GeForce RTX 3080: Thermal Throttling (10 min ago)
       GPU throttling detected
       Sound: bundled:gpu-throttle
  [3] AMD Radeon RX 6800: High Memory (1 hour ago)
       85% memory usage
       Sound: bundled:gpu-memory

GPU Statistics:
  Total GPUs: 2
  Healthy: 1
  Warning: 1
  Throttling Events: 1

Sound Settings:
  Warning: bundled:gpu-warning
  Critical: bundled:gpu-critical
  Throttle: bundled:gpu-throttle
  Memory: bundled:gpu-memory

[Configure] [Test All]
```

---

## Audio Player Compatibility

GPU monitoring doesn't play sounds directly:
- Monitoring feature using nvidia-smi, rocm-smi, sensors
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### GPU Monitor

```go
type GPUMonitor struct {
    config        *GPUMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    gpuState      map[int]*GPUInfo
    lastEventTime map[string]time.Time
}

type GPUInfo struct {
    Index        int
    Name         string
    Temperature  float64
    Utilization  float64
    MemoryUsed   int64
    MemoryTotal  int64
    MemoryPercent float64
    Power        float64
    PowerMax     float64
    FanSpeed     int
    Status       string // "healthy", "warning", "critical", "throttling"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| nvidia-smi | System Tool | Free | NVIDIA GPU status |
| rocm-smi | System Tool | Free | AMD GPU status |
| sensors | System Tool | Free | Hardware sensors |

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
| macOS | Supported | Uses powermetrics |
| Linux | Supported | Uses nvidia-smi, rocm-smi, sensors |
