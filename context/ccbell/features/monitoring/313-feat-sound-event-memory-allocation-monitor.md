# Feature: Sound Event Memory Allocation Monitor

Play sounds for large memory allocations and allocation failures.

## Summary

Monitor memory allocation patterns and failures, playing sounds for significant allocation events.

## Motivation

- Memory pressure awareness
- Allocation failure detection
- Performance monitoring
- Memory leak detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Memory Allocation Events

| Event | Description | Example |
|-------|-------------|---------|
| Large Allocation | > 1GB allocated | malloc(2GB) |
| Allocation Failed | ENOMEM error | Cannot allocate |
| Reallocation | Memory resized | realloc() |
| Deallocation | Memory freed | free() |

### Configuration

```go
type MemoryAllocationMonitorConfig struct {
    Enabled              bool              `json:"enabled"`
    WatchProcesses       []string          `json:"watch_processes"]
    LargeAllocationSize  int               `json:"large_allocation_mb"` // 1024 default
    SoundOnLargeAlloc    bool              `json:"sound_on_large_alloc"]
    SoundOnAllocFail     bool              `json:"sound_on_alloc_fail"]
    Sounds               map[string]string `json:"sounds"`
    PollInterval         int               `json:"poll_interval_sec"` // 30 default
}

type MemoryAllocationEvent struct {
    ProcessName string
    PID         int
    Size        int64
    EventType   string // "large_alloc", "alloc_fail", "realloc"
}
```

### Commands

```bash
/ccbell:memalloc status               # Show memory allocation status
/ccbell:memalloc add nginx            # Add process to watch
/ccbell:memalloc remove nginx
/ccbell:memalloc large 1024           # Set large allocation threshold
/ccbell:memalloc sound fail <sound>
/ccbell:memalloc test                 # Test memory sounds
```

### Output

```
$ ccbell:memalloc status

=== Sound Event Memory Allocation Monitor ===

Status: Enabled
Large Allocation: 1024 MB
Fail Sounds: Yes

Watched Processes: 2

[1] chrome (PID: 1234)
    Memory: 4 GB
    Allocations: 1,234
    Large Allocs: 5
    Sound: bundled:stop

[2] postgres (PID: 5678)
    Memory: 8 GB
    Allocations: 567
    Large Allocs: 2
    Sound: bundled:memalloc-large

Recent Events:
  [1] chrome: Large Allocation (5 min ago)
       2 GB allocated
  [2] postgres: Large Allocation (10 min ago)
       1.5 GB allocated
  [3] node: Allocation Failed (1 hour ago)
       Cannot allocate memory

Memory Statistics:
  Total large allocs: 7
  Failed allocs: 1

Sound Settings:
  Large Alloc: bundled:memalloc-large
  Alloc Fail: bundled:memalloc-fail

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

Memory allocation monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Memory Allocation Monitor

```go
type MemoryAllocationMonitor struct {
    config                *MemoryAllocationMonitorConfig
    player                *audio.Player
    running               bool
    stopCh                chan struct{}
    processMemoryUsage    map[int]*ProcessMemoryInfo
    lastEventTime         map[string]time.Time
}

type ProcessMemoryInfo struct {
    PID         int
    ProcessName string
    VMSize      int64
    RSS         int64
    Allocations int64
}

func (m *MemoryAllocationMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processMemoryUsage = make(map[int]*ProcessMemoryInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *MemoryAllocationMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotMemoryUsage()

    for {
        select {
        case <-ticker.C:
            m.checkMemoryAllocations()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MemoryAllocationMonitor) snapshotMemoryUsage() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinMemory()
    } else {
        m.snapshotLinuxMemory()
    }
}

func (m *MemoryAllocationMonitor) snapshotDarwinMemory() {
    cmd := exec.Command("ps", "-eo", "pid,rss,vsz,comm")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePSOutput(string(output))
}

func (m *MemoryAllocationMonitor) snapshotLinuxMemory() {
    // Read /proc/*/status for all processes
    entries, err := os.ReadDir("/proc")
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        pid, err := strconv.Atoi(entry.Name())
        if err != nil {
            continue
        }

        m.getProcessMemoryInfo(pid)
    }
}

func (m *MemoryAllocationMonitor) checkMemoryAllocations() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinAllocations()
    } else {
        m.checkLinuxAllocations()
    }
}

func (m *MemoryAllocationMonitor) checkDarwinAllocations() {
    cmd := exec.Command("ps", "-eo", "pid,rss,vsz,comm")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePSOutput(string(output))
}

func (m *MemoryAllocationMonitor) checkLinuxAllocations() {
    entries, err := os.ReadDir("/proc")
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        pid, err := strconv.Atoi(entry.Name())
        if err != nil {
            continue
        }

        m.getProcessMemoryInfo(pid)
    }
}

func (m *MemoryAllocationMonitor) parsePSOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "PID") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        pid, _ := strconv.Atoi(parts[0])
        rssKB, _ := strconv.ParseInt(parts[1], 10, 64)
        vszKB, _ := strconv.ParseInt(parts[2], 10, 64)
        processName := parts[3]

        vszMB := vszKB / 1024

        // Check for large allocation
        if vszMB >= int64(m.config.LargeAllocationSize) {
            if m.shouldWatchProcess(processName) {
                m.onLargeAllocation(processName, pid, vszMB*1024*1024)
            }
        }

        m.processMemoryUsage[pid] = &ProcessMemoryInfo{
            PID:         pid,
            ProcessName: processName,
            VMSize:      vszKB * 1024,
            RSS:         rssKB * 1024,
        }
    }
}

func (m *MemoryAllocationMonitor) getProcessMemoryInfo(pid int) {
    statusFile := filepath.Join("/proc", strconv.Itoa(pid), "status")
    data, err := os.ReadFile(statusFile)
    if err != nil {
        return
    }

    var vmSize, rss int64
    var processName string

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "VmSize:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                vmSize, _ = strconv.ParseInt(parts[1], 10, 64) // kB
            }
        } else if strings.HasPrefix(line, "VmRSS:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                rss, _ = strconv.ParseInt(parts[1], 10, 64) // kB
            }
        } else if strings.HasPrefix(line, "Name:") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) >= 2 {
                processName = strings.TrimSpace(parts[1])
            }
        }
    }

    vmMB := vmSize / 1024

    // Check for large allocation
    if vmMB >= int64(m.config.LargeAllocationSize) {
        if m.shouldWatchProcess(processName) {
            m.onLargeAllocation(processName, pid, vmSize*1024)
        }
    }

    m.processMemoryUsage[pid] = &ProcessMemoryInfo{
        PID:         pid,
        ProcessName: processName,
        VMSize:      vmSize * 1024,
        RSS:         rss * 1024,
    }
}

func (m *MemoryAllocationMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, process := range m.config.WatchProcesses {
        if name == process {
            return true
        }
    }

    return false
}

func (m *MemoryAllocationMonitor) onLargeAllocation(processName string, pid int, size int64) {
    if !m.config.SoundOnLargeAlloc {
        return
    }

    key := fmt.Sprintf("large:%s:%d", processName, pid)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["large_alloc"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *MemoryAllocationMonitor) onAllocationFailed(processName string) {
    if !m.config.SoundOnAllocFail {
        return
    }

    key := fmt.Sprintf("fail:%s", processName)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["alloc_fail"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *MemoryAllocationMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ps | System Tool | Free | Process memory info |
| /proc/*/status | File | Free | Linux memory info |

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
| macOS | Supported | Uses ps |
| Linux | Supported | Uses /proc/*/status |
| Windows | Not Supported | ccbell only supports macOS/Linux |
