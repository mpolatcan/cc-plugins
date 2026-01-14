# Feature: Sound Event SELinux Event Monitor

Play sounds for SELinux policy violations and enforcement events.

## Summary

Monitor SELinux events including denials, policy loads, and enforcement changes, playing sounds for security events.

## Motivation

- Security monitoring
- Policy violation alerts
- Compliance awareness
- Access control feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### SELinux Events

| Event | Description | Example |
|-------|-------------|---------|
| Access Denied | SELinux blocked | AVC denial |
| Policy Loaded | New policy applied | semodule |
| Enforcing Change | Mode changed | setenforce 0 |
| Context Change | Label changed | chcon |

### Configuration

```go
type SELinuxMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchContexts   []string          `json:"watch_contexts"] // "httpd_t", "mysqld_t"
    SoundOnDeny     bool              `json:"sound_on_deny"]
    SoundOnPolicy   bool              `json:"sound_on_policy"]
    SoundOnEnforce  bool              `json:"sound_on_enforce"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 10 default
}

type SELinuxEvent struct {
    Context    string
    Source     string
    Target     string
    Action     string
    Result     string // "denied", "granted"
    EventType  string
}
```

### Commands

```bash
/ccbell:selinux status                # Show SELinux status
/ccbell:selinux add httpd_t           # Add context to watch
/ccbell:selinux remove httpd_t
/ccbell:selinux sound deny <sound>
/ccbell:selinux sound policy <sound>
/ccbell:selinux test                  # Test SELinux sounds
```

### Output

```
$ ccbell:selinux status

=== Sound Event SELinux Monitor ===

Status: Enabled
Mode: Enforcing
Deny Sounds: Yes
Policy Sounds: Yes

Watched Contexts: 2

[1] httpd_t
    Denials: 5
    Last Denial: 5 min ago
    Sound: bundled:selinux-deny

[2] mysqld_t
    Denials: 2
    Last Denial: 1 hour ago
    Sound: bundled:stop

Recent Events:
  [1] httpd_t: Access Denied (5 min ago)
       httpd_t -> var_log_t (write)
  [2] mysqld_t: Access Denied (1 hour ago)
       mysqld_t -> shadow_t (read)
  [3] Policy Loaded (2 hours ago)
       New policy installed

SELinux Statistics (24h):
  Total denials: 7
  Enforcing changes: 0

Sound Settings:
  Deny: bundled:selinux-deny
  Policy: bundled:stop
  Enforce: bundled:selinux-enforce

[Configure] [Add Context] [Test All]
```

---

## Audio Player Compatibility

SELinux monitoring doesn't play sounds directly:
- Monitoring feature using SELinux tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SELinux Event Monitor

```go
type SELinuxMonitor struct {
    config           *SELinuxMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    selinuxState     *SELinuxState
    lastEventTime    map[string]time.Time
}

type SELinuxState struct {
    Mode        string // "Enforcing", "Permissive", "Disabled"
    PolicyLoaded string
    DenyCount   int
}

func (m *SELinuxMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.selinuxState = &SELinuxState{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SELinuxMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSELinuxState()

    for {
        select {
        case <-ticker.C:
            m.checkSELinuxEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SELinuxMonitor) snapshotSELinuxState() {
    if runtime.GOOS != "linux" {
        return
    }

    // Check SELinux status
    m.checkSELinuxStatus()

    // Check for denials
    m.checkAVCDenials()
}

func (m *SELinuxMonitor) checkSELinuxStatus() {
    // Get current mode
    cmd := exec.Command("getenforce")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    mode := strings.TrimSpace(string(output))
    if mode != m.selinuxState.Mode {
        m.onEnforceModeChange(mode, m.selinuxState.Mode)
        m.selinuxState.Mode = mode
    }
}

func (m *SELinuxMonitor) checkAVCDenials() {
    // Check audit logs for AVC denials
    logFile := "/var/log/audit/audit.log"
    data, err := os.ReadFile(logFile)
    if err != nil {
        // Try syslog
        data, err = os.ReadFile("/var/log/syslog")
        if err != nil {
            return
        }
    }

    m.parseAuditLog(string(data))
}

func (m *SELinuxMonitor) checkSELinuxEvents() {
    if runtime.GOOS != "linux" {
        return
    }

    // Check mode changes
    m.checkSELinuxStatus()

    // Check for new denials
    m.checkAVCDenials()
}

func (m *SELinuxMonitor) parseAuditLog(log string) {
    recentTime := time.Now().Add(-time.Duration(m.config.PollInterval) * time.Second)
    lines := strings.Split(log, "\n")

    for _, line := range lines {
        if !strings.Contains(line, "AVC") {
            continue
        }

        event := m.parseAVCLine(line)
        if event == nil {
            continue
        }

        // Check if we should watch this context
        if m.shouldWatchContext(event.Context) {
            m.onAccessDenied(event)
        }
    }
}

func (m *SELinuxMonitor) parseAVCLine(line string) *SELinuxEvent {
    // Parse audit log line format
    // type=AVC msg=audit(1234567890.123:456): avc:  denied  { write } for pid=1234 comm="httpd" name="log" dev="sda1" ino=12345 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:var_log_t:s0 tclass=file

    event := &SELinuxEvent{}

    // Extract source context
    scontextRe := regexp.MustCompile(`scontext=([^:]+:[^:]+:[^:]+)`)
    if match := scontextRe.FindStringSubmatch(line); match != nil {
        event.Context = match[1]
    }

    // Extract action
    if strings.Contains(line, "denied") {
        event.Result = "denied"
        event.EventType = "deny"
    } else {
        event.Result = "granted"
        event.EventType = "allow"
    }

    // Extract target class
    tclassRe := regexp.MustCompile(`tclass=([^ ]+)`)
    if match := tclassRe.FindStringSubmatch(line); match != nil {
        event.Target = match[1]
    }

    return event
}

func (m *SELinuxMonitor) shouldWatchContext(context string) bool {
    if len(m.config.WatchContexts) == 0 {
        return true
    }

    for _, ctx := range m.config.WatchContexts {
        if strings.Contains(context, ctx) {
            return true
        }
    }

    return false
}

func (m *SELinuxMonitor) onAccessDenied(event *SELinuxEvent) {
    if !m.config.SoundOnDeny {
        return
    }

    key := fmt.Sprintf("deny:%s", event.Context)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["deny"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }

    m.selinuxState.DenyCount++
}

func (m *SELinuxMonitor) onPolicyLoaded() {
    if !m.config.SoundOnPolicy {
        return
    }

    key := "policy:loaded"
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["policy"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SELinuxMonitor) onEnforceModeChange(newMode string, oldMode string) {
    if !m.config.SoundOnEnforce {
        return
    }

    key := fmt.Sprintf("enforce:%s->%s", oldMode, newMode)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["enforce"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SELinuxMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| getenforce | System Tool | Free | SELinux mode |
| /var/log/audit/audit.log | File | Free | Audit logs |

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
| macOS | Not Supported | No SELinux on macOS |
| Linux | Supported | Uses getenforce, audit.log |
| Windows | Not Supported | ccbell only supports macOS/Linux |
