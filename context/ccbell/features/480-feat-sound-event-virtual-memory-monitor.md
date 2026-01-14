# Feature: Sound Event Virtual Memory Monitor

Play sounds for virtual memory pressure, swap paging, and OOM killer events.

## Summary

Monitor virtual memory (swap, page faults, memory pressure) for performance issues and OOM conditions, playing sounds for VM events.

## Motivation

- Memory pressure alerts
- Swap activity detection
- OOM prevention
- Performance monitoring
- Page fault tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Virtual Memory Events

| Event | Description | Example |
|-------|-------------|---------|
| High Pressure | Memory pressure high | high |
| Low Memory | Available memory low | low |
| Swap In | Pages swapped in | swap in |
| Swap Out | Pages swapped out | swap out |
| Page Fault | Page fault rate | high faults |
| OOM Kill | Process killed | oom-killed |

### Configuration

```go
type VirtualMemoryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    PressureThreshold int               `json:"pressure_threshold"` // 80
    SwapThresholdMB   int               `json:"swap_threshold_mb"` // 1000
    FaultThreshold    int               `json:"fault_threshold_per_sec"` // 1000
    SoundOnPressure   bool              `json:"sound_on_pressure"`
    SoundOnSwap       bool              `json:"sound_on_swap"`
    SoundOnOOM        bool              `json:"sound_on_oom"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:vm status                   # Show VM status
/ccbell:vm pressure 80              # Set pressure threshold
/ccbell:vm sound pressure <sound>
/ccbell:vm test                     # Test VM sounds
```

### Output

```
$ ccbell:vm status

=== Sound Event Virtual Memory Monitor ===

Status: Enabled
Pressure Threshold: 80%
Swap Threshold: 1000 MB

Virtual Memory Status:

[1] System Memory
    Status: HEALTHY
    Total: 16 GB
    Used: 11 GB (68%)
    Available: 5 GB
    Pressure: LOW
    Sound: bundled:vm-normal

[2] Swap
    Status: HEALTHY
    Total: 2 GB
    Used: 0 GB (0%)
    Free: 2 GB
    Swap In: 0 KB/s
    Swap Out: 0 KB/s
    Sound: bundled:vm-swap

[3] Page Faults
    Status: NORMAL
    Major: 5/sec
    Minor: 1000/sec
    Fault Rate: Normal
    Sound: bundled:vm-faults

Recent Events:

[1] System: High Memory Pressure (5 min ago)
       Pressure: HIGH (85%)
       Sound: bundled:vm-pressure
  [2] postgres: OOM Killed (30 min ago)
       Out of memory, killed pid 12345
       Sound: bundled:vm-oom
  [3] System: Swap Activity (1 hour ago)
       500 MB swapped in, 200 MB out
       Sound: bundled:vm-swap-activity

Virtual Memory Statistics:
  Memory Used: 68%
  Swap Used: 0%
  Page Faults: 1005/sec
  OOM Kills Today: 1

Sound Settings:
  Pressure: bundled:vm-pressure
  Swap: bundled:vm-swap
  OOM: bundled:vm-oom
  Fault: bundled:vm-fault

[Configure] [Test All]
```

---

## Audio Player Compatibility

VM monitoring doesn't play sounds directly:
- Monitoring feature using vm_stat, swapon, sar
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Virtual Memory Monitor

```go
type VirtualMemoryMonitor struct {
    config        *VirtualMemoryMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    vmState       *VMInfo
    lastEventTime map[string]time.Time
}

type VMInfo struct {
    TotalBytes     int64
    UsedBytes      int64
    AvailableBytes int64
    Pressure       string // "low", "medium", "high"
    SwapTotalBytes int64
    SwapUsedBytes  int64
    SwapInRate     int64
    SwapOutRate    int64
    MajorFaults    int64
    MinorFaults    int64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| vm_stat | System Tool | Free | macOS VM stats |
| sar | System Tool | Free | System activity reporter |
| swapon | System Tool | Free | Swap status |

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
| macOS | Supported | Uses vm_stat |
| Linux | Supported | Uses sar, /proc/vmstat |
