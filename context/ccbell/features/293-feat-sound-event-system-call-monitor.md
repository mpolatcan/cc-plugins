# Feature: Sound Event System Call Monitor

Play sounds for system call patterns and security events.

## Summary

Monitor system call activity, security-related syscalls, and audit events, playing sounds for significant system call activity.

## Motivation

- Security monitoring
- Syscall awareness
- Audit trail feedback
- Suspicious activity alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### System Call Events

| Event | Description | Example |
|-------|-------------|---------|
| Execve Called | New process | execve("/bin/sh") |
| Setuid Called | Privilege change | setuid(0) |
| Chroot Called | Root change | chroot("/ jail") |
| Socket Created | Network socket | socket(AF_INET) |

### Configuration

```go
type SystemCallMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchSyscalls    []string          `json:"watch_syscalls"` // "execve", "setuid", "socket"
    WatchProcesses   []string          `json:"watch_processes"]
    SoundOnSyscall   bool              `json:"sound_on_syscall"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 1 default
}

type SystemCallEvent struct {
    ProcessName string
    PID         int
    Syscall     string
    Arguments   []string
    Timestamp   time.Time
}
```

### Commands

```bash
/ccbell:syscall status               # Show syscall status
/ccbell:syscall add execve           # Add syscall to watch
/ccbell:syscall remove execve
/ccbell:syscall sound execve <sound>
/ccbell:syscall test                 # Test syscall sounds
```

### Output

```
$ ccbell:syscall status

=== Sound Event System Call Monitor ===

Status: Enabled
Syscall Sounds: Yes

Watched Syscalls: 3

[1] execve
    Calls/min: 45
    Last Call: 5 sec ago
    Sound: bundled:stop

[2] setuid
    Calls/min: 2
    Last Call: 1 min ago
    Sound: bundled:stop

[3] socket
    Calls/min: 120
    Last Call: 1 sec ago
    Sound: bundled:stop

Recent Events:
  [1] bash: execve (5 sec ago)
       /usr/bin/git push
  [2] sudo: setuid (30 sec ago)
       setuid(0)
  [3] curl: socket (1 min ago)
       socket(AF_INET, SOCK_STREAM)

Syscall Statistics (Last Hour):
  - execve: 2,700 calls
  - socket: 7,200 calls
  - setuid: 120 calls

Sound Settings:
  execve: bundled:stop
  setuid: bundled:stop
  socket: bundled:stop

[Configure] [Add Syscall] [Test All]
```

---

## Audio Player Compatibility

System call monitoring doesn't play sounds directly:
- Monitoring feature using audit tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Call Monitor

```go
type SystemCallMonitor struct {
    config           *SystemCallMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    syscallCount     map[string]int
    syscallLastSeen  map[string]time.Time
}

func (m *SystemCallMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.syscallCount = make(map[string]int)
    m.syscallLastSeen = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemCallMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSyscalls()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemCallMonitor) checkSyscalls() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinSyscalls()
    } else {
        m.checkLinuxSyscalls()
    }
}

func (m *SystemCallMonitor) checkDarwinSyscalls() {
    // Use dtrace or Instruments (limited)
    // Check for security audit events
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'execve' || eventMessage CONTAINS 'setuid'",
        "--last", "1m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseAuditOutput(string(output))
}

func (m *SystemCallMonitor) checkLinuxSyscalls() {
    // Use auditd if available
    cmd := exec.Command("ausearch", "-m", "SYSCALL", "-ts", "recent")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to checking /proc for process syscalls
        m.checkProcSyscalls()
        return
    }

    m.parseAuditOutput(string(output))
}

func (m *SystemCallMonitor) checkProcSyscalls() {
    // Check /proc/*/syscall for suspicious activity
    entries, err := os.ReadDir("/proc")
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        // Skip non-PID directories
        if _, err := strconv.Atoi(entry.Name()); err != nil {
            continue
        }

        syscallFile := filepath.Join("/proc", entry.Name(), "syscall")
        data, err := os.ReadFile(syscallFile)
        if err != nil {
            continue
        }

        parts := strings.Fields(string(data))
        if len(parts) < 2 {
            continue
        }

        syscallNum := parts[0]
        syscallName := m.getSyscallName(syscallNum)

        if m.shouldWatchSyscall(syscallName) {
            m.onSyscallDetected(entry.Name(), syscallName)
        }
    }
}

func (m *SystemCallMonitor) getSyscallName(num string) string {
    // Map syscall number to name
    syscallMap := map[string]string{
        "59": "execve",
        "23": "setuid",
        "41": "socket",
        "42": "connect",
        "2":  "creat",
        "3":  "close",
        "0":  "read",
        "1":  "write",
        "60": "exit",
    }

    if name, ok := syscallMap[num]; ok {
        return name
    }
    return "unknown"
}

func (m *SystemCallMonitor) shouldWatchSyscall(name string) bool {
    if len(m.config.WatchSyscalls) == 0 {
        return true
    }

    for _, watch := range m.config.WatchSyscalls {
        if strings.ToLower(name) == strings.ToLower(watch) {
            return true
        }
    }

    return false
}

func (m *SystemCallMonitor) parseAuditOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse audit event line
        syscall := m.extractSyscallFromAudit(line)
        if syscall != "" && m.shouldWatchSyscall(syscall) {
            m.onSyscallDetected("unknown", syscall)
        }
    }
}

func (m *SystemCallMonitor) extractSyscallFromAudit(line string) string {
    // Look for syscall names in audit output
    syscalls := []string{"execve", "setuid", "socket", "connect", "chroot"}

    for _, syscall := range syscalls {
        if strings.Contains(strings.ToLower(line), syscall) {
            return syscall
        }
    }

    return ""
}

func (m *SystemCallMonitor) onSyscallDetected(pid string, syscall string) {
    if !m.config.SoundOnSyscall {
        return
    }

    // Debounce: don't alert too frequently for same syscall
    key := syscall
    if lastTime := m.syscallLastSeen[key]; lastTime.Add(5*time.Second).After(time.Now()) {
        return
    }
    m.syscallLastSeen[key] = time.Now()

    m.syscallCount[syscall]++

    // Get sound for this syscall
    sound := m.config.Sounds[syscall]
    if sound == "" {
        sound = m.config.Sounds["default"]
    }

    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ausearch | System Tool | Free | Linux audit search |
| /proc/*/syscall | File | Free | Process syscalls |

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
| macOS | Supported | Uses log command |
| Linux | Supported | Uses ausearch, /proc |
| Windows | Not Supported | ccbell only supports macOS/Linux |
