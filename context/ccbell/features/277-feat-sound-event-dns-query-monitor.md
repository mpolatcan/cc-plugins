# Feature: Sound Event DNS Query Monitor

Play sounds for DNS query events and resolution changes.

## Summary

Monitor DNS queries, resolution failures, and DNS changes, playing sounds for DNS events.

## Motivation

- DNS failure alerts
- Resolution latency feedback
- Domain tracking
- Network debugging

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### DNS Events

| Event | Description | Example |
|-------|-------------|---------|
| Resolution Slow | DNS took > 500ms | Slow query |
| Resolution Failed | NXDOMAIN or timeout | Not found |
| TTL Expired | Record expired | Cache miss |
| New Record | DNS record added | A record created |

### Configuration

```go
type DNSQueryMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchDomains     []string          `json:"watch_domains"`
    LatencyThreshold int               `json:"latency_threshold_ms"` // 500 default
    SoundOnSlow      bool              `json:"sound_on_slow"`
    SoundOnFail      bool              `json:"sound_on_fail"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type DNSQueryEvent struct {
    Domain       string
    QueryType    string // "A", "AAAA", "CNAME", "MX"
    LatencyMs    int
    Result       string // "success", "nxdomain", "timeout"
    TTL          int
}
```

### Commands

```bash
/ccbell:dns status                 # Show DNS status
/ccbell:dns add example.com        # Add domain to watch
/ccbell:dns remove example.com
/ccbell:dns sound slow <sound>
/ccbell:dns sound fail <sound>
/ccbell:dns test                   # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Query Monitor ===

Status: Enabled
Latency Threshold: 500ms
Fail Sounds: Yes

Watched Domains: 3

[1] example.com
    Last Check: 5 min ago
    Latency: 45ms
    TTL: 3600s
    Status: OK
    Sound: bundled:stop

[2] api.example.com
    Last Check: 5 min ago
    Latency: 850ms
    TTL: 300s
    Status: SLOW
    Sound: bundled:stop

[3] old.example.com
    Last Check: 1 hour ago
    Latency: N/A
    TTL: N/A
    Status: FAILED
    Error: NXDOMAIN
    Sound: bundled:stop

Recent Events:
  [1] api.example.com: Slow Query (10 min ago)
       850ms latency
  [2] example.com: Resolved (1 hour ago)
       45ms latency, TTL: 3600s
  [3] old.example.com: Resolution Failed (2 hours ago)
       NXDOMAIN

Sound Settings:
  Slow: bundled:stop
  Fail: bundled:stop
  Resolved: bundled:stop

[Configure] [Add Domain] [Test All]
```

---

## Audio Player Compatibility

DNS monitoring doesn't play sounds directly:
- Monitoring feature using DNS resolution tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### DNS Query Monitor

```go
type DNSQueryMonitor struct {
    config           *DNSQueryMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    domainState      map[string]*DomainStatus
    lastAlertTime    map[string]time.Time
}

type DomainStatus struct {
    Domain      string
    LastCheck   time.Time
    LatencyMs   int
    TTL         int
    Status      string // "ok", "slow", "failed"
}
```

```go
func (m *DNSQueryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.domainState = make(map[string]*DomainStatus)
    m.lastAlertTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DNSQueryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDomains()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSQueryMonitor) checkDomains() {
    for _, domain := range m.config.WatchDomains {
        m.queryDomain(domain)
    }
}

func (m *DNSQueryMonitor) queryDomain(domain string) {
    status := &DomainStatus{
        Domain:    domain,
        LastCheck: time.Now(),
    }

    // Use dig or nslookup
    cmd := exec.Command("dig", "+time=5", "+tries=2", domain)
    start := time.Now()
    output, err := cmd.Output()
    latency := int(time.Since(start).Milliseconds())

    status.LatencyMs = latency

    if err != nil {
        status.Status = "failed"
        m.onDNSFailed(domain)
    } else {
        result := m.parseDigOutput(domain, string(output))
        status.TTL = result.TTL
        status.Status = result.Status

        if result.Status == "slow" {
            m.onDNSSlow(domain, latency)
        }
    }

    m.domainState[domain] = status
}

type DNSResult struct {
    TTL   int
    Status string
}

func (m *DNSQueryMonitor) parseDigOutput(domain string, output string) DNSResult {
    result := DNSResult{Status: "ok"}

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, domain) {
            // Parse answer section
            parts := strings.Fields(line)
            if len(parts) >= 4 {
                // Format: domain. IN A ip_address ttl
                for i, part := range parts {
                    if part == "IN" && i+2 < len(parts) {
                        if ttl, err := strconv.Atoi(parts[i+2]); err == nil {
                            result.TTL = ttl
                        }
                        break
                    }
                }
            }
        }
    }

    // Check for NXDOMAIN
    if strings.Contains(output, "NXDOMAIN") {
        result.Status = "failed"
    } else if strings.Contains(output, "timed out") {
        result.Status = "failed"
    } else if result.TTL == 0 {
        result.Status = "failed"
    }

    return result
}

func (m *DNSQueryMonitor) onDNSSlow(domain string, latency int) {
    if !m.config.SoundOnSlow {
        return
    }

    key := fmt.Sprintf("slow:%s", domain)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DNSQueryMonitor) onDNSFailed(domain string) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", domain)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *DNSQueryMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastAlertTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastAlertTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dig | System Tool | Free | DNS lookup |
| nslookup | System Tool | Free | DNS query |

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
| Windows | Not Supported | ccbell only supports macOS/Linux |
