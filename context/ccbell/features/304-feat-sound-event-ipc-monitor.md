# Feature: Sound Event IPC Monitor

Play sounds for inter-process communication events.

## Summary

Monitor IPC mechanisms including shared memory, semaphores, message queues, and pipes, playing sounds for IPC events.

## Motivation

- IPC awareness
- Resource exhaustion detection
- Process communication feedback
- System health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### IPC Events

| Event | Description | Example |
|-------|-------------|---------|
| Queue Created | Message queue created | msgget() |
| Semaphore Created | Semaphore created | semget() |
| Shared Memory Created | Shmem attached | shmat() |
| IPC Removed | IPC resource removed | ipcrm |

### Configuration

```go
type IPCMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchTypes        []string          `json:"watch_types"` // "msg", "sem", "shm"
    SoundOnCreate     bool              `json:"sound_on_create"]
    SoundOnRemove     bool              `json:"sound_on_remove"]
    SoundOnFull       bool              `json:"sound_on_full"] // Queue full
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type IPCEvent struct {
    IPCType   string // "msg", "sem", "shm"
    Key       int
    ID        int
    Owner     string
    EventType string // "create", "remove", "full"
}
```

### Commands

```bash
/ccbell:ipc status                    # Show IPC status
/ccbell:ipc add msg                   # Add IPC type to watch
/ccbell:ipc remove msg
/ccbell:ipc sound create <sound>
/ccbell:ipc sound full <sound>
/ccbell:ipc test                      # Test IPC sounds
```

### Output

```
$ ccbell:ipc status

=== Sound Event IPC Monitor ===

Status: Enabled
Create Sounds: Yes
Full Sounds: Yes

Watched Types: 3

[1] Message Queues
    Count: 5
    Last Create: 5 min ago
    Sound: bundled:stop

[2] Semaphores
    Count: 12
    Last Create: 10 min ago
    Sound: bundled:stop

[3] Shared Memory
    Count: 8
    Last Create: 1 hour ago
    Sound: bundled:stop

Recent Events:
  [1] Shared Memory Created (5 min ago)
       ID: 65536, Owner: user
  [2] Message Queue Full (10 min ago)
       ID: 32768, Owner: postgres
  [3] Semaphore Removed (1 hour ago)
       ID: 16384, Owner: root

IPC Statistics:
  Created/min: 2
  Removed/min: 1

Sound Settings:
  Create: bundled:stop
  Remove: bundled:stop
  Full: bundled:ipc-full

[Configure] [Add Type] [Test All]
```

---

## Audio Player Compatibility

IPC monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### IPC Monitor

```go
type IPCMonitor struct {
    config          *IPCMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    ipcState        map[string]int
    lastIPCChange   map[string]time.Time
}

func (m *IPCMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.ipcState = make(map[string]int)
    m.lastIPCChange = make(map[string]time.Time)
    go m.monitor()
}

func (m *IPCMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotIPCState()

    for {
        select {
        case <-ticker.C:
            m.checkIPCState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *IPCMonitor) snapshotIPCState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinIPC()
    } else {
        m.snapshotLinuxIPC()
    }
}

func (m *IPCMonitor) snapshotLinuxIPC() {
    // Check message queues
    if m.shouldWatchType("msg") {
        m.checkLinuxMsgQueues()
    }

    // Check semaphores
    if m.shouldWatchType("sem") {
        m.checkLinuxSemaphores()
    }

    // Check shared memory
    if m.shouldWatchType("shm") {
        m.checkLinuxSharedMemory()
    }
}

func (m *IPCMonitor) checkIPCState() {
    if runtime.GOOS == "darwin" {
        // Limited IPC support on macOS
        return
    }

    m.snapshotLinuxIPC()
}

func (m *IPCMonitor) checkLinuxMsgQueues() {
    cmd := exec.Command("ipcs", "-q")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    count := m.parseIPCSOutput(string(output))
    m.onIPCChange("msg", count)
}

func (m *IPCMonitor) checkLinuxSemaphores() {
    cmd := exec.Command("ipcs", "-s")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    count := m.parseIPCSOutput(string(output))
    m.onIPCChange("sem", count)
}

func (m *IPCMonitor) checkLinuxSharedMemory() {
    cmd := exec.Command("ipcs", "-m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    count := m.parseIPCSOutput(string(output))
    m.onIPCChange("shm", count)
}

func (m *IPCMonitor) parseIPCSOutput(output string) int {
    lines := strings.Split(output, "\n")
    count := 0

    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "------") {
            continue
        }

        // Count non-header lines
        if !strings.HasPrefix(line, "T") && !strings.HasPrefix(line, "Message") {
            if strings.HasPrefix(line, "0x") || strings.HasPrefix(line, "q") || strings.HasPrefix(line, "s") {
                count++
            }
        }
    }

    return count
}

func (m *IPCMonitor) snapshotDarwinIPC() {
    // macOS doesn't have ipcs, check with launchctl for Mach ports
    cmd := exec.Command("launchctl", "list")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Approximate IPC count from running services
    lines := strings.Split(string(output), "\n")
    count := 0
    for _, line := range lines {
        if !strings.HasPrefix(line, "-") {
            count++
        }
    }

    m.ipcState["mach"] = count
}

func (m *IPCMonitor) shouldWatchType(ipcType string) bool {
    if len(m.config.WatchTypes) == 0 {
        return true
    }

    for _, t := range m.config.WatchTypes {
        if t == ipcType {
            return true
        }
    }

    return false
}

func (m *IPCMonitor) onIPCChange(ipcType string, newCount int) {
    lastCount := m.ipcState[ipcType]

    if lastCount == 0 {
        m.ipcState[ipcType] = newCount
        return
    }

    if newCount > lastCount {
        // IPC created
        m.onIPCCreated(ipcType, newCount-lastCount)
    } else if newCount < lastCount {
        // IPC removed
        m.onIPCRemoved(ipcType, lastCount-newCount)
    }

    m.ipcState[ipcType] = newCount
}

func (m *IPCMonitor) onIPCCreated(ipcType string, count int) {
    if !m.config.SoundOnCreate {
        return
    }

    // Only alert on significant creation bursts
    if count < 3 {
        return
    }

    key := fmt.Sprintf("create:%s", ipcType)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["create"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *IPCMonitor) onIPCRemoved(ipcType string, count int) {
    if !m.config.SoundOnRemove {
        return
    }

    sound := m.config.Sounds["remove"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *IPCMonitor) onIPCFull(ipcType string) {
    if !m.config.SoundOnFull {
        return
    }

    key := fmt.Sprintf("full:%s", ipcType)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["full"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *IPCMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastIPCChange[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastIPCChange[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ipcs | System Tool | Free | Linux IPC status |
| ipcrm | System Tool | Free | IPC removal |
| launchctl | System Tool | Free | macOS service management |

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
| macOS | Limited | Uses launchctl |
| Linux | Supported | Uses ipcs, ipcrm |
| Windows | Not Supported | ccbell only supports macOS/Linux |
