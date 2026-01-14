# Feature: Sound Event System Boot Monitor

Play sounds for system boot completion, boot time milestones, and shutdown events.

## Summary

Monitor system boot process for completion, boot time analysis, and shutdown detection, playing sounds for boot events.

## Motivation

- Boot completion awareness
- Boot time tracking
- Startup service monitoring
- Shutdown detection
- System startup feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### System Boot Events

| Event | Description | Example |
|-------|-------------|---------|
| Boot Started | System powering on | power on |
| Boot Completed | System ready | login screen |
| Boot Slow | Time > threshold | > 60s |
| Service Started | Important service up | network ready |
| Shutdown Started | System shutting down | power off |
| Emergency Boot | Recovery mode | rescue mode |

### Configuration

```go
type SystemBootMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    TargetLevel       string            `json:"target_level"` // "graphical", "multi-user"
    BootTimeout       int               `json:"boot_timeout_sec"` // 120 default
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnSlow       bool              `json:"sound_on_slow"`
    SoundOnShutdown   bool              `json:"sound_on_shutdown"`
    Sounds            map[string]string `json:"sounds"`
}
```

### Commands

```bash
/ccbell:boot status                    # Show boot status
/ccbell:boot timeout 120               # Set boot timeout
/ccbell:boot sound complete <sound>
/ccbell:boot sound slow <sound>
/ccbell:boot test                      # Test boot sounds
```

### Output

```
$ ccbell:boot status

=== Sound Event System Boot Monitor ===

Status: Enabled
Target Level: graphical
Boot Timeout: 120 seconds
Complete Sounds: Yes
Slow Sounds: Yes

Last Boot Information:
  Date: Jan 14, 2026 08:30:15
  Duration: 45.2 seconds
  Status: SUCCESS

Boot Milestones:
  Kernel: 2.1s
  Init: 5.5s
  Network: 12.3s
  Services: 35.0s
  GUI: 45.2s

Previous Boot Times:
  Today: 45.2s (normal)
  Yesterday: 48.1s (normal)
  Last Week Avg: 47.5s

Boot Statistics:
  Total Boots: 30
  Successful: 30
  Slow Boots: 2 (> 60s)
  Avg Boot Time: 47.5s

Recent Events:
  [1] Boot Completed (5 hours ago)
       45.2s total time
  [2] Boot Slow (1 week ago)
       75.3s > 60s threshold
  [3] Shutdown Started (1 week ago)
       System powering off

Sound Settings:
  Complete: bundled:boot-complete
  Slow: bundled:boot-slow
  Shutdown: bundled:boot-shutdown

[Configure] [Test All]
```

---

## Audio Player Compatibility

Boot monitoring doesn't play sounds directly:
- Monitoring feature using systemd-analyze/uptime
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Boot Monitor

```go
type SystemBootMonitor struct {
    config          *SystemBootMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    bootState       *BootInfo
    lastEventTime   map[string]time.Time
}

type BootInfo struct {
    StartTime       time.Time
    EndTime         time.Time
    Duration        time.Duration
    Status          string // "success", "slow", "failed"
    Milestones      map[string]time.Duration
}

func (m *SystemBootMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.bootState = &BootInfo{
        Milestones: make(map[string]time.Duration),
    }
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemBootMonitor) monitor() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBootStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemBootMonitor) checkBootStatus() {
    // Check if system just booted (uptime < 5 minutes)
    uptime := m.getUptime()

    if uptime < 5*time.Minute && m.bootState.EndTime.IsZero() {
        // System is booting or just booted
        m.bootState.StartTime = time.Now().Add(-uptime)

        // Check boot progress
        progress := m.checkBootProgress()

        if m.bootState.Status == "success" && progress >= 100 {
            m.onBootComplete()
        }
    } else if uptime > 5*time.Minute && !m.bootState.EndTime.IsZero() {
        // Reset for next boot
        m.bootState = &BootInfo{
            Milestones: make(map[string]time.Duration),
        }
    }
}

func (m *SystemBootMonitor) getUptime() time.Duration {
    cmd := exec.Command("uptime", "-p")
    output, err := cmd.Output()
    if err != nil {
        // Fallback: use /proc/uptime
        data, err := os.ReadFile("/proc/uptime")
        if err != nil {
            return 0
        }
        parts := strings.Fields(string(data))
        seconds, _ := strconv.ParseFloat(parts[0], 64)
        return time.Duration(seconds * float64(time.Second))
    }

    // Parse "up 5 minutes, 2 users"
    outputStr := strings.TrimSpace(string(output))
    if strings.HasPrefix(outputStr, "up ") {
        // Parse duration
        re := regexp.MustEach(`(\d+)`)
        matches := re.FindAllString(outputStr, -1)
        if len(matches) >= 1 {
            minutes, _ := strconv.Atoi(matches[0])
            return time.Duration(minutes) * time.Minute
        }
    }

    return 0
}

func (m *SystemBootMonitor) checkBootProgress() int {
    // Use systemd-analyze for boot time
    cmd := exec.Command("systemd-analyze", "time")
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    // Parse: "Startup finished in 2.1s (kernel) + 5.5s (initrd) + 35.0s (userspace) = 45.2s"
    outputStr := string(output)

    re := regexp.MustEach(`\+ ([\d.]+s)`)
    matches := re.FindAllStringSubmatch(outputStr, -1)

    totalDuration := 0.0
    milestones := make(map[string]time.Duration)

    milestoneNames := []string{"kernel", "initrd", "userspace"}

    for i, match := range matches {
        if i >= len(milestoneNames) {
            break
        }
        durationStr := match[1]
        durationStr = strings.TrimSuffix(durationStr, "s")
        duration, _ := strconv.ParseFloat(durationStr, 64)
        milestones[milestoneNames[i]] = time.Duration(duration * float64(time.Second))
        totalDuration += duration
    }

    m.bootState.Duration = time.Duration(totalDuration * float64(time.Second))
    m.bootState.Milestones = milestones

    // Check if boot is complete (userspace finished)
    if _, exists := milestones["userspace"]; exists {
        m.bootState.Status = "success"

        if totalDuration > float64(m.config.BootTimeout) {
            m.bootState.Status = "slow"
        }
    }

    // Calculate progress
    elapsed := time.Since(m.bootState.StartTime)
    estimatedTotal := m.bootState.Duration

    if estimatedTotal > 0 {
        return int(float64(elapsed) / float64(estimatedTotal) * 100)
    }

    return 0
}

func (m *SystemBootMonitor) onBootComplete() {
    m.bootState.EndTime = time.Now()

    if m.bootState.Status == "success" {
        if m.config.SoundOnComplete {
            key := "boot:complete"
            if m.shouldAlert(key, 24*time.Hour) {
                sound := m.config.Sounds["complete"]
                if sound != "" {
                    m.player.Play(sound, 0.4)
                }
            }
        }
    } else if m.bootState.Status == "slow" {
        if m.config.SoundOnSlow {
            key := "boot:slow"
            if m.shouldAlert(key, 24*time.Hour) {
                sound := m.config.Sounds["slow"]
                if sound != "" {
                    m.player.Play(sound, 0.5)
                }
            }
        }
    }
}

func (m *SystemBootMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| systemd-analyze | System Tool | Free | Boot time analysis |
| uptime | System Tool | Free | System uptime |
| /proc/uptime | Linux Path | Free | Uptime information |

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
| macOS | Supported | Uses uptime, /proc/uptime |
| Linux | Supported | Uses systemd-analyze, uptime |
