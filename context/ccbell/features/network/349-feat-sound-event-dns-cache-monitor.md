# Feature: Sound Event DNS Cache Monitor

Play sounds for DNS cache events and resolution failures.

## Summary

Monitor DNS cache status, cache hits/misses, and resolution failures, playing sounds for DNS events.

## Motivation

- DNS awareness
- Resolution failure alerts
- Cache performance feedback
- Domain blocking detection
- DNS security monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### DNS Cache Events

| Event | Description | Example |
|-------|-------------|---------|
| Cache Miss | DNS not in cache | First lookup |
| Cache Flush | Cache cleared | Cache purged |
| Resolution Failed | DNS lookup failed | NXDOMAIN |
| High Latency | Slow DNS response | > 100ms |
| Cache Poisoning | Suspicious entry | Invalid TTL |

### Configuration

```go
type DNSCacheMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchDomains       []string          `json:"watch_domains"` // "example.com", "*"
    LatencyThresholdMs int               `json:"latency_threshold_ms"` // 100 default
    SoundOnMiss        bool              `json:"sound_on_miss"`
    SoundOnFail        bool              `json:"sound_on_fail"`
    SoundOnFlush       bool              `json:"sound_on_flush"`
    SoundOnLatency     bool              `json:"sound_on_latency"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}

type DNSCacheEvent struct {
    Domain      string
    Resolver    string
    TTL         int
    LatencyMs   float64
    Result      string // "success", "nxdomain", "timeout", "servfail"
    EventType   string // "miss", "flush", "fail", "latency", "poison"
}
```

### Commands

```bash
/ccbell:dns status                    # Show DNS cache status
/ccbell:dns add example.com           # Add domain to watch
/ccbell:dns remove example.com
/ccbell:dns latency 100               # Set latency threshold
/ccbell:dns sound fail <sound>
/ccbell:dns test                      # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Cache Monitor ===

Status: Enabled
Latency Threshold: 100 ms
Miss Sounds: Yes
Fail Sounds: Yes

Watched Domains: 2

[1] example.com
    Status: CACHED
    TTL: 3600
    Latency: 2.5 ms
    Sound: bundled:dns-cache

[2] api.example.org
    Status: RESOLVED
    TTL: 300
    Latency: 45.2 ms
    Sound: bundled:dns-api

DNS Cache Statistics:
  Total Entries: 1250
  Hit Rate: 94.5%
  Avg Latency: 15 ms
  Failures Today: 3

Recent Events:
  [1] api.example.org: Cache Miss (5 min ago)
       First lookup for domain
  [2] unknown.com: Resolution Failed (10 min ago)
       NXDOMAIN response
  [3] blocked.com: Resolution Failed (1 hour ago)
       Blocked by DNS filter

DNS Resolvers:
  [1] 8.8.8.8 (Google)
  [2] 1.1.1.1 (Cloudflare)

Sound Settings:
  Miss: bundled:dns-miss
  Fail: bundled:dns-fail
  Flush: bundled:dns-flush

[Configure] [Add Domain] [Test All]
```

---

## Audio Player Compatibility

DNS cache monitoring doesn't play sounds directly:
- Monitoring feature using dig/lookupd
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### DNS Cache Monitor

```go
type DNSCacheMonitor struct {
    config          *DNSCacheMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    cacheState      map[string]*CacheEntry
    domainState     map[string]*DomainInfo
    lastEventTime   map[string]time.Time
}

type CacheEntry struct {
    Domain    string
    Resolver  string
    TTL       int
    AddedAt   time.Time
}

type DomainInfo struct {
    Domain     string
    Cached     bool
    TTL        int
    LatencyMs  float64
    LastResult string
    LookupCount int
}

func (m *DNSCacheMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cacheState = make(map[string]*CacheEntry)
    m.domainState = make(map[string]*DomainInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DNSCacheMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCacheState()

    for {
        select {
        case <-ticker.C:
            m.checkDomainState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSCacheMonitor) snapshotCacheState() {
    // Read DNS cache on Linux (dnsmasq/systemd-resolved)
    m.readDNSMasqCache()
    m.readSystemdResolvedCache()
}

func (m *DNSCacheMonitor) readDNSMasqCache() {
    cachePath := "/var/lib/dnsmasq/dnsmasq.leases"
    // This is a simplified approach - actual cache is in memory
}

func (m *DNSCacheMonitor) readSystemdResolvedCache() {
    cmd := exec.Command("resolvectl", "statistics")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse statistics
    m.parseResolvedStats(string(output))
}

func (m *DNSCacheMonitor) parseResolvedStats(output string) {
    // Parse systemd-resolved statistics
    // Look for cache hits/misses
}

func (m *DNSCacheMonitor) checkDomainState() {
    for domain := range m.domainState {
        m.lookupDomain(domain)
    }
}

func (m *DNSCacheMonitor) lookupDomain(domain string) {
    start := time.Now()

    cmd := exec.Command("dig", "+short", domain)
    output, err := cmd.Output()

    latency := time.Since(start).Seconds() * 1000

    info := &DomainInfo{
        Domain:    domain,
        LatencyMs: latency,
        LookupCount: m.domainState[domain].LookupCount + 1,
    }

    if err != nil {
        info.LastResult = "fail"
        m.onDNSFailed(domain, info)
        return
    }

    outputStr := strings.TrimSpace(string(output))

    // Check for various response types
    if outputStr == "" {
        info.LastResult = "nxdomain"
        m.onDNSFailed(domain, info)
        return
    }

    // Parse IPs
    ips := strings.Split(outputStr, "\n")
    info.Cached = false // dig doesn't check cache directly

    info.LastResult = "success"
    m.evaluateDNSEvents(domain, info)
}

func (m *DNSCacheMonitor) evaluateDNSEvents(domain string, info *DomainInfo) {
    // Check latency
    if info.LatencyMs >= float64(m.config.LatencyThresholdMs) {
        m.onHighLatency(domain, info)
    }

    // Check first lookup (cache miss)
    if info.LookupCount == 1 {
        m.onCacheMiss(domain, info)
    }

    m.domainState[domain] = info
}

func (m *DNSCacheMonitor) onCacheMiss(domain string, info *DomainInfo) {
    if !m.config.SoundOnMiss {
        return
    }

    key := fmt.Sprintf("miss:%s", domain)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["miss"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *DNSCacheMonitor) onDNSFailed(domain string, info *DomainInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", domain)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DNSCacheMonitor) onHighLatency(domain string, info *DomainInfo) {
    if !m.config.SoundOnLatency {
        return
    }

    key := fmt.Sprintf("latency:%s", domain)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["latency"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSCacheMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| dig | System Tool | Free | DNS lookup utility |
| resolvectl | System Tool | Free | systemd-resolved |
| dnsmasq | System Service | Free | DNS cache (optional) |

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
| macOS | Supported | Uses dig, dscacheutil |
| Linux | Supported | Uses dig, resolvectl |
