# Feature: Sound Event LDAP/AD Connection Monitor

Play sounds for LDAP/Active Directory connection status, bind failures, and sync events.

## Summary

Monitor LDAP and Active Directory connections for authentication, replication, and availability, playing sounds for directory events.

## Motivation

- Directory service awareness
- Authentication monitoring
- Replication tracking
- Connection failure alerts
- User lookup feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### LDAP/AD Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Up | Connected to LDAP | connected |
| Connection Down | Connection failed | timeout |
| Bind Failed | Authentication failed | invalid creds |
| Replication Sync | Replication complete | synced |
| Search Slow | Query > threshold | > 1s |
| Schema Change | Directory updated | new attribute |

### Configuration

```go
type LDAPConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Servers           []LDAPServerConfig `json:"servers"`
    QueryTimeout      int               `json:"query_timeout_ms"` // 5000 default
    SlowThreshold     int               `json:"slow_threshold_ms"` // 1000 default
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type LDAPServerConfig struct {
    Name     string `json:"name"` // "Corporate AD"
    Host     string `json:"host"` // "ldap.example.com"
    Port     int    `json:"port"` // 389, 636
    UseTLS   bool   `json:"use_tls"`
    BaseDN   string `json:"base_dn"` // "dc=example,dc=com"
    BindDN   string `json:"bind_dn"`
    BindPass string `json:"bind_pass"`
}
```

### Commands

```bash
/ccbell:ldap status                    # Show LDAP status
/ccbell:ldap add "ldap.example.com"    # Add server
/ccbell:ldap remove "ldap.example.com"
/ccbell:ldap sound connect <sound>
/ccbell:ldap sound fail <sound>
/ccbell:ldap test                      # Test LDAP sounds
```

### Output

```
$ ccbell:ldap status

=== Sound Event LDAP/AD Connection Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Fail Sounds: Yes

Monitored Servers: 2

LDAP Server Status:

[1] Corporate AD (ldap.corp.example.com:389)
    Status: Connected
    Latency: 15ms
    Last Check: 5 min ago
    Bind: Success
    Replication: Synced (5 min ago)
    Sound: bundled:ldap-corporate

[2] OpenLDAP (ldap.openldap.local:389)
    Status: Connected
    Latency: 5ms
    Last Check: 5 min ago
    Bind: Success
    Entries: 12,450
    Sound: bundled:ldap-openldap

Connection Statistics:
  Total Servers: 2
  Connected: 2
  Failed Binds: 0
  Total Queries: 500

Recent Events:
  [1] Corporate AD: Connected (5 min ago)
       Reconnected after brief outage
  [2] OpenLDAP: Slow Query (1 hour ago)
       1.5s > 1s threshold
  [3] Corporate AD: Replication Sync (2 hours ago)
       500 changes synced

LDAP Statistics:
  Queries Today: 250
  Slow Queries: 3
  Failed Queries: 0
  Average Latency: 12ms

Sound Settings:
  Connect: bundled:ldap-connect
  Disconnect: bundled:ldap-disconnect
  Fail: bundled:ldap-fail

[Configure] [Add Server] [Test All]
```

---

## Audio Player Compatibility

LDAP monitoring doesn't play sounds directly:
- Monitoring feature using ldapsearch
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### LDAP Connection Monitor

```go
type LDAPConnectionMonitor struct {
    config          *LDAPConnectionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serverState     map[string]*LDAPServerInfo
    lastEventTime   map[string]time.Time
}

type LDAPServerInfo struct {
    Name       string
    Host       string
    Port       int
    Status     string // "connected", "disconnected", "unknown"
    Latency    int64  // milliseconds
    BindStatus string // "success", "failed", "unknown"
    LastCheck  time.Time
}

func (m *LDAPConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serverState = make(map[string]*LDAPServerInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *LDAPConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkServers()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LDAPConnectionMonitor) checkServers() {
    for _, server := range m.config.Servers {
        m.checkServer(&server)
    }
}

func (m *LDAPConnectionMonitor) checkServer(config *LDAPServerConfig) {
    id := fmt.Sprintf("%s:%d", config.Host, config.Port)

    info := &LDAPServerInfo{
        Name:      config.Name,
        Host:      config.Host,
        Port:      config.Port,
        LastCheck: time.Now(),
    }

    // Test connection with timeout
    startTime := time.Now()

    cmd := exec.Command("ldapsearch",
        "-H", fmt.Sprintf("ldap://%s:%d", config.Host, config.Port),
        "-D", config.BindDN,
        "-w", config.BindPass,
        "-b", config.BaseDN,
        "-s", "base",
        "(objectClass=*)",
        "dn",
        "-Z", // Start TLS if configured
        "-o", fmt.Sprintf("nettimeout=%d", m.config.QueryTimeout/1000),
    )

    if config.UseTLS {
        cmd = exec.Command("ldapsearch",
            "-H", fmt.Sprintf("ldaps://%s:%d", config.Host, config.Port),
            "-D", config.BindDN,
            "-w", config.BindPass,
            "-b", config.BaseDN,
            "-s", "base",
            "(objectClass=*)",
            "dn",
            "-o", fmt.Sprintf("nettimeout=%d", m.config.QueryTimeout/1000),
        )
    }

    output, err := cmd.Output()
    latency := time.Since(startTime).Milliseconds()
    info.Latency = latency

    if err != nil {
        // Check if it's a connection error or auth error
        errStr := string(output)
        if strings.Contains(errStr, "Invalid credentials") {
            info.Status = "connected"
            info.BindStatus = "failed"
        } else {
            info.Status = "disconnected"
            info.BindStatus = "unknown"
        }
    } else {
        info.Status = "connected"
        info.BindStatus = "success"
    }

    m.processServerStatus(id, config.Name, info)
}

func (m *LDAPConnectionMonitor) processServerStatus(id, name string, info *LDAPServerInfo) {
    lastInfo := m.serverState[id]

    if lastInfo == nil {
        m.serverState[id] = info
        return
    }

    // Check for connection changes
    if lastInfo.Status != info.Status {
        if info.Status == "connected" {
            m.onServerConnected(name, info)
        } else if info.Status == "disconnected" {
            m.onServerDisconnected(name, info)
        }
    }

    // Check for bind failures
    if lastInfo.BindStatus != info.BindStatus && info.BindStatus == "failed" {
        m.onBindFailed(name, info)
    }

    // Check for slow queries
    if info.Latency >= int64(m.config.SlowThreshold) {
        if lastInfo.Latency < int64(m.config.SlowThreshold) {
            m.onSlowQuery(name, info)
        }
    }

    m.serverState[id] = info
}

func (m *LDAPConnectionMonitor) onServerConnected(name string, info *LDAPServerInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    key := fmt.Sprintf("connect:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LDAPConnectionMonitor) onServerDisconnected(name string, info *LDAPServerInfo) {
    if !m.config.SoundOnDisconnect {
        return
    }

    key := fmt.Sprintf("disconnect:%s", name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *LDAPConnectionMonitor) onBindFailed(name string, info *LDAPServerInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("bindfail:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *LDAPConnectionMonitor) onSlowQuery(name string, info *LDAPServerInfo) {
    key := fmt.Sprintf("slow:%s", name)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LDAPConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ldapsearch | System Tool | Free | LDAP client (openldap) |

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
| macOS | Supported | Uses ldapsearch (via homebrew) |
| Linux | Supported | Uses ldapsearch (openldap-clients) |
