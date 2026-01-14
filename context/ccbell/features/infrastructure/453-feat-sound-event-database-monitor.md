# Feature: Sound Event Database Monitor

Play sounds for database connection issues, query performance problems, and replication lag.

## Summary

Monitor database systems (PostgreSQL, MySQL, MongoDB) for connection failures, query issues, and replication status, playing sounds for database events.

## Motivation

- Database awareness
- Connection failure alerts
- Performance monitoring
- Replication status
- Query failure detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Database Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Lost | Database unreachable | connection failed |
| Connection Restored | Database back online | connected |
| High Load | Query queue high | > 100 queries |
| Replication Lag | Slave behind master | > 10 seconds |
| Replication Down | Replication stopped | not replicating |
| Query Timeout | Slow query detected | > 10s |

### Configuration

```go
type DatabaseMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    WatchDatabases      []string          `json:"watch_databases"` // "postgresql://...", "mysql://..."
    ConnectionTimeout   int               `json:"connection_timeout_sec"` // 10 default
    QueryThresholdMs    int               `json:"query_threshold_ms"` // 10000 default
    ReplicationLagSec   int               `json:"replication_lag_sec"` // 10 default
    SoundOnDisconnect   bool              `json:"sound_on_disconnect"`
    SoundOnConnect      bool              `json:"sound_on_connect"`
    SoundOnHighLoad     bool              `json:"sound_on_high_load"`
    SoundOnReplication  bool              `json:"sound_on_replication"`
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:db status                   # Show database status
/ccbell:db add postgresql://localhost/mydb
/ccbell:db sound disconnect <sound>
/ccbell:db test                     # Test database sounds
```

### Output

```
$ ccbell:db status

=== Sound Event Database Monitor ===

Status: Enabled
Connection Timeout: 10s
Query Threshold: 10000ms
Replication Lag: 10s

Database Status:

[1] postgresql://localhost/mydb
    Status: CONNECTED
    Version: PostgreSQL 15.2
    Connections: 45/100
    Queries/sec: 120
    Replication: ACTIVE (lag: 0s)
    Sound: bundled:db-postgres

[2] mysql://localhost/appdb
    Status: CONNECTED
    Version: MySQL 8.0
    Connections: 80/200
    Queries/sec: 250
    Replication: SECONDARY *** LAG ***
    Lag: 15s *** HIGH ***
    Sound: bundled:db-mysql *** WARNING ***

[3] mongodb://localhost:27017
    Status: DISCONNECTED *** DOWN ***
    Last Error: connection refused
    Sound: bundled:db-mongo *** FAILED ***

Recent Events:

[1] mysql://localhost/appdb: Replication Lag (5 min ago)
       15s > 10s threshold
       Sound: bundled:db-replication
  [2] mongodb://localhost:27017: Disconnected (10 min ago)
       Connection refused
       Sound: bundled:db-disconnect
  [3] postgresql://localhost/mydb: Connected (30 min ago)
       Back online
       Sound: bundled:db-connect

Database Statistics:
  Total Databases: 3
  Connected: 2
  Disconnected: 1
  High Load: 0

Sound Settings:
  Connect: bundled:db-connect
  Disconnect: bundled:db-disconnect
  High Load: bundled:db-highload
  Replication: bundled:db-replication

[Configure] [Add Database] [Test All]
```

---

## Audio Player Compatibility

Database monitoring doesn't play sounds directly:
- Monitoring feature using psql, mysql, mongosh
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Database Monitor

```go
type DatabaseMonitor struct {
    config        *DatabaseMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    dbState       map[string]*DatabaseInfo
    lastEventTime map[string]time.Time
}

type DatabaseInfo struct {
    URL           string
    Type          string // "postgresql", "mysql", "mongodb"
    Status        string // "connected", "disconnected", "unknown"
    Version       string
    Connections   int
    MaxConnections int
    QueriesPerSec float64
    ReplicationLag int
    ReplicationStatus string
    LastError     string
}

func (m *DatabaseMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.dbState = make(map[string]*DatabaseInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DatabaseMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDBState()

    for {
        select {
        case <-ticker.C:
            m.checkDBState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DatabaseMonitor) snapshotDBState() {
    m.checkDBState()
}

func (m *DatabaseMonitor) checkDBState() {
    for _, dbURL := range m.config.WatchDatabases {
        info := m.checkDatabase(dbURL)
        if info != nil {
            m.processDBStatus(info)
        }
    }
}

func (m *DatabaseMonitor) checkDatabase(dbURL string) *DatabaseInfo {
    info := &DatabaseInfo{
        URL: dbURL,
    }

    // Parse connection string to determine type
    if strings.Contains(dbURL, "postgresql") || strings.Contains(dbURL, "postgres") {
        info.Type = "postgresql"
        return m.checkPostgreSQL(info)
    } else if strings.Contains(dbURL, "mysql") {
        info.Type = "mysql"
        return m.checkMySQL(info)
    } else if strings.Contains(dbURL, "mongodb") || strings.Contains(dbURL, "mongo") {
        info.Type = "mongodb"
        return m.checkMongoDB(info)
    }

    return nil
}

func (m *DatabaseMonitor) checkPostgreSQL(info *DatabaseInfo) *DatabaseInfo {
    // Try to connect and get status
    cmd := exec.Command("psql", "-c", "SELECT 1", "-t")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "disconnected"
        info.LastError = err.Error()
        return info
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("psql", "-c", "SELECT version()", "-t")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get connection count
    cmd = exec.Command("psql", "-c", "SELECT count(*) FROM pg_stat_activity", "-t")
    connOutput, _ := cmd.Output()
    info.Connections, _ = strconv.Atoi(strings.TrimSpace(string(connOutput)))

    // Get max connections
    cmd = exec.Command("psql", "-c", "SHOW max_connections", "-t")
    maxOutput, _ := cmd.Output()
    maxConn, _ := strconv.Atoi(strings.TrimSpace(string(maxOutput)))
    info.MaxConnections = maxConn

    return info
}

func (m *DatabaseMonitor) checkMySQL(info *DatabaseInfo) *DatabaseInfo {
    // Check connection
    cmd := exec.Command("mysql", "-e", "SELECT 1", "-N")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "disconnected"
        info.LastError = err.Error()
        return info
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("mysql", "-e", "SELECT VERSION()", "-N")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get connection count
    cmd = exec.Command("mysql", "-e", "SHOW STATUS LIKE 'Threads_connected'", "-N")
    connOutput, _ := cmd.Output()
    connStr := strings.TrimSpace(string(connOutput))
    info.Connections, _ = strconv.Atoi(strings.Split(connStr, "\t")[1])

    // Get max connections
    cmd = exec.Command("mysql", "-e", "SHOW VARIABLES LIKE 'max_connections'", "-N")
    maxOutput, _ := cmd.Output()
    maxStr := strings.TrimSpace(string(maxOutput))
    info.MaxConnections, _ = strconv.Atoi(strings.Split(maxStr, "\t")[1])

    // Check replication
    cmd = exec.Command("mysql", "-e", "SHOW SLAVE STATUS", "-N")
    slaveOutput, _ := cmd.Output()
    if len(slaveOutput) > 0 {
        lines := strings.Split(string(slaveOutput), "\n")
        if len(lines) > 0 {
            fields := strings.Split(lines[0], "\t")
            if len(fields) > 25 {
                // Check if IO thread is running
                ioThread := fields[10]
                if ioThread == "Yes" {
                    info.ReplicationStatus = "active"
                    // Get lag
                    lagStr := fields[32]
                    info.ReplicationLag, _ = strconv.Atoi(lagStr)
                } else {
                    info.ReplicationStatus = "down"
                }
            }
        }
    }

    return info
}

func (m *DatabaseMonitor) checkMongoDB(info *DatabaseInfo) *DatabaseInfo {
    // Check connection
    cmd := exec.Command("mongosh", "--eval", "db.adminCommand('ping')")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "disconnected"
        info.LastError = err.Error()
        return info
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("mongosh", "--eval", "db.version()")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get connections
    cmd = exec.Command("mongosh", "--eval", "db.adminCommand({serverStatus: 1}).connections.current")
    connOutput, _ := cmd.Output()
    info.Connections, _ = strconv.Atoi(strings.TrimSpace(string(connOutput)))

    return info
}

func (m *DatabaseMonitor) processDBStatus(info *DatabaseInfo) {
    lastInfo := m.dbState[info.URL]

    if lastInfo == nil {
        m.dbState[info.URL] = info

        if info.Status == "connected" && m.config.SoundOnConnect {
            m.onDatabaseConnected(info)
        } else if info.Status == "disconnected" && m.config.SoundOnDisconnect {
            m.onDatabaseDisconnected(info)
        }
        return
    }

    // Check for connection changes
    if info.Status != lastInfo.Status {
        if info.Status == "connected" && lastInfo.Status == "disconnected" {
            if m.config.SoundOnConnect {
                m.onDatabaseConnected(info)
            }
        } else if info.Status == "disconnected" && lastInfo.Status == "connected" {
            if m.config.SoundOnDisconnect {
                m.onDatabaseDisconnected(info)
            }
        }
    }

    // Check for replication lag
    if info.ReplicationLag > m.config.ReplicationLagSec {
        if lastInfo.ReplicationLag <= m.config.ReplicationLagSec {
            if m.config.SoundOnReplication && m.shouldAlert(info.URL+"replag", 5*time.Minute) {
                m.onReplicationLag(info)
            }
        }
    }

    // Check for high connection load
    loadPercent := float64(info.Connections) / float64(info.MaxConnections) * 100
    if loadPercent > 80 {
        if lastInfo == nil || float64(lastInfo.Connections)/float64(lastInfo.MaxConnections)*100 < 80 {
            if m.config.SoundOnHighLoad && m.shouldAlert(info.URL+"load", 5*time.Minute) {
                m.onHighLoad(info)
            }
        }
    }

    m.dbState[info.URL] = info
}

func (m *DatabaseMonitor) onDatabaseConnected(info *DatabaseInfo) {
    key := fmt.Sprintf("connect:%s", info.URL)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DatabaseMonitor) onDatabaseDisconnected(info *DatabaseInfo) {
    key := fmt.Sprintf("disconnect:%s", info.URL)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DatabaseMonitor) onReplicationLag(info *DatabaseInfo) {
    sound := m.config.Sounds["replication"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DatabaseMonitor) onHighLoad(info *DatabaseInfo) {
    sound := m.config.Sounds["high_load"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *DatabaseMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| psql | System Tool | Free | PostgreSQL client |
| mysql | System Tool | Free | MySQL client |
| mongosh | System Tool | Free | MongoDB shell |

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
| macOS | Supported | Uses psql, mysql, mongosh |
| Linux | Supported | Uses psql, mysql, mongosh |
