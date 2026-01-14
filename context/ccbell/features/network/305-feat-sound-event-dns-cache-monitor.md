# Feature: Sound Event DNS Cache Monitor

Play sounds for DNS cache changes and resolution events.

## Summary

Monitor DNS cache activity, resolution failures, and cache pollution, playing sounds for DNS events.

## Motivation

- DNS resolution awareness
- Cache poisoning alerts
- Resolution failure detection
- Network troubleshooting feedback

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
| Cache Miss | DNS not in cache | New lookup |
| Cache Hit | DNS resolved from cache | Cached entry |
| Resolution Failed | DNS lookup failed | NXDOMAIN |
| Cache Flushed | Cache cleared | scutil --flush |

### Configuration

```go
type DNSCacheMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDomains      []string          `json:"watch_domains"` // "example.com"
    SoundOnMiss       bool              `json:"sound_on_miss"]
    SoundOnFail       bool              `json:"sound_on_fail"]
    SoundOnFlush      bool              `json:"sound_on_flush"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type DNSCacheEvent struct {
    Domain      string
    IPAddress   string
    TTL         int
    EventType   string // "miss", "hit", "fail", "flush"
}
```

### Commands

```bash
/ccbell:dns status                    # Show DNS cache status
/ccbell:dns add example.com           # Add domain to watch
/ccbell:dns remove example.com
/ccbell:dns sound miss <sound>
/ccbell:dns sound fail <sound>
/ccbell:dns test                      # Test DNS sounds
```

### Output

```
$ ccbell:dns status

=== Sound Event DNS Cache Monitor ===

Status: Enabled
Miss Sounds: Yes
Fail Sounds: Yes

Watched Domains: 3

[1] api.example.com
    Status: HIT
    TTL: 300
    IP: 10.0.0.1
    Sound: bundled:stop

[2] db.example.com
    Status: HIT
    TTL: 600
    IP: 10.0.0.2
    Sound: bundled:stop

[3] new.example.com
    Status: MISS
    Resolving...
    Sound: bundled:dns-miss

Recent Events:
  [1] new.example.com: Cache Miss (5 sec ago)
       Resolving...
  [2] api.example.com: Cache Hit (1 min ago)
       TTL: 300
  [3] Cache Flushed (1 hour ago)
       DNS cache cleared

DNS Statistics:
  Hit Rate: 95%
  Queries/min: 100

Sound Settings:
  Miss: bundled:dns-miss
  Fail: bundled:dns-fail
  Flush: bundled:stop

[Configure] [Add Domain] [Test All]
```

---

## Audio Player Compatibility

DNS cache monitoring doesn't play sounds directly:
- Monitoring feature using DNS tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### DNS Cache Monitor

```go
type DNSCacheMonitor struct {
    config           *DNSCacheMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    dnsCache         map[string]*DNSCacheEntry
    cacheStats       *DNSStats
}

type DNSCacheEntry struct {
    Domain    string
    IPAddress string
    TTL       int
    Timestamp time.Time
}

type DNSStats struct {
    Hits   int
    Misses int
    Fails  int
}

func (m *DNSCacheMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.dnsCache = make(map[string]*DNSCacheEntry)
    m.cacheStats = &DNSStats{}
    go m.monitor()
}

func (m *DNSCacheMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDNSCache()

    for {
        select {
        case <-ticker.C:
            m.checkDNSEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DNSCacheMonitor) snapshotDNSCache() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinDNSCache()
    } else {
        m.snapshotLinuxDNSCache()
    }
}

func (m *DNSCacheMonitor) snapshotDarwinDNSCache() {
    // Use scutil to get DNS configuration
    cmd := exec.Command("scutil", "--dns")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseScutilOutput(string(output))
}

func (m *DNSCacheMonitor) snapshotLinuxDNSCache() {
    // Check systemd-resolved cache if available
    cmd := exec.Command("systemd-resolve", "--statistics")
    output, err := cmd.Output()
    if err != nil {
        // Fallback: use dig to check specific domains
        for _, domain := range m.config.WatchDomains {
            m.checkDomain(domain)
        }
        return
    }

    m.parseSystemdResolveOutput(string(output))
}

func (m *DNSCacheMonitor) checkDNSEvents() {
    for _, domain := range m.config.WatchDomains {
        m.checkDomain(domain)
    }
}

func (m *DNSCacheMonitor) checkDomain(domain string) {
    // Use dig to check DNS resolution
    cmd := exec.Command("dig", "+short", domain)
    output, err := cmd.Output()

    if err != nil {
        m.onDNSResolutionFailed(domain)
        return
    }

    ip := strings.TrimSpace(string(output))
    if ip == "" {
        m.onDNSResolutionFailed(domain)
        return
    }

    entry := m.dnsCache[domain]
    if entry == nil {
        // Cache miss - new domain
        m.onDNSCacheMiss(domain, ip)
    } else if entry.IPAddress != ip {
        // IP changed - potential cache pollution or update
        m.onDNSCacheUpdated(domain, entry.IPAddress, ip)
    }

    // Update cache
    m.dnsCache[domain] = &DNSCacheEntry{
        Domain:    domain,
        IPAddress: ip,
        Timestamp: time.Now(),
    }
}

func (m *DNSCacheMonitor) parseScutilOutput(output string) {
    lines := strings.Split(output, "\n")
    currentDomain := ""

    for _, line := range lines {
        if strings.HasPrefix(line, "  domain") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                currentDomain = parts[2]
            }
        } else if strings.HasPrefix(line, "  address") && currentDomain != "" {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                ip := parts[2]
                m.dnsCache[currentDomain] = &DNSCacheEntry{
                    Domain:    currentDomain,
                    IPAddress: ip,
                    Timestamp: time.Now(),
                }
            }
        }
    }
}

func (m *DNSCacheMonitor) parseSystemdResolveOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "Cache:") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                // Parse cache statistics
                m.cacheStats.Hits, _ = strconv.Atoi(parts[1])
            }
        }
    }
}

func (m *DNSCacheMonitor) onDNSCacheMiss(domain string, ip string) {
    if !m.config.SoundOnMiss {
        return
    }

    // Only alert if we're watching this domain
    shouldWatch := len(m.config.WatchDomains) == 0
    for _, d := range m.config.WatchDomains {
        if d == domain {
            shouldWatch = true
            break
        }
    }

    if !shouldWatch {
        return
    }

    m.cacheStats.Misses++

    sound := m.config.Sounds["miss"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *DNSCacheMonitor) onDNSCacheUpdated(domain string, oldIP string, newIP string) {
    // IP change could indicate DNS poisoning - alert
    sound := m.config.Sounds["updated"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DNSCacheMonitor) onDNSResolutionFailed(domain string) {
    if !m.config.SoundOnFail {
        return
    }

    // Only alert if we're watching this domain
    shouldWatch := len(m.config.WatchDomains) == 0
    for _, d := range m.config.WatchDomains {
        if d == domain {
            shouldWatch = true
            break
        }
    }

    if !shouldWatch {
        return
    }

    m.cacheStats.Fails++

    sound := m.config.Sounds["fail"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *DNSCacheMonitor) onDNSCacheFlushed() {
    if !m.config.SoundOnFlush {
        return
    }

    // Clear cache
    m.dnsCache = make(map[string]*DNSCacheEntry)

    sound := m.config.Sounds["flush"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dig | Network Tool | Free | DNS lookup |
| scutil | System Tool | Free | macOS DNS config |
| systemd-resolve | System Tool | Free | Linux DNS stats |

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
| macOS | Supported | Uses scutil, dig |
| Linux | Supported | Uses dig, systemd-resolve |
| Windows | Not Supported | ccbell only supports macOS/Linux |
