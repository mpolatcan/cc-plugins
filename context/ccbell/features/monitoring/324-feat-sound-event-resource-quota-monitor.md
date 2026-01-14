# Feature: Sound Event Resource Quota Monitor

Play sounds for user and group resource quota limits and violations.

## Summary

Monitor user and group resource quotas, tracking limits and violations, playing sounds for quota events.

## Motivation

- Quota violation alerts
- Resource limit awareness
- User resource tracking
- System administration feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Resource Quota Events

| Event | Description | Example |
|-------|-------------|---------|
| Quota Near | > 80% used | 800/1000 files |
| Quota Exceeded | Limit reached | 1000/1000 files |
| Quota Changed | Limit modified | new hard limit |
| Grace Period | Extension granted | 7 days grace |

### Configuration

```go
type ResourceQuotaMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchUsers      []string          `json:"watch_users"] // "www-data", "postgres"
    WatchPaths      []string          `json:"watch_paths"] // "/home", "/var"
    WarningPercent  int               `json:"warning_percent"` // 80 default
    SoundOnWarning  bool              `json:"sound_on_warning"]
    SoundOnExceeded bool              `json:"sound_on_exceeded"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 3600 default
}

type ResourceQuotaEvent struct {
    User      string
    Path      string
    Resource  string // "files", "disk", "memory"
    Used      int64
    Limit     int64
    Percent   float64
    EventType string // "warning", "exceeded", "changed"
}
```

### Commands

```bash
/ccbell:quota status                  # Show quota status
/ccbell:quota add user                # Add user to watch
/ccbell:quota remove user
/ccbell:quota warning 80              # Set warning threshold
/ccbell:quota sound exceeded <sound>
/ccbell:quota test                    # Test quota sounds
```

### Output

```
$ ccbell:quota status

=== Sound Event Resource Quota Monitor ===

Status: Enabled
Warning: 80%
Exceeded Sounds: Yes

Watched Users: 2
Watched Paths: 2

[1] www-data (/var/www)
    Files: 45,000 / 50,000 (90%)
    Status: WARNING
    Sound: bundled:quota-warning

[2] postgres (/var/lib/postgresql)
    Disk: 10 GB / 100 GB (10%)
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] www-data: Quota Warning (5 min ago)
       Files: 90% used
  [2] postgres: Quota Changed (1 hour ago)
       New limit: 100 GB
  [3] www-data: Quota Exceeded (2 hours ago)
       Files: 100% used

Quota Statistics:
  Users near limit: 2
  Users exceeded: 1

Sound Settings:
  Warning: bundled:quota-warning
  Exceeded: bundled:quota-exceeded

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

Resource quota monitoring doesn't play sounds directly:
- Monitoring feature using quota tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Resource Quota Monitor

```go
type ResourceQuotaMonitor struct {
    config          *ResourceQuotaMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    quotaState      map[string]*QuotaInfo
    lastEventTime   map[string]time.Time
}

type QuotaInfo struct {
    User     string
    Path     string
    Resource string
    Used     int64
    Limit    int64
    Percent  float64
}

func (m *ResourceQuotaMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.quotaState = make(map[string]*QuotaInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ResourceQuotaMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotQuotaState()

    for {
        select {
        case <-ticker.C:
            m.checkQuotaState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ResourceQuotaMonitor) snapshotQuotaState() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinQuotas()
    } else {
        m.snapshotLinuxQuotas()
    }
}

func (m *ResourceQuotaMonitor) snapshotDarwinQuotas() {
    // macOS doesn't have standard quota, check disk usage
    for _, path := range m.config.WatchPaths {
        m.checkDiskUsageForUser(path, "")
    }
}

func (m *ResourceQuotaMonitor) snapshotLinuxQuotas() {
    // Check with repquota for each watched user
    for _, user := range m.config.WatchUsers {
        cmd := exec.Command("quota", "-u", user)
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        m.parseQuotaOutput(string(output), user, "")
    }

    // Check disk usage for paths
    for _, path := range m.config.WatchPaths {
        m.checkDiskUsageForUser(path, "")
    }
}

func (m *ResourceQuotaMonitor) checkQuotaState() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinQuotas()
    } else {
        m.checkLinuxQuotas()
    }
}

func (m *ResourceQuotaMonitor) checkDarwinQuotas() {
    for _, path := range m.config.WatchPaths {
        m.checkDiskUsageForUser(path, "")
    }
}

func (m *ResourceQuotaMonitor) checkLinuxQuotas() {
    // Check user quotas
    for _, user := range m.config.WatchUsers {
        cmd := exec.Command("quota", "-u", user)
        output, err := cmd.Output()
        if err != nil {
            continue
        }

        m.parseQuotaOutput(string(output), user, "")
    }

    // Check paths
    for _, path := range m.config.WatchPaths {
        m.checkDiskUsageForUser(path, "")
    }
}

func (m *ResourceQuotaMonitor) parseQuotaOutput(output string, user string, path string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, user) {
            parts := strings.Fields(line)
            if len(parts) >= 8 {
                // Format varies, look for limits
                // Example: user disk 1024 2048 500 600
                used, _ := strconv.ParseInt(parts[2], 10, 64)
                limit, _ := strconv.ParseInt(parts[3], 10, 64)

                if limit > 0 {
                    percent := float64(used) / float64(limit) * 100
                    key := fmt.Sprintf("%s:%s:files", user, path)

                    lastInfo := m.quotaState[key]
                    m.evaluateQuotaStatus(user, path, "files", used, limit, percent, lastInfo)

                    m.quotaState[key] = &QuotaInfo{
                        User:     user,
                        Path:     path,
                        Resource: "files",
                        Used:     used,
                        Limit:    limit,
                        Percent:  percent,
                    }
                }
            }
        }
    }
}

func (m *ResourceQuotaMonitor) checkDiskUsageForUser(path string, user string) {
    cmd := exec.Command("du", "-s", path)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    parts := strings.Fields(string(output))
    usedKB, _ := strconv.ParseInt(parts[0], 10, 64)

    // Estimate limit based on path
    limitKB := m.estimateQuotaLimit(path)
    if limitKB == 0 {
        return
    }

    usedGB := usedKB / 1024 / 1024
    limitGB := limitKB / 1024 / 1024
    percent := float64(usedGB) / float64(limitGB) * 100

    key := fmt.Sprintf("%s:%s:disk", user, path)

    lastInfo := m.quotaState[key]
    m.evaluateQuotaStatus(user, path, "disk", usedGB, limitGB, percent, lastInfo)

    m.quotaState[key] = &QuotaInfo{
        User:     user,
        Path:     path,
        Resource: "disk",
        Used:     usedGB,
        Limit:    limitGB,
        Percent:  percent,
    }
}

func (m *ResourceQuotaMonitor) estimateQuotaLimit(path string) int64 {
    // This is a simplified estimation
    // In production, would query actual quota limits
    if strings.Contains(path, "/home") {
        return 100 * 1024 * 1024 // 100 GB in KB
    } else if strings.Contains(path, "/var") {
        return 50 * 1024 * 1024 // 50 GB in KB
    }
    return 10 * 1024 * 1024 // 10 GB default
}

func (m *ResourceQuotaMonitor) evaluateQuotaStatus(user string, path string, resource string, used int64, limit int64, percent float64, lastInfo *QuotaInfo) {
    key := fmt.Sprintf("%s:%s:%s", user, path, resource)

    if lastInfo == nil {
        // First check - only alert if already over threshold
        if percent >= float64(m.config.WarningPercent) {
            m.onQuotaWarning(user, path, resource, used, limit, percent)
        }
        return
    }

    // Check if crossed threshold
    if percent >= float64(m.config.WarningPercent) && lastInfo.Percent < float64(m.config.WarningPercent) {
        m.onQuotaWarning(user, path, resource, used, limit, percent)
    } else if percent >= 100 && lastInfo.Percent < 100 {
        m.onQuotaExceeded(user, path, resource, used, limit)
    }
}

func (m *ResourceQuotaMonitor) shouldWatchUser(user string) bool {
    if len(m.config.WatchUsers) == 0 {
        return true
    }

    for _, u := range m.config.WatchUsers {
        if u == user {
            return true
        }
    }

    return false
}

func (m *ResourceQuotaMonitor) onQuotaWarning(user string, path string, resource string, used int64, limit int64, percent float64) {
    if !m.config.SoundOnWarning {
        return
    }

    if !m.shouldWatchUser(user) {
        return
    }

    key := fmt.Sprintf("warning:%s:%s:%s", user, path, resource)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ResourceQuotaMonitor) onQuotaExceeded(user string, path string, resource string, used int64, limit int64) {
    if !m.config.SoundOnExceeded {
        return
    }

    if !m.shouldWatchUser(user) {
        return
    }

    key := fmt.Sprintf("exceeded:%s:%s:%s", user, path, resource)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["exceeded"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *ResourceQuotaMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| quota | System Tool | Free | Linux quota management |
| du | System Tool | Free | Disk usage |

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
| macOS | Supported | Uses du for estimation |
| Linux | Supported | Uses quota, du |
| Windows | Not Supported | ccbell only supports macOS/Linux |
