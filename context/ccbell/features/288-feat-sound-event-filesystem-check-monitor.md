# Feature: Sound Event Filesystem Check Monitor

Play sounds for filesystem check (fsck) events and results.

## Summary

Monitor filesystem check operations and results, playing sounds for fsck events.

## Motivation

- Filesystem error detection
- Check completion feedback
- Corruption alerts
- Repair notification

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Filesystem Check Events

| Event | Description | Example |
|-------|-------------|---------|
| Check Started | fsck initiated | /dev/disk1s1 |
| Check Passed | No errors | Clean |
| Errors Fixed | Issues repaired | 5 files fixed |
| Check Failed | Unrecoverable | Need manual |

### Configuration

```go
type FilesystemCheckMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchFilesystems  []string          `json:"watch_filesystems"` // "/", "/home"
    SoundOnStart      bool              `json:"sound_on_start"]
    SoundOnPass       bool              `json:"sound_on_pass"]
    SoundOnFail       bool              `json:"sound_on_fail"]
    SoundOnFix        bool              `json:"sound_on_fix"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type FilesystemCheckEvent struct {
    Filesystem  string
    Device      string
    Result      string // "passed", "failed", "fixed"
    ErrorsFixed int
    CheckTime   time.Time
}
```

### Commands

```bash
/ccbell:fsck status                  # Show fsck status
/ccbell:fsck add "/"                 # Add filesystem to watch
/ccbell:fsck remove "/"
/ccbell:fsck sound pass <sound>
/ccbell:fsck sound fail <sound>
/ccbell:fsck test                    # Test fsck sounds
```

### Output

```
$ ccbell:fsck status

=== Sound Event Filesystem Check Monitor ===

Status: Enabled
Pass Sounds: Yes
Fail Sounds: Yes

Watched Filesystems: 2

[1] / (APFS)
    Device: /dev/disk1s1
    Last Check: 1 week ago
    Result: PASSED
    Errors Fixed: 0
    Status: OK
    Sound: bundled:stop

[2] /home (APFS)
    Device: /dev/disk1s5
    Last Check: 2 days ago
    Result: PASSED
    Errors Fixed: 0
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] /: Check Passed (1 week ago)
       Clean mount
  [2] /home: Errors Fixed (2 weeks ago)
       3 orphaned inodes fixed
  [3] /: Check Started (1 month ago)

Filesystem Health:
  - No recent errors
  - All checks passing
  - Next scheduled: 1 week

Sound Settings:
  Start: bundled:stop
  Pass: bundled:stop
  Fail: bundled:stop
  Fix: bundled:stop

[Configure] [Add Filesystem] [Test All]
```

---

## Audio Player Compatibility

Filesystem check monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Filesystem Check Monitor

```go
type FilesystemCheckMonitor struct {
    config           *FilesystemCheckMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    fsckState        map[string]*FSCKStatus
}

type FSCKStatus struct {
    Filesystem   string
    Device       string
    LastCheck    time.Time
    Result       string
    ErrorsFixed  int
}
```

```go
func (m *FilesystemCheckMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fsckState = make(map[string]*FSCKStatus)
    go m.monitor()
}

func (m *FilesystemCheckMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkFilesystems()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FilesystemCheckMonitor) checkFilesystems() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinFilesystems()
    } else {
        m.checkLinuxFilesystems()
    }
}

func (m *FilesystemMonitor) checkDarwinFilesystems() {
    // Check fsck status from fsck_apfs or diskutil
    for _, fs := range m.config.WatchFilesystems {
        // Get mount point info
        cmd := exec.Command("diskutil", "info", fs)
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        // Parse filesystem info
        m.parseDiskutilInfo(fs, string(output))
    }

    // Check for recent fsck activity in logs
    m.checkFsckLogs()
}

func (m *FilesystemCheckMonitor) checkLinuxFilesystems() {
    // Check /proc/mounts and /etc/fstab for mounted filesystems
    mounts, err := os.ReadFile("/proc/mounts")
    if err != nil {
        return
    }

    lines := strings.Split(string(mounts), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        mountPoint := parts[1]
        fsType := parts[2]

        // Skip virtual filesystems
        if fsType == "proc" || fsType == "sysfs" || fsType == "devpts" ||
           fsType == "tmpfs" || fsType == "cgroup" || fsType == "cgroup2" {
            continue
        }

        if m.shouldWatchFilesystem(mountPoint) {
            m.checkFilesystemStatus(mountPoint, parts[0])
        }
    }
}

func (m *FilesystemCheckMonitor) parseDiskutilInfo(fs string, output string) {
    status := &FSCKStatus{
        Filesystem: fs,
    }

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Device Identifier:") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) >= 2 {
                status.Device = strings.TrimSpace(parts[1])
            }
        }
    }

    m.evaluateFilesystemStatus(fs, status)
}

func (m *FilesystemCheckMonitor) checkFsckLogs() {
    // Check system log for fsck events
    logPath := "/var/log/system.log"
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("log", "show", "--predicate", "eventMessage CONTAINS 'fsck'",
            "--last", "1h")
        output, err := cmd.Output()
        if err != nil {
            return
        }

        m.parseFsckLogOutput(string(output))
    } else {
        data, err := os.ReadFile("/var/log/syslog")
        if err != nil {
            return
        }

        m.parseLinuxFsckLog(string(data))
    }
}

func (m *FilesystemCheckMonitor) parseFsckLogOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "fsck_apfs") || strings.Contains(line, "fsck_hfs") {
            event := m.parseFsckLine(line)
            if event != nil {
                m.onFsckEvent(event)
            }
        }
    }
}

func (m *FilesystemCheckMonitor) parseFsckLine(line string) *FilesystemCheckEvent {
    event := &FilesystemCheckEvent{
        CheckTime: time.Now(),
    }

    // Parse fsck output for results
    if strings.Contains(line, "fsck_apfs") {
        if strings.Contains(line, "Volume") {
            re := regexp.MustCompile(`(disk\d+s\d+)`)
            match := re.FindStringSubmatch(line)
            if len(match) >= 1 {
                event.Device = match[1]
            }
        }

        if strings.Contains(line, "OK") || strings.Contains(line, "passed") {
            event.Result = "passed"
        } else if strings.Contains(line, "failed") || strings.Contains(line, "FAILED") {
            event.Result = "failed"
        } else if strings.Contains(line, "fixed") || strings.Contains(line, "FIXED") {
            event.Result = "fixed"
        }
    }

    return event
}

func (m *FilesystemCheckMonitor) shouldWatchFilesystem(path string) bool {
    if len(m.config.WatchFilesystems) == 0 {
        return true
    }

    for _, watch := range m.config.WatchFilesystems {
        if path == watch || strings.HasPrefix(path, watch) {
            return true
        }
    }

    return false
}

func (m *FilesystemCheckMonitor) evaluateFilesystemStatus(path string, status *FSCKStatus) {
    lastState := m.fsckState[path]

    if lastState == nil {
        m.fsckState[path] = status
        return
    }

    // Detect results
    if status.Result != "" && status.Result != lastState.Result {
        m.onFsckResult(path, status)
    }

    m.fsckState[path] = status
}

func (m *FilesystemCheckMonitor) onFsckEvent(event *FilesystemCheckEvent) {
    switch event.Result {
    case "passed":
        if m.config.SoundOnPass {
            sound := m.config.Sounds["pass"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    case "failed":
        if m.config.SoundOnFail {
            sound := m.config.Sounds["fail"]
            if sound != "" {
                m.player.Play(sound, 0.7)
            }
        }
    case "fixed":
        if m.config.SoundOnFix {
            sound := m.config.Sounds["fix"]
            if sound != "" {
                m.player.Play(sound, 0.6)
            }
        }
    }
}

func (m *FilesystemCheckMonitor) onFsckResult(path string, status *FSCKStatus) {
    switch status.Result {
    case "passed":
        if m.config.SoundOnPass {
            sound := m.config.Sounds["pass"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    case "failed":
        if m.config.SoundOnFail {
            sound := m.config.Sounds["fail"]
            if sound != "" {
                m.player.Play(sound, 0.7)
            }
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| diskutil | System Tool | Free | macOS disk utility |
| fsck | System Tool | Free | Filesystem check |
| /proc/mounts | File | Free | Linux mount info |

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
| macOS | Supported | Uses diskutil |
| Linux | Supported | Uses fsck, /proc/mounts |
| Windows | Not Supported | ccbell only supports macOS/Linux |
