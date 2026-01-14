# Feature: Sound Event SSH Connection Monitor

Play sounds for SSH connection attempts, successful logins, and security alerts.

## Summary

Monitor SSH connections for login attempts, connection failures, and brute-force detection, playing sounds for SSH events.

## Motivation

- SSH security awareness
- Login tracking
- Brute-force detection
- Connection feedback
- Security monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSH Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Login Successful | User logged in | user@host |
| Login Failed | Auth failed | invalid password |
| Brute Force | Multiple failures | 10+ attempts |
| Connection Lost | Session dropped | disconnect |
| Root Login | Root access | sudo access |
| New Host | First connection | unknown host |

### Configuration

```go
type SSHConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchUsers        []string          `json:"watch_users"` // "root", "admin", "*"
    WatchHosts        []string          `json:"watch_hosts"` // specific IPs
    BruteForceThreshold int             `json:"brute_force_threshold"` // 5 default
    SoundOnLogin      bool              `json:"sound_on_login"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnBruteForce bool              `json:"sound_on_brute_force"`
    SoundOnRoot       bool              `json:"sound_on_root"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:ssh status                  # Show SSH status
/ccbell:ssh add root                # Add user to watch
/ccbell:ssh brute 5                 # Set brute force threshold
/ccbell:ssh sound login <sound>
/ccbell:ssh sound failed <sound>
/ccbell:ssh test                    # Test SSH sounds
```

### Output

```
$ ccbell:ssh status

=== Sound Event SSH Connection Monitor ===

Status: Enabled
Brute Force Threshold: 5 attempts
Watch Users: *

SSH Connection Status:

[1] Active Sessions: 3
    - user@192.168.1.100 (1 hour)
    - admin@10.0.0.50 (45 min)
    - root@192.168.1.105 (5 min) *** ROOT ***

[2] Recent Logins (Last 24h):
    - user@192.168.1.100 (Today 09:00)
    - admin@10.0.0.50 (Today 08:45)
    - root@192.168.1.105 (Today 10:00)

[3] Failed Attempts:
    - 3 attempts from 45.33.22.11 (Today 02:00)
    - 2 attempts from 123.45.67.89 (Yesterday)

Security Alerts:

  [1] Root Login (5 min ago)
       root@192.168.1.105
       Method: Password
       Sound: bundled:ssh-root *** WARNING ***
  [2] Brute Force Blocked (8 hours ago)
       45.33.22.11 (5 attempts)
       Sound: bundled:ssh-brute *** BLOCKED ***
  [3] Failed Login (Yesterday)
       invalid user from 89.123.45.67
       Sound: bundled:ssh-failed

SSH Statistics:
  Total Logins Today: 15
  Failed Attempts: 5
  Active Sessions: 3
  Root Logins: 2

Sound Settings:
  Login: bundled:ssh-login
  Failed: bundled:ssh-failed
  Brute Force: bundled:ssh-brute
  Root: bundled:ssh-root

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

SSH monitoring doesn't play sounds directly:
- Monitoring feature using last/lastlog/ausearch
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSH Connection Monitor

```go
type SSHConnectionMonitor struct {
    config          *SSHConnectionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    connectionState map[string]*SSHConnectionInfo
    lastEventTime   map[string]time.Time
    failedAttempts  map[string]int
}

type SSHConnectionInfo struct {
    User       string
    Host       string
    SourceIP   string
    LoginTime  time.Time
    Method     string
    Status     string // "logged_in", "failed", "disconnected"
}

func (m *SSHConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.connectionState = make(map[string]*SSHConnectionInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.failedAttempts = make(map[string]int)
    go m.monitor()
}

func (m *SSHConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotConnectionState()

    for {
        select {
        case <-ticker.C:
            m.checkConnectionState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSHConnectionMonitor) snapshotConnectionState() {
    m.checkConnectionState()
}

func (m *SSHConnectionMonitor) checkConnectionState() {
    // Check recent logins
    m.checkRecentLogins()

    // Check active sessions
    m.checkActiveSessions()

    // Check failed attempts
    m.checkFailedAttempts()
}

func (m *SSHConnectionMonitor) checkRecentLogins() {
    cmd := exec.Command("last", "-n", "20", "-i")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || strings.HasPrefix(line, "wtmp") {
            continue
        }

        conn := m.parseLastLog(line)
        if conn == nil {
            continue
        }

        if !m.shouldWatchUser(conn.User) {
            continue
        }

        key := fmt.Sprintf("%s:%s:%s", conn.User, conn.SourceIP, conn.LoginTime.Unix())

        if _, exists := m.connectionState[key]; !exists {
            m.connectionState[key] = conn

            if conn.Status == "logged_in" && m.config.SoundOnLogin {
                m.onSSHSuccessful(conn)
            } else if conn.Status == "failed" && m.config.SoundOnFailed {
                m.onSSHFailed(conn)
            }
        }
    }
}

func (m *SSHConnectionMonitor) parseLastLog(line string) *SSHConnectionInfo {
    // Parse "last" output format:
    // username pts/0 192.168.1.100 Thu Jan 14 09:00 - 10:00 (01:00)
    // failed password for root from 45.33.22.11 port 22

    parts := strings.Fields(line)
    if len(parts) < 3 {
        return nil
    }

    conn := &SSHConnectionInfo{}

    // Check for failed attempt
    if strings.HasPrefix(line, "Failed password") ||
       strings.HasPrefix(line, "Invalid user") {
        conn.Status = "failed"

        // Extract username
        if strings.HasPrefix(line, "Invalid user") {
            userRe := regexp.MustEach(`Invalid user (\S+)`)
            matches := userRe.FindStringSubmatch(line)
            if len(matches) >= 2 {
                conn.User = matches[1]
            }
        } else {
            userRe := regexp.MustEach(`for (\S+)`)
            matches := userRe.FindStringSubmatch(line)
            if len(matches) >= 2 {
                conn.User = matches[1]
            }
        }

        // Extract IP
        ipRe := regexp.MustEach(`from ([0-9.]+)`)
        matches := ipRe.FindStringSubmatch(line)
        if len(matches) >= 2 {
            conn.SourceIP = matches[1]
        }

        return conn
    }

    // Successful login
    conn.User = parts[0]
    conn.Status = "logged_in"

    // Get timestamp (parts[3-5] are day, month, date)
    // Skip for now - focus on recent events

    // Extract IP if present
    if strings.Contains(parts[2], ".") {
        conn.SourceIP = parts[2]
    }

    return conn
}

func (m *SSHConnectionMonitor) checkActiveSessions() {
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) >= 4 {
            user := parts[0]
            if !m.shouldWatchUser(user) {
                continue
            }

            // Check for root
            if user == "root" && m.config.SoundOnRoot {
                m.onRootLogin(user)
            }
        }
    }
}

func (m *SSHConnectionMonitor) checkFailedAttempts() {
    // Use ausearch for audit logs
    cmd := exec.Command("ausearch", "-m", "SSH_EVENT", "-ts", "recent")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    failedFromIP := make(map[string]int)

    for _, line := range lines {
        if strings.Contains(line, "failure") ||
           strings.Contains(line, "Failed") {
            ipRe := regexp.MustEach(`([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})`)
            matches := ipRe.FindStringSubmatch(line)
            if len(matches) >= 1 {
                failedFromIP[matches[1]]++
            }
        }
    }

    // Check for brute force attempts
    for ip, count := range failedFromIP {
        if count >= m.config.BruteForceThreshold {
            if m.config.SoundOnBruteForce {
                m.onBruteForce(ip, count)
            }
        }
    }
}

func (m *SSHConnectionMonitor) shouldWatchUser(user string) bool {
    if len(m.config.WatchUsers) == 0 {
        return true
    }

    for _, u := range m.config.WatchUsers {
        if u == "*" || user == u {
            return true
        }
    }

    return false
}

func (m *SSHConnectionMonitor) onSSHSuccessful(conn *SSHConnectionInfo) {
    // Skip if this was a previous session
    if time.Since(conn.LoginTime) > time.Duration(m.config.PollInterval)*time.Second {
        return
    }

    key := fmt.Sprintf("login:%s:%s", conn.User, conn.SourceIP)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["login"]
        if sound != "" {
            volume := 0.3
            if conn.User == "root" {
                volume = 0.4
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *SSHConnectionMonitor) onSSHFailed(conn *SSHConnectionInfo) {
    key := fmt.Sprintf("failed:%s:%s", conn.User, conn.SourceIP)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }

    // Track for brute force detection
    m.failedAttempts[conn.SourceIP]++
    if m.failedAttempts[conn.SourceIP] >= m.config.BruteForceThreshold {
        m.onBruteForce(conn.SourceIP, m.failedAttempts[conn.SourceIP])
    }
}

func (m *SSHConnectionMonitor) onBruteForce(ip string, attempts int) {
    key := fmt.Sprintf("brute:%s", ip)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["brute_force"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSHConnectionMonitor) onRootLogin(user string) {
    key := "root:login"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["root"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSHConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| last | System Tool | Free | Login history |
| who | System Tool | Free | Current users |
| ausearch | System Tool | Free | Audit log search |

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
| macOS | Supported | Uses last, who |
| Linux | Supported | Uses last, who, ausearch |

# Feature: Sound Event DNS Resolution Monitor

Play sounds for DNS resolution failures, high latency, and domain changes.

## Summary

Monitor DNS resolution for failures, slow queries, and domain changes, playing sounds for DNS events.

## Motivation

- DNS awareness
- Resolution failure alerts
- Latency monitoring
- Domain change detection
- Network health

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### DNS Resolution Events

| Event | Description | Example |
|-------|-------------|---------|
| Resolution Failed | DNS lookup failed | NXDOMAIN |
| High Latency | Query > threshold | > 500ms |
| Slow Server | Server slow | > 200ms |
| TTL Low | Record expiring | < 300s |
| Server Changed | DNS server switch | 8.8.8.8 |
| New Record | New DNS record | A record |

### Configuration

```go
type DNSResolutionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDomains      []string          `json:"watch_domains"` // "example.com", "*"
    WatchServers      []string          `json:"watch_servers"` // "8.8.8.8", "1.1.1.1"
    LatencyThreshold  int               `json:"latency_threshold_ms"` // 500 default
    TTLWarning        int               `json:"ttl_warning_seconds"` // 300 default
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnSlow       bool              `json:"sound_on_slow"`
    SoundOnTTL        bool              `json:"sound_on_ttl"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:dns status                  # Show DNS status
/ccbell:dns add example.com         # Add domain to watch
/ccbell:dns latency 500             # Set latency threshold
/ccbell:dns sound failed <sound>
/ccbell:dns test                    # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Resolution Monitor ===

Status: Enabled
Latency Threshold: 500ms
TTL Warning: 300s

DNS Resolution Status:

[1] example.com
    Status: RESOLVED
    IP: 93.184.216.34
    Latency: 45ms
    TTL: 21600s (6 hours)
    DNS Server: 8.8.8.8
    Sound: bundled:dns-example

[2] api.example.com
    Status: SLOW *** SLOW ***
    IP: 104.21.55.1
    Latency: 850ms *** HIGH LATENCY ***
    TTL: 300s (5 min)
    DNS Server: 1.1.1.1
    Sound: bundled:dns-api *** WARNING ***

[3] old.example.com
    Status: FAILED *** FAILED ***
    Error: NXDOMAIN
    TTL: -
    DNS Server: 8.8.8.8
    Sound: bundled:dns-old *** ERROR ***

[4] internal.company.local
    Status: RESOLVED
    IP: 10.0.0.5
    Latency: 2ms
    TTL: 3600s (1 hour)
    DNS Server: 10.0.0.1
    Sound: bundled:dns-internal

DNS Server Status:

  8.8.8.8: 45ms (Normal)
  1.1.1.1: 850ms (Slow)
  10.0.0.1: 2ms (Normal)

Recent DNS Events:
  [1] api.example.com: High Latency (5 min ago)
       850ms > 500ms threshold
       Sound: bundled:dns-slow
  [2] old.example.com: Resolution Failed (1 hour ago)
       NXDOMAIN
       Sound: bundled:dns-failed
  [3] example.com: TTL Warning (2 hours ago)
       300s remaining
       Sound: bundled:dns-ttl

DNS Statistics:
  Total Domains: 4
  Resolved: 3
  Failed: 1
  Avg Latency: 299ms

Sound Settings:
  Failed: bundled:dns-failed
  Slow: bundled:dns-slow
  TTL: bundled:dns-ttl
  Server: bundled:dns-server

[Configure] [Add Domain] [Test All]
```

---

## Audio Player Compatibility

DNS monitoring doesn't play sounds directly:
- Monitoring feature using dig/nslookup
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### DNS Resolution Monitor

```go
type DNSResolutionMonitor struct {
    config          *DNSResolutionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    dnsState        map[string]*DNSResolutionInfo
    lastEventTime   map[string]time.Time
}

type DNSResolutionInfo struct {
    Domain     string
    IP         string
    Status     string // "resolved", "failed", "slow", "unknown"
    Latency    time.Duration
    TTL        int
    Server     string
    LastCheck  time.Time
}

func (m *DNSResolutionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.dnsState = make(map[string]*DNSResolutionInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DNSResolutionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDNSState()

    for {
        select {
        case <-ticker.C:
            m.checkDNSState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSResolutionMonitor) snapshotDNSState() {
    m.checkDNSState()
}

func (m *DNSResolutionMonitor) checkDNSState() {
    for _, domain := range m.config.WatchDomains {
        info := m.resolveDomain(domain)
        if info != nil {
            m.processDNSStatus(info)
        }
    }
}

func (m *DNSResolutionMonitor) resolveDomain(domain string) *DNSResolutionInfo {
    info := &DNSResolutionInfo{
        Domain:    domain,
        LastCheck: time.Now(),
    }

    // Use dig for resolution
    cmd := exec.Command("dig", "+short", "+time=5", domain)
    start := time.Now()
    output, err := cmd.Output()
    info.Latency = time.Since(start)

    if err != nil {
        info.Status = "failed"
        return info
    }

    ip := strings.TrimSpace(string(output))
    if ip == "" {
        info.Status = "failed"
        return info
    }

    info.IP = ip
    info.Status = "resolved"

    // Check if slow
    if info.Latency.Milliseconds() >= int64(m.config.LatencyThreshold) {
        info.Status = "slow"
    }

    // Get TTL
    cmd = exec.Command("dig", "+ttlid", domain)
    ttluid, _ := cmd.Output()

    ttlRe := regexp.MustEach(`IN\s+A\s+([0-9]+)`)
    matches := ttlRe.FindStringSubmatch(string(ttluid))
    if len(matches) >= 2 {
        info.TTL, _ = strconv.Atoi(matches[1])
    }

    return info
}

func (m *DNSResolutionMonitor) processDNSStatus(info *DNSResolutionInfo) {
    lastInfo := m.dnsState[info.Domain]

    if lastInfo == nil {
        m.dnsState[info.Domain] = info
        if info.Status == "failed" && m.config.SoundOnFailed {
            m.onDNSFailed(info)
        } else if info.Status == "slow" && m.config.SoundOnSlow {
            m.onDNSSlow(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "failed":
            if m.config.SoundOnFailed {
                m.onDNSFailed(info)
            }
        case "slow":
            if m.config.SoundOnSlow {
                m.onDNSSlow(info)
            }
        case "resolved":
            if lastInfo.Status == "failed" {
                // DNS recovered
            }
        }
    }

    // Check for TTL warning
    if info.TTL > 0 && info.TTL <= m.config.TTLWarning {
        if lastInfo.TTL == 0 || lastInfo.TTL > m.config.TTLWarning {
            if m.config.SoundOnTTL {
                m.onTTLWarning(info)
            }
        }
    }

    // Check for IP changes
    if info.IP != lastInfo.IP && info.IP != "" && lastInfo.IP != "" {
        // Domain IP changed
    }

    m.dnsState[info.Domain] = info
}

func (m *DNSResolutionMonitor) onDNSFailed(info *DNSResolutionInfo) {
    key := fmt.Sprintf("failed:%s", info.Domain)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DNSResolutionMonitor) onDNSSlow(info *DNSResolutionInfo) {
    key := fmt.Sprintf("slow:%s", info.Domain)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSResolutionMonitor) onTTLWarning(info *DNSResolutionInfo) {
    key := fmt.Sprintf("ttl:%s", info.Domain)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["ttl"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *DNSResolutionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| dig | System Tool | Free | DNS lookup tool |
| nslookup | System Tool | Free | DNS lookup (alternative) |

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
| macOS | Supported | Uses dig, nslookup |
| Linux | Supported | Uses dig, nslookup |
