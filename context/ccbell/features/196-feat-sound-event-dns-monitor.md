# Feature: Sound Event DNS Monitor

Play sounds when DNS resolution changes.

## Summary

Play sounds when DNS queries succeed, fail, or return specific results.

## Motivation

- Network debugging
- DNS change alerts
- Server availability

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
| Lookup Success | Domain resolved | google.com found |
| Lookup Failed | Domain not found | NXDOMAIN |
| Slow Query | High latency | > 500ms |
| IP Changed | IP address changed | New IP returned |

### Configuration

```go
type DNSMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    CheckInterval int              `json:"check_interval_sec"` // 60 default
    WatchDomains  []*DomainWatch   `json:"watch_domains"`
    Sounds        map[string]string `json:"sounds"`
}

type DomainWatch struct {
    Domain      string  `json:"domain"`
    Resolver    string  `json:"resolver,omitempty"` // "8.8.8.8" or system default
    CheckIP     string  `json:"check_ip,omitempty"` // Expected IP
    LatencyThreshold int `json:"latency_threshold_ms"`
    Sound       string  `json:"sound"`
    Enabled     bool    `json:"enabled"`
}

type DNSResult struct {
    Domain     string
    ResolvedIP string
    LatencyMs  float64
    Error      string
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:dns status                  # Show DNS status
/ccbell:dns add google.com          # Watch domain
/ccbell:dns add google.com --resolver 8.8.8.8
/ccbell:dns add google.com --check-ip 142.250.185.206
/ccbell:dns remove google.com
/ccbell:dns sound success <sound>
/ccbell:dns sound failed <sound>
/ccbell:dns enable                  # Enable DNS monitoring
/ccbell:dns disable                 # Disable DNS monitoring
/ccbell:dns test                    # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Monitor ===

Status: Enabled
Check Interval: 60s

Watched Domains: 3

[1] google.com
    Resolver: 8.8.8.8
    Expected IP: 142.250.185.206
    Current: 142.250.185.206
    Latency: 12ms
    Status: OK
    Sound: bundled:stop
    [Edit] [Remove]

[2] github.com
    Resolver: system
    Expected IP: -
    Current: 140.82.113.4
    Latency: 45ms
    Status: OK
    Sound: bundled:stop
    [Edit] [Remove]

[3] broken.example.com
    Resolver: 8.8.8.8
    Expected IP: -
    Current: -
    Status: FAILED (NXDOMAIN)
    Sound: bundled:stop
    [Edit] [Remove]

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

DNS monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### DNS Monitor

```go
type DNSMonitor struct {
    config   *DNSMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastResults map[string]*DNSResult
}

func (m *DNSMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastResults = make(map[string]*DNSResult)
    go m.monitor()
}

func (m *DNSMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
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

func (m *DNSMonitor) checkDomains() {
    for _, watch := range m.config.WatchDomains {
        if !watch.Enabled {
            continue
        }

        result := m.resolveDomain(watch)
        m.evaluateResult(watch, result)
        m.lastResults[watch.Domain] = result
    }
}

func (m *DNSMonitor) resolveDomain(watch *DomainWatch) *DNSResult {
    start := time.Now()

    var r *net.Resolver
    if watch.Resolver != "" {
        r = &net.Resolver{
            PreferGo: true,
            Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                d := net.Dialer{Timeout: 5 * time.Second}
                return d.DialContext(ctx, network, address+":53")
            },
        }
    } else {
        r = net.DefaultResolver
    }

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    ips, err := r.LookupHost(ctx, watch.Domain)
    latency := time.Since(start).Seconds() * 1000

    result := &DNSResult{
        Domain:    watch.Domain,
        LatencyMs: latency,
        Timestamp: time.Now(),
    }

    if err != nil {
        result.Error = err.Error()
    } else if len(ips) > 0 {
        result.ResolvedIP = ips[0]
    }

    return result
}

func (m *DNSMonitor) evaluateResult(watch *DomainWatch, result *DNSResult) {
    lastResult := m.lastResults[watch.Domain]

    // Check for resolution failure
    if result.Error != "" && (lastResult == nil || lastResult.Error == "") {
        m.playDNSEvent("failed", watch.Sound)
        return
    }

    // Check for recovery
    if result.Error == "" && lastResult != nil && lastResult.Error != "" {
        m.playDNSEvent("recovered", watch.Sound)
    }

    // Check for IP change
    if result.ResolvedIP != "" && watch.CheckIP != "" {
        if result.ResolvedIP != watch.CheckIP {
            if lastResult == nil || lastResult.ResolvedIP != result.ResolvedIP {
                m.playDNSEvent("ip_changed", watch.Sound)
            }
        }
    }

    // Check for slow query
    if result.LatencyMs > float64(watch.LatencyThreshold) {
        if lastResult == nil || result.LatencyMs < float64(watch.LatencyThreshold) {
            m.playDNSEvent("slow", watch.Sound)
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| net | Go Stdlib | Free | DNS resolution |
| context | Go Stdlib | Free | Cancellation |

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
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
