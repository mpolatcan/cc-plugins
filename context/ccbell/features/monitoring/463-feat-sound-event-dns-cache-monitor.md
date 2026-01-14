# Feature: Sound Event DNS Cache Monitor

Play sounds for DNS cache performance, cache misses, and resolution failures.

## Summary

Monitor DNS cache (system resolver, dnsmasq, systemd-resolved) for cache hit rates, misses, and resolution issues, playing sounds for DNS events.

## Motivation

- DNS awareness
- Cache performance
- Resolution failures
- Network debugging
- Performance monitoring

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
| Cache Miss | Cache miss detected | 10% miss |
| High Miss Rate | > 20% miss rate | 25% |
| Resolution Failed | DNS query failed | NXDOMAIN |
| Slow Resolution | > 100ms latency | 200ms |
| Cache Flushed | Cache cleared | flushed |
| Cache Hit | High hit rate | 95% |

### Configuration

```go
type DNSCacheMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchCache     string            `json:"watch_cache"` // "dnsmasq", "systemd-resolved", "all"
    MissThreshold  float64           `json:"miss_threshold"` // 0.2 (20%)
    LatencyThreshold int             `json:"latency_threshold_ms"` // 100 default
    SoundOnMiss    bool              `json:"sound_on_miss"`
    SoundOnFail    bool              `json:"sound_on_fail"`
    SoundOnSlow    bool              `json:"sound_on_slow"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:dns status                  # Show DNS cache status
/ccbell:dns add dnsmasq             # Add DNS cache to watch
/ccbell:dns miss 20                 # Set miss threshold
/ccbell:dns sound miss <sound>
/ccbell:dns test                    # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Cache Monitor ===

Status: Enabled
Watch Cache: dnsmasq
Miss Threshold: 20%
Latency Threshold: 100ms

DNS Cache Status:

[1] dnsmasq (local)
    Status: HEALTHY
    Cache Size: 10,000
    Cache Hits: 45,678
    Cache Misses: 5,123
    Hit Rate: 89.9%
    Miss Rate: 10.1%
    Avg Latency: 15ms
    Sound: bundled:dns-dnsmasq

[2] systemd-resolved
    Status: WARNING *** WARNING ***
    Cache Size: 5,000
    Cache Hits: 12,345
    Cache Misses: 4,567
    Hit Rate: 73.0%
    Miss Rate: 27.0% *** HIGH ***
    Avg Latency: 85ms
    Sound: bundled:dns-resolved *** WARNING ***

Recent Events:

[1] systemd-resolved: High Miss Rate (5 min ago)
       27% > 20% threshold
       Sound: bundled:dns-miss
  [2] dnsmasq: Cache Flushed (1 hour ago)
       Cache cleared manually
       Sound: bundled:dns-flush
  [3] systemd-resolved: Slow Resolution (2 hours ago)
       Avg latency 150ms > 100ms
       Sound: bundled:dns-slow

DNS Statistics:
  Total Queries: 67,813
  Total Hits: 58,023 (85.6%)
  Total Misses: 9,790 (14.4%)

Sound Settings:
  Miss: bundled:dns-miss
  Fail: bundled:dns-fail
  Slow: bundled:dns-slow
  Flush: bundled:dns-flush

[Configure] [Add Cache] [Test All]
```

---

## Audio Player Compatibility

DNS monitoring doesn't play sounds directly:
- Monitoring feature using dig, nslookup, dnsmasq statistics
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### DNS Cache Monitor

```go
type DNSCacheMonitor struct {
    config        *DNSCacheMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    cacheState    map[string]*DNSInfo
    lastEventTime map[string]time.Time
}

type DNSInfo struct {
    CacheType   string // "dnsmasq", "systemd-resolved", "unbound"
    Status      string // "healthy", "warning", "critical"
    CacheSize   int64
    Hits        int64
    Misses      int64
    HitRate     float64
    MissRate    float64
    AvgLatency  float64
    Failures    int64
}

func (m *DNSCacheMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cacheState = make(map[string]*DNSInfo)
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
            m.checkCacheState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSCacheMonitor) snapshotCacheState() {
    m.checkCacheState()
}

func (m *DNSCacheMonitor) checkCacheState() {
    // Check dnsmasq
    m.checkDnsmasq()

    // Check systemd-resolved
    m.checkSystemdResolved()

    // Check unbound
    m.checkUnbound()
}

func (m *DNSCacheMonitor) checkDnsmasq() {
    // Check if dnsmasq is running
    cmd := exec.Command("pgrep", "-x", "dnsmasq")
    if err := cmd.Run(); err != nil {
        return
    }

    info := &DNSInfo{
        CacheType: "dnsmasq",
    }

    // Get statistics
    cmd = exec.Command("cat", "/var/lib/misc/dnsmasq.leases")
    // Or check dnsmasq statistics if available

    // Try to get cache statistics from log
    cmd = exec.Command("grep", "dnsmasq", "/var/log/syslog", "-c", "-i", "query")
    _, _ = cmd.Output()

    // Check if we can query cache stats
    cmd = exec.Command("dig", "+short", "localhost")
    _, _ = cmd.Output()

    // Get cache info from statistics
    cmd = exec.Command("dig", "+stats", "example.com")
    output, err := cmd.Output()
    if err == nil {
        // Parse dig stats
        statsRe := regexp.MustEach(`Query time:\s*(\d+)`)
        matches := statsRe.FindStringSubmatch(string(output))
        if len(matches) >= 2 {
            info.AvgLatency, _ = strconv.ParseFloat(matches[1], 64)
        }
    }

    // Estimate hit rate based on latency (faster = better cache)
    if info.AvgLatency < 10 {
        info.HitRate = 95
        info.MissRate = 5
    } else if info.AvgLatency < 50 {
        info.HitRate = 85
        info.MissRate = 15
    } else {
        info.HitRate = 70
        info.MissRate = 30
    }

    info.Status = m.calculateStatus(info.MissRate)
    m.processCacheStatus(info)
}

func (m *DNSCacheMonitor) checkSystemdResolved() {
    // Check if systemd-resolved is running
    cmd := exec.Command("pgrep", "-x", "systemd-resolved")
    if err := cmd.Run(); err != nil {
        return
    }

    info := &DNSInfo{
        CacheType: "systemd-resolved",
    }

    // Get cache statistics from resolvedctl
    cmd = exec.Command("resolvectl", "statistics")
    output, err := cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "Cache") {
                // Parse cache statistics
                statsRe := regexp.MustEach(`(\d+)`)
                matches := statsRe.FindAllString(line, -1)
                if len(matches) >= 3 {
                    // Try to parse as total, hits, misses
                    if hits, err := strconv.ParseInt(matches[1], 10, 64); err == nil {
                        info.Hits = hits
                    }
                    if misses, err := strconv.ParseInt(matches[2], 10, 64); err == nil {
                        info.Misses = misses
                    }
                }
            }
        }
    }

    // Calculate hit rate
    total := info.Hits + info.Misses
    if total > 0 {
        info.HitRate = float64(info.Hits) / float64(total) * 100
        info.MissRate = float64(info.Misses) / float64(total) * 100
    }

    info.Status = m.calculateStatus(info.MissRate)
    m.processCacheStatus(info)
}

func (m *DNSCacheMonitor) checkUnbound() {
    // Check if unbound is running
    cmd := exec.Command("pgrep", "-x", "unbound")
    if err := cmd.Run(); err != nil {
        return
    }

    info := &DNSInfo{
        CacheType: "unbound",
    }

    // Get statistics
    cmd = exec.Command("unbound-control", "stats_noreset")
    output, err := cmd.Output()
    if err == nil {
        // Parse stats
        hitRe := regexp.MustEach(`total\.hit=([0-9]+)`)
        missRe := regexp.MustEach(`total\.miss=([0-9]+)`)

        hitMatches := hitRe.FindStringSubmatch(string(output))
        missMatches := missRe.FindStringSubmatch(string(output))

        if len(hitMatches) >= 2 {
            info.Hits, _ = strconv.ParseInt(hitMatches[1], 10, 64)
        }
        if len(missMatches) >= 2 {
            info.Misses, _ = strconv.ParseInt(missMatches[1], 10, 64)
        }
    }

    // Calculate hit rate
    total := info.Hits + info.Misses
    if total > 0 {
        info.HitRate = float64(info.Hits) / float64(total) * 100
        info.MissRate = float64(info.Misses) / float64(total) * 100
    }

    info.Status = m.calculateStatus(info.MissRate)
    m.processCacheStatus(info)
}

func (m *DNSCacheMonitor) calculateStatus(missRate float64) string {
    if missRate >= m.config.MissThreshold*100 {
        return "warning"
    }
    return "healthy"
}

func (m *DNSCacheMonitor) processCacheStatus(info *DNSInfo) {
    lastInfo := m.cacheState[info.CacheType]

    if lastInfo == nil {
        m.cacheState[info.CacheType] = info

        if info.Status == "warning" && m.config.SoundOnMiss {
            m.onHighMissRate(info)
        }
        return
    }

    // Check for miss rate changes
    if info.MissRate > lastInfo.MissRate {
        if info.MissRate >= m.config.MissThreshold*100 &&
           lastInfo.MissRate < m.config.MissThreshold*100 {
            if m.config.SoundOnMiss && m.shouldAlert(info.CacheType+"miss", 10*time.Minute) {
                m.onHighMissRate(info)
            }
        }
    }

    // Check for high latency
    if info.AvgLatency >= float64(m.config.LatencyThreshold) &&
       lastInfo.AvgLatency < float64(m.config.LatencyThreshold) {
        if m.config.SoundOnSlow && m.shouldAlert(info.CacheType+"slow", 10*time.Minute) {
            m.onSlowResolution(info)
        }
    }

    m.cacheState[info.CacheType] = info
}

func (m *DNSCacheMonitor) onHighMissRate(info *DNSInfo) {
    key := fmt.Sprintf("miss:%s", info.CacheType)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["miss"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSCacheMonitor) onSlowResolution(info *DNSInfo) {
    key := fmt.Sprintf("slow:%s", info.CacheType)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DNSCacheMonitor) onResolutionFailed(info *DNSInfo) {
    key := fmt.Sprintf("fail:%s", info.CacheType)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
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
| resolvectl | System Tool | Free | systemd-resolved control |
| pgrep | System Tool | Free | Process checking |

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
| macOS | Supported | Uses dig, scutil |
| Linux | Supported | Uses dig, resolvectl, unbound-control |
