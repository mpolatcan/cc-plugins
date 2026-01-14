# Feature: Sound Event File Descriptor Monitor

Play sounds for file descriptor usage and limits.

## Summary

Monitor file descriptor usage per process, playing sounds when processes approach or exceed limits.

## Motivation

- Resource exhaustion alerts
- FD leak detection
- Process health monitoring
- System limits awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### File Descriptor Events

| Event | Description | Example |
|-------|-------------|---------|
| FD High | FD count high | > 500 |
| FD Limit | At system limit | 1024/1024 |
| FD Leak | Increasing FD | Leak detected |
| FD Closed | FD count dropped | Cleaned up |

### Configuration

```go
type FileDescriptorMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchProcesses     []string          `json:"watch_processes"]
    WarningThreshold   int               `json:"warning_threshold"` // 500 default
    CriticalThreshold  int               `json:"critical_threshold"` // 900 default
    SoundOnWarning     bool              `json:"sound_on_warning"]
    SoundOnCritical    bool              `json:"sound_on_critical"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}

type FileDescriptorEvent struct {
    ProcessName string
    PID         int
    FDCount     int
    Limit       int
    UsagePercent float64
    EventType   string // "warning", "critical", "leak", "closed"
}
```

### Commands

```bash
/ccbell:fd status                    # Show FD status
/ccbell:fd add nginx                 # Add process to watch
/ccbell:fd remove nginx
/ccbell:fd warning 500               # Set warning threshold
/ccbell:fd sound warning <sound>
/ccbell:fd test                      # Test FD sounds
```

### Output

```
$ ccbell:fd status

=== Sound Event File Descriptor Monitor ===

Status: Enabled
Warning: 500
Critical: 900

Watched Processes: 3

[1] nginx (PID: 1234)
    FDs: 245 / 10240
    Usage: 2%
    Status: OK
    Sound: bundled:stop

[2] postgres (PID: 5678)
    FDs: 156 / 10240
    Usage: 2%
    Status: OK
    Sound: bundled:stop

[3] java (PID: 9012)
    FDs: 892 / 1024
    Usage: 87%
    Status: WARNING
    Sound: bundled:fd-warning

Recent Events:
  [1] java: Warning (5 min ago)
       502 FDs open (49%)
  [2] java: Leak Detected (1 hour ago)
       FD count increasing
  [3] nginx: FD Closed (2 hours ago)
       Cleaned up 50 FDs

System Limits:
  Soft Limit: 1024
  Hard Limit: 10240

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Leak: bundled:stop

[Configure] [Add Process] [Test All]
```

---

## Audio Player Compatibility

File descriptor monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Descriptor Monitor

```go
type FileDescriptorMonitor struct {
    config            *FileDescriptorMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    processFDCount    map[int]int
    fdHistory         map[int][]int // PID -> recent FD counts
    lastWarningTime   map[string]time.Time
}

func (m *FileDescriptorMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.processFDCount = make(map[int]int)
    m.fdHistory = make(map[int][]int)
    m.lastWarningTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FileDescriptorMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkFileDescriptors()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileDescriptorMonitor) checkFileDescriptors() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinFD()
    } else {
        m.checkLinuxFD()
    }
}

func (m *FileDescriptorMonitor) checkDarwinFD() {
    // Use lsof to get file descriptor counts
    cmd := exec.Command("lsof", "-F", "p")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLsofOutput(string(output))
}

func (m *FileDescriptorMonitor) checkLinuxFD() {
    // Read from /proc/*/fd for each process
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

        // Get process name
        cmdline := filepath.Join("/proc", entry.Name(), "cmdline")
        data, err := os.ReadFile(cmdline)
        if err != nil {
            continue
        }

        // Skip kernel processes
        if len(data) == 0 {
            continue
        }

        // Count open file descriptors
        fdPath := filepath.Join("/proc", entry.Name(), "fd")
        fds, err := os.ReadDir(fdPath)
        if err != nil {
            continue
        }

        processName := m.getProcessName(pid)
        if m.shouldWatchProcess(processName) {
            m.evaluateFDCount(pid, processName, len(fds))
        }
    }
}

func (m *FileDescriptorMonitor) parseLsofOutput(output string) {
    lines := strings.Split(output, "\n")
    fdCount := make(map[int]int)

    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse lsof -F output: "pPID\n"
        if strings.HasPrefix(line, "p") {
            pid, _ := strconv.Atoi(strings.TrimPrefix(line, "p"))
            fdCount[pid]++
        }
    }

    for pid, count := range fdCount {
        processName := m.getProcessName(pid)
        m.evaluateFDCount(pid, processName, count)
    }
}

func (m *FileDescriptorMonitor) getProcessName(pid int) string {
    cmdline := filepath.Join("/proc", strconv.Itoa(pid), "cmdline")
    data, err := os.ReadFile(cmdline)
    if err != nil {
        return ""
    }

    // cmdline is null-separated
    parts := strings.Split(string(data), "\x00")
    if len(parts) > 0 && parts[0] != "" {
        return filepath.Base(parts[0])
    }

    return ""
}

func (m *FileDescriptorMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, watch := range m.config.WatchProcesses {
        if strings.Contains(strings.ToLower(name), strings.ToLower(watch)) {
            return true
        }
    }

    return false
}

func (m *FileDescriptorMonitor) evaluateFDCount(pid int, name string, count int) {
    lastCount := m.processFDCount[pid]
    m.processFDCount[pid] = count

    // Get system limit
    limit := m.getSystemFDLimit()
    usagePercent := float64(count) / float64(limit) * 100

    // Update history for leak detection
    history := m.fdHistory[pid]
    history = append(history, count)
    if len(history) > 10 {
        history = history[len(history)-10:]
    }
    m.fdHistory[pid] = history

    // Check for leak (consistent increase)
    if len(history) >= 5 {
        increasing := true
        for i := 1; i < len(history); i++ {
            if history[i] <= history[i-1] {
                increasing = false
                break
            }
        }
        if increasing && count > m.config.WarningThreshold {
            m.onFDLeakDetected(name, pid, count)
        }
    }

    // Check thresholds
    if count >= m.config.CriticalThreshold {
        m.onFDCritical(name, pid, count, limit, usagePercent)
    } else if count >= m.config.WarningThreshold {
        if lastCount < m.config.WarningThreshold {
            m.onFDWarning(name, pid, count, limit, usagePercent)
        }
    } else if lastCount >= m.config.WarningThreshold && count < m.config.WarningThreshold {
        m.onFDCleaned(name, pid, count)
    }
}

func (m *FileDescriptorMonitor) getSystemFDLimit() int {
    data, err := os.ReadFile("/proc/sys/fs/file-max")
    if err != nil {
        return 1024
    }

    limit, _ := strconv.Atoi(strings.TrimSpace(string(data)))
    return limit
}

func (m *FileDescriptorMonitor) onFDWarning(name string, pid int, count int, limit int, percent float64) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%d", pid)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileDescriptorMonitor) onFDCritical(name string, pid int, count int, limit int, percent float64) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("critical:%d", pid)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *FileDescriptorMonitor) onFDLeakDetected(name string, pid int, count int) {
    sound := m.config.Sounds["leak"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *FileDescriptorMonitor) onFDCleaned(name string, pid int, count int) {
    sound := m.config.Sounds["closed"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *FileDescriptorMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastWarningTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastWarningTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lsof | System Tool | Free | macOS FD listing |
| /proc/*/fd | File | Free | Linux FD listing |

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
| macOS | Supported | Uses lsof |
| Linux | Supported | Uses /proc/*/fd |
| Windows | Not Supported | ccbell only supports macOS/Linux |
