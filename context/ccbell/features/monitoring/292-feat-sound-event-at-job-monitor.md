# Feature: Sound Event At Job Monitor

Play sounds for at (delayed) job execution events.

## Summary

Monitor at job scheduling and execution, playing sounds for at job events.

## Motivation

- Scheduled task awareness
- One-time job alerts
- Execution feedback
- Schedule tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### At Job Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Scheduled | New at job added | at 14:00 |
| Job Executed | at job ran | backup.sh |
| Job Removed | at job cancelled | atrm |

### Configuration

```go
type AtJobMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchUsers      []string          `json:"watch_users"]
    SoundOnSchedule bool              `json:"sound_on_schedule"]
    SoundOnExecute  bool              `json:"sound_on_execute"]
    SoundOnRemove   bool              `json:"sound_on_remove"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 30 default
}

type AtJobEvent struct {
    User      string
    Command   string
    Schedule  string
    JobID     int
    EventType string // "schedule", "execute", "remove"
}
```

### Commands

```bash
/ccbell:at status                    # Show at job status
/ccbell:at add user                  # Add user to watch
/ccbell:at remove user
/ccbell:at sound schedule <sound>
/ccbell:at sound execute <sound>
/ccbell:at test                      # Test at sounds
```

### Output

```
$ ccbell:at status

=== Sound Event At Job Monitor ===

Status: Enabled
Schedule Sounds: Yes
Execute Sounds: Yes

Watched Users: 2

Queued Jobs: 3

[1] Job ID: 42
    User: user
    Schedule: Thu Jan 16 14:00:00 2025
    Command: /home/user/backup.sh
    Status: PENDING
    Sound: bundled:stop

[2] Job ID: 41
    User: root
    Schedule: Thu Jan 16 12:00:00 2025
    Command: /usr/local/bin/cleanup.sh
    Status: COMPLETED (2 hours ago)
    Exit: 0
    Sound: bundled:stop

[3] Job ID: 40
    User: admin
    Schedule: Thu Jan 16 10:00:00 2025
    Command: /opt/scripts/report.sh
    Status: COMPLETED (4 hours ago)
    Exit: 1
    Sound: bundled:at-fail

Recent Events:
  [1] root: Job Executed (2 hours ago)
       cleanup.sh (Exit: 0)
  [2] admin: Job Executed (4 hours ago)
       report.sh (Exit: 1)
  [3] user: Job Scheduled (1 day ago)
       backup.sh at 14:00

Sound Settings:
  Schedule: bundled:stop
  Execute: bundled:stop
  Remove: bundled:stop

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

At job monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### At Job Monitor

```go
type AtJobMonitor struct {
    config      *AtJobMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    atQueue     map[int]*AtJob
}

type AtJob struct {
    JobID     int
    User      string
    Command   string
    Schedule  string
    Status    string // "pending", "executed", "removed"
}
```

```go
func (m *AtJobMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.atQueue = make(map[int]*AtJob)
    go m.monitor()
}

func (m *AtJobMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Snapshot current queue
    m.snapshotAtQueue()

    for {
        select {
        case <-ticker.C:
            m.checkAtJobs()
        case <-m.stopCh:
            return
        }
    }
}

func (m *AtJobMonitor) snapshotAtQueue() {
    // Get current at jobs
    output, err := exec.Command("atq").Output()
    if err != nil {
        return
    }

    m.parseAtqOutput(string(output))
}

func (m *AtJobMonitor) checkAtJobs() {
    // Get current queue
    output, err := exec.Command("atq").Output()
    if err != nil {
        return
    }

    newQueue := make(map[int]*AtJob)
    m.parseAtqOutputToMap(string(output), newQueue)

    // Compare with last known state
    for jobID, job := range newQueue {
        if m.atQueue[jobID] == nil {
            // New job
            m.atQueue[jobID] = job
            m.onJobScheduled(job)
        }
    }

    // Check for executed jobs (not in queue anymore)
    for jobID, job := range m.atQueue {
        if newQueue[jobID] == nil && job.Status == "pending" {
            job.Status = "executed"
            m.onJobExecuted(job)
        }
    }

    m.atQueue = newQueue
}

func (m *AtJobMonitor) parseAtqOutput(output string) {
    m.parseAtqOutputToMap(output, m.atQueue)
}

func (m *AtJobMonitor) parseAtqOutputToMap(output string, queue map[int]*AtJob) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Format: "jobid date time queue user"
        parts := strings.Fields(line)
        if len(parts) < 5 {
            continue
        }

        jobID, err := strconv.Atoi(parts[0])
        if err != nil {
            continue
        }

        user := parts[len(parts)-1]

        // Check user filter
        if len(m.config.WatchUsers) > 0 {
            found := false
            for _, watchUser := range m.config.WatchUsers {
                if user == watchUser {
                    found = true
                    break
                }
            }
            if !found {
                continue
            }
        }

        // Get command for this job
        cmd := exec.Command("at", "-c", strconv.Itoa(jobID))
        cmdOutput, err := cmd.Output()
        var command string
        if err == nil {
            command = m.extractAtCommand(string(cmdOutput))
        }

        schedule := strings.Join(parts[1:4], " ")

        queue[jobID] = &AtJob{
            JobID:    jobID,
            User:     user,
            Command:  command,
            Schedule: schedule,
            Status:   "pending",
        }
    }
}

func (m *AtJobMonitor) extractAtCommand(output string) string {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "command") {
            parts := strings.SplitN(line, "=", 2)
            if len(parts) >= 2 {
                return strings.TrimSpace(parts[1])
            }
        }
    }
    return ""
}

func (m *AtJobMonitor) onJobScheduled(job *AtJob) {
    if !m.config.SoundOnSchedule {
        return
    }

    sound := m.config.Sounds["schedule"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *AtJobMonitor) onJobExecuted(job *AtJob) {
    if !m.config.SoundOnExecute {
        return
    }

    sound := m.config.Sounds["execute"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *AtJobMonitor) onJobRemoved(jobID int) {
    if !m.config.SoundOnRemove {
        return
    }

    sound := m.config.Sounds["remove"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| at | System Tool | Free | Job scheduling |
| atq | System Tool | Free | Queue listing |

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
| macOS | Supported | Uses at, atq |
| Linux | Supported | Uses at, atq |
| Windows | Not Supported | ccbell only supports macOS/Linux |
