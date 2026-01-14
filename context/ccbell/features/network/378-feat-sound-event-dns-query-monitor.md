# Feature: Sound Event DNS Query Monitor

Play sounds for DNS resolution failures, slow queries, and domain changes.

## Summary

Monitor DNS queries, resolution times, and domain record changes, playing sounds for DNS events.

## Motivation

- Network troubleshooting
- DNS failure alerts
- Performance monitoring
- Domain change detection
- Connectivity awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### DNS Query Events

| Event | Description | Example |
|-------|-------------|---------|
| Resolution Failed | DNS lookup failed | NXDOMAIN |
| Slow Query | Resolution > threshold | > 500ms |
| TTL Warning | Record expires soon | TTL < 60s |
| IP Changed | A record updated | New IP |
| Domain Invalid | Invalid domain | format error |

### Configuration

```go
type DNSQueryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDomains      []string          `json:"watch_domains"` // "example.com", "*"
    QueryTimeout      int               `json:"query_timeout_ms"` // 5000 default
    SlowThreshold     int               `json:"slow_threshold_ms"` // 500 default
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnSlow       bool              `json:"sound_on_slow"`
    SoundOnChange     bool              `json:"sound_on_change"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:dns status                    # Show DNS status
/ccbell:dns add example.com           # Add domain to watch
/ccbell:dns remove example.com
/ccbell:dns threshold 500             # Set slow query threshold
/ccbell:dns sound fail <sound>
/ccbell:dns test                      # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Query Monitor ===

Status: Enabled
Fail Sounds: Yes
Slow Sounds: Yes
Change Sounds: Yes

Slow Query Threshold: 500ms
Watched Domains: 4

Monitored Domains:

[1] example.com
    IP: 93.184.216.34
    TTL: 86400s
    Last Check: 5 min ago
    Avg Query Time: 45ms
    Sound: bundled:dns-example

[2] github.com
    IP: 140.82.113.4
    TTL: 60s
    Last Check: 5 min ago
    Avg Query Time: 120ms
    Sound: bundled:dns-github

[3] google.com
    IP: 142.250.185.206
    TTL: 300s
    Last Check: 5 min ago
    Avg Query Time: 35ms
    Sound: bundled:dns-google

[4] internal.local
    Status: FAILED
    Error: NXDOMAIN
    Last Check: 1 hour ago
    Sound: bundled:dns-internal

Recent Events:
  [1] internal.local: Resolution Failed (1 hour ago)
       Error: NXDOMAIN
  [2] github.com: TTL Warning (2 hours ago)
       TTL: 60s < threshold
  [3] example.com: IP Changed (1 day ago)
       93.184.216.34 -> 93.184.216.34

DNS Statistics:
  Total Queries: 1000
  Failed: 2
  Slow Queries: 5
  IP Changes: 1

Sound Settings:
  Fail: bundled:dns-fail
  Slow: bundled:dns-slow
  Change: bundled:dns-change

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

### DNS Query Monitor

```go
type DNSQueryMonitor struct {
    config          *DNSQueryMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    domainState     map[string]*DomainInfo
    lastEventTime   map[string]time.Time
}

type DomainInfo struct {
    Domain       string
    IP           string
    TTL          int
    QueryTime    int64 // milliseconds
    LastCheck    time.Time
    Failed       bool
    Error        string
}

func (m *DNSQueryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.domainState = make(map[string]*DomainInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DNSQueryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDomainState()

    for {
        select {
        case <-ticker.C:
            m.checkDomainState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSQueryMonitor) snapshotDomainState() {
    for _, domain := range m.config.WatchDomains {
        m.checkDomain(domain)
    }
}

func (m *DNSQueryMonitor) checkDomainState() {
    for _, domain := range m.config.WatchDomains {
        m.checkDomain(domain)
    }
}

func (m *DNSQueryMonitor) checkDomain(domain string) {
    result := m.queryDNS(domain)
    if result == nil {
        return
    }

    result.Domain = domain
    result.LastCheck = time.Now()

    lastInfo := m.domainState[domain]
    if lastInfo == nil {
        m.domainState[domain] = result
        return
    }

    // Check for resolution failure
    if result.Failed && !lastInfo.Failed {
        m.onResolutionFailed(domain, result)
    }

    // Check for recovery
    if !result.Failed && lastInfo.Failed {
        m.onResolutionRecovered(domain, result)
    }

    // Check for slow query
    if !result.Failed && result.QueryTime > int64(m.config.SlowThreshold) {
        if lastInfo.Failed || result.QueryTime > lastInfo.QueryTime+100 {
            m.onSlowQuery(domain, result)
        }
    }

    // Check for IP change
    if !result.Failed && !lastInfo.Failed && result.IP != lastInfo.IP {
        m.onIPChanged(domain, result, lastInfo)
    }

    // Check for TTL warning
    if result.TTL < 60 && lastInfo.TTL >= 60 {
        m.onTTLWarning(domain, result)
    }

    m.domainState[domain] = result
}

func (m *DNSQueryMonitor) queryDNS(domain string) *DomainInfo {
    // Use dig with time tracking
    cmd := exec.Command("dig", "+time=5", "+tries=1", "+short", domain)
    output, err := cmd.Output()

    info := &DomainInfo{}

    if err != nil {
        info.Failed = true
        info.Error = err.Error()
        return info
    }

    ip := strings.TrimSpace(string(output))
    if ip == "" {
        info.Failed = true
        info.Error = "No answer"
        return info
    }

    info.IP = ip
    info.Failed = false

    // Get TTL
    ttlCmd := exec.Command("dig", "+time=5", "+tries=1", "+noall", "+answer", "+ttlid", domain)
    ttlOutput, _ := ttlCmd.Output()

    re := regexp.MustEach(`\s(\d+)\s+`)
    // Parse TTL from output

    return info
}

func (m *DNSQueryMonitor) onResolutionFailed(domain string, info *DomainInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", domain)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *DNSQueryMonitor) onResolutionRecovered(domain string, info *DomainInfo) {
    // Optional: sound when DNS recovers
}

func (m *DNSQueryMonitor) onSlowQuery(domain string, info *DomainInfo) {
    if !m.config.SoundOnSlow {
        return
    }

    key := fmt.Sprintf("slow:%s", domain)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSQueryMonitor) onIPChanged(domain string, info *DomainInfo, lastInfo *DomainInfo) {
    if !m.config.SoundOnChange {
        return
    }

    key := fmt.Sprintf("change:%s", domain)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSQueryMonitor) onTTLWarning(domain string, info *DomainInfo) {
    // Optional: sound for low TTL
}

func (m *DNSQueryMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| dig | System Tool | Free | DNS lookup (bind-utils) |
| nslookup | System Tool | Free | DNS lookup |

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
