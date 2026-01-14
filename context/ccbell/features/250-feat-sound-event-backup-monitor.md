# Feature: Sound Event Backup Monitor

Play sounds for backup operations and completion events.

## Summary

Monitor backup operations, sync completion, and restoration events, playing sounds for backup activities.

## Motivation

- Backup completion alerts
- Sync finish feedback
- Restore notifications
- Backup failure warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Backup Events

| Event | Description | Example |
|-------|-------------|---------|
| Backup Started | Backup initiated | Time Machine start |
| Backup Complete | Backup finished | Success |
| Backup Failed | Backup errored | Disk full |
| Sync Complete | Sync finished | iCloud sync |
| Restore Started | Restore began | Recovery mode |
| Restore Complete | Restore finished | Data restored |

### Configuration

```go
type BackupMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchServices    []string          `json:"watch_services"` // "timemachine", "rsync", "restic"
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnComplete  bool              `json:"sound_on_complete"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type BackupEvent struct {
    ServiceName  string
    EventType    string // "started", "complete", "failed", "sync"
    SourcePath   string
    DestPath     string
    BytesCopied  int64
    Duration     time.Duration
}
```

### Commands

```bash
/ccbell:backup status              # Show backup status
/ccbell:backup add timemachine     # Add service to watch
/ccbell:backup remove timemachine
/ccbell:backup sound complete <sound>
/ccbell:backup sound failed <sound>
/ccbell:backup test                # Test backup sounds
```

### Output

```
$ ccbell:backup status

=== Sound Event Backup Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes

Watched Services: 2

[1] Time Machine
    Last Backup: 2 hours ago
    Status: Completed
    Size: 245 GB
    Sound: bundled:stop

[2] Restic
    Last Backup: 1 day ago
    Status: Completed
    Size: 50 GB
    Sound: bundled:stop

Recent Events:
  [1] Time Machine: Backup Complete (2 hours ago)
       245 GB backed up
  [2] Restic: Backup Complete (1 day ago)
       50 GB backed up
       Duration: 45 min

Sound Settings:
  Started: bundled:stop
  Complete: bundled:stop
  Failed: bundled:stop
  Sync: bundled:stop

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Backup monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Backup Monitor

```go
type BackupMonitor struct {
    config          *BackupMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    backupState     map[string]*BackupStatus
}

type BackupStatus struct {
    ServiceName string
    Running     bool
    LastRun     time.Time
    LastSuccess time.Time
    LastBytes   int64
    ErrorMsg    string
}

func (m *BackupMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.backupState = make(map[string]*BackupStatus)
    go m.monitor()
}

func (m *BackupMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBackups()
        case <-m.stopCh:
            return
        }
    }
}

func (m *BackupMonitor) checkBackups() {
    for _, service := range m.config.WatchServices {
        m.checkService(service)
    }
}

func (m *BackupMonitor) checkService(service string) {
    switch service {
    case "timemachine":
        m.checkTimeMachine()
    case "rsync":
        m.checkRsync()
    case "restic":
        m.checkRestic()
    }
}

func (m *BackupMonitor) checkTimeMachine() {
    cmd := exec.Command("tmutil", "status")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    result := string(output)
    status := m.parseTimeMachineStatus(result)

    state := m.backupState["timemachine"]
    if state == nil {
        state = &BackupStatus{ServiceName: "Time Machine"}
        m.backupState["timemachine"] = state
    }

    if status.Running && !state.Running {
        // Backup started
        state.Running = true
        m.onBackupStarted("timemachine")
    } else if !status.Running && state.Running {
        // Backup finished
        state.Running = false
        if status.Error == "" {
            state.LastSuccess = time.Now()
            state.LastBytes = status.BytesCopied
            m.onBackupComplete("timemachine")
        } else {
            state.ErrorMsg = status.Error
            m.onBackupFailed("timemachine", status.Error)
        }
    }
}

func (m *BackupMonitor) parseTimeMachineStatus(output string) *TimeMachineStatus {
    status := &TimeMachineStatus{}

    if strings.Contains(output, "Running = 1") {
        status.Running = true
    }

    // Check for client ID (indicates active backup)
    if strings.Contains(output, "ClientID") {
        status.Running = true
    }

    return status
}

func (m *BackupMonitor) checkRsync() {
    // Check for running rsync processes
    cmd := exec.Command("pgrep", "-f", "rsync")
    _, err := cmd.Output()

    state := m.backupState["rsync"]
    if state == nil {
        state = &BackupStatus{ServiceName: "rsync"}
        m.backupState["rsync"] = state
    }

    if err == nil {
        // rsync is running
        if !state.Running {
            state.Running = true
            m.onBackupStarted("rsync")
        }
    } else {
        // rsync not running
        if state.Running {
            state.Running = false
            state.LastSuccess = time.Now()
            m.onBackupComplete("rsync")
        }
    }
}

func (m *BackupMonitor) checkRestic() {
    // Check for running restic processes
    cmd := exec.Command("pgrep", "-f", "restic")
    _, err := cmd.Output()

    state := m.backupState["restic"]
    if state == nil {
        state = &BackupStatus{ServiceName: "restic"}
        m.backupState["restic"] = state
    }

    if err == nil {
        // restic is running
        if !state.Running {
            state.Running = true
            m.onBackupStarted("restic")
        }
    } else {
        // restic not running
        if state.Running {
            state.Running = false
            state.LastSuccess = time.Now()
            m.onBackupComplete("restic")
        }
    }
}

func (m *BackupMonitor) onBackupStarted(service string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *BackupMonitor) onBackupComplete(service string) {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *BackupMonitor) onBackupFailed(service string, errorMsg string) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| tmutil | System Tool | Free | macOS Time Machine |
| pgrep | System Tool | Free | Process checking |
| rsync | System Tool | Free | File sync |
| restic | External Tool | Free | Backup software |

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
| macOS | Supported | Uses tmutil |
| Linux | Supported | Uses rsync, restic |
| Windows | Not Supported | ccbell only supports macOS/Linux |
