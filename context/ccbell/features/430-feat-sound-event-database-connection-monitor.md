# Feature: Sound Event Database Connection Monitor

Play sounds for database connection status, query timeouts, and connection pool exhaustion.

## Summary

Monitor database connections for availability, query performance, and connection pool status, playing sounds for database events.

## Motivation

- Database awareness
- Connection failure alerts
- Query performance tracking
- Pool exhaustion warnings
- Database health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Database Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Up | DB connected | Connected |
| Connection Down | DB unreachable | Timeout |
| Query Slow | Query > threshold | > 5s |
| Pool High | Pool near max | > 80% |
| Connection Lost | Connection dropped | Reconnect |
| Replication Lag | Replica behind | > 10s |

### Configuration

```go
type DatabaseConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDatabases    []string          `json:"watch_databases"` // "localhost:5432", "mongodb://*"
    QueryTimeout      int               `json:"query_timeout_sec"` // 5 default
    SlowQueryThreshold int              `json:"slow_query_sec"` // 5 default
    PoolWarning       int               `json:"pool_warning_percent"` // 80 default
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnSlowQuery  bool              `json:"sound_on_slow_query"`
    SoundOnPoolHigh   bool              `json:"sound_on_pool_high"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:db status                   # Show database status
/ccbell:db add localhost:5432       # Add database to watch
/ccbell:db add mongodb://localhost
/ccbell:db timeout 5                # Set query timeout
/ccbell:db sound connect <sound>
/ccbell:db sound disconnect <sound>
/ccbell:db test                     # Test database sounds
```

### Output

```
$ ccbell:db status

=== Sound Event Database Connection Monitor ===

Status: Enabled
Query Timeout: 5s
Slow Query Threshold: 5s

Database Status:

[1] postgresql://localhost:5432 (main)
    Status: CONNECTED
    Version: PostgreSQL 15.2
    Connections: 45/100 (45%)
    Latency: 2ms
    Queries/sec: 125
    Sound: bundled:db-postgres

[2] mysql://localhost:3306 (app)
    Status: CONNECTED
    Version: MySQL 8.0.32
    Connections: 23/200 (12%)
    Latency: 1ms
    Queries/sec: 85
    Sound: bundled:db-mysql

[3] mongodb://localhost:27017 (analytics)
    Status: CONNECTING
    Version: MongoDB 6.0
    Connections: 5/100 (5%)
    Latency: -
    Sound: bundled:db-mongo *** CONNECTING ***

[4] redis://localhost:6379 (cache)
    Status: CONNECTED
    Version: Redis 7.2
    Connected Clients: 12
    Memory: 45 MB
    Sound: bundled:db-redis

Connection Pool Status:

  PostgreSQL: 45/100 (45%)
  MySQL: 23/200 (12%)
  MongoDB: 5/100 (5%)

Recent Events:
  [1] PostgreSQL: Slow Query (1 hour ago)
       Query took 8.2s > 5s threshold
       Sound: bundled:db-slow-query
  [2] MongoDB: Connection Lost (2 hours ago)
       Server timeout
       Sound: bundled:db-disconnect
  [3] Redis: Connected (3 hours ago)
       New connection established
       Sound: bundled:db-connect

Database Statistics:
  Total Databases: 4
  Connected: 3
  Avg Latency: 1.5ms
  Slow Queries Today: 5

Sound Settings:
  Connect: bundled:db-connect
  Disconnect: bundled:db-disconnect
  Slow Query: bundled:db-slow-query
  Pool High: bundled:db-pool-high

[Configure] [Add Database] [Test All]
```

---

## Audio Player Compatibility

Database monitoring doesn't play sounds directly:
- Monitoring feature using psql/mysql/mongosh/redis-cli
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Database Connection Monitor

```go
type DatabaseConnectionMonitor struct {
    config          *DatabaseConnectionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    dbState         map[string]*DatabaseInfo
    lastEventTime   map[string]time.Time
}

type DatabaseInfo struct {
    Name           string
    Type           string // "postgresql", "mysql", "mongodb", "redis"
    ConnectionString string
    Status         string // "connected", "disconnected", "connecting", "unknown"
    Version        string
    Connections    int
    MaxConnections int
    PoolPercent    float64
    Latency        time.Duration
    QueriesPerSec  float64
    LastCheck      time.Time
}

func (m *DatabaseConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.dbState = make(map[string]*DatabaseInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DatabaseConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDatabaseConnections()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DatabaseConnectionMonitor) checkDatabaseConnections() {
    for _, connStr := range m.config.WatchDatabases {
        info := m.checkDatabase(connStr)
        if info != nil {
            m.processDatabaseStatus(info)
        }
    }
}

func (m *DatabaseConnectionMonitor) checkDatabase(connStr string) *DatabaseInfo {
    info := &DatabaseInfo{
        ConnectionString: connStr,
        LastCheck:        time.Now(),
    }

    // Parse connection string
    info.Name, info.Type = m.parseConnectionString(connStr)

    // Check connection based on type
    switch info.Type {
    case "postgresql":
        m.checkPostgreSQL(info)
    case "mysql":
        m.checkMySQL(info)
    case "mongodb":
        m.checkMongoDB(info)
    case "redis":
        m.checkRedis(info)
    }

    return info
}

func (m *DatabaseConnectionMonitor) parseConnectionString(connStr string) (name, dbType string) {
    // Parse common database connection strings
    if strings.HasPrefix(connStr, "postgresql://") ||
       strings.HasPrefix(connStr, "postgres://") ||
       strings.HasPrefix(connStr, "pgsql://") {
        return connStr, "postgresql"
    }
    if strings.HasPrefix(connStr, "mysql://") {
        return connStr, "mysql"
    }
    if strings.HasPrefix(connStr, "mongodb://") ||
       strings.HasPrefix(connStr, "mongodb+srv://") {
        return connStr, "mongodb"
    }
    if strings.HasPrefix(connStr, "redis://") {
        return connStr, "redis"
    }

    // Default to postgres for localhost:port patterns
    if strings.Contains(connStr, ":5432") {
        return connStr, "postgresql"
    }
    if strings.Contains(connStr, ":3306") {
        return connStr, "mysql"
    }
    if strings.Contains(connStr, ":27017") {
        return connStr, "mongodb"
    }
    if strings.Contains(connStr, ":6379") {
        return connStr, "redis"
    }

    return connStr, "unknown"
}

func (m *DatabaseConnectionMonitor) checkPostgreSQL(info *DatabaseInfo) {
    // Try to check PostgreSQL connection
    cmd := exec.Command("psql", "-h", "localhost", "-c", "SELECT 1", "-t", "-q")
    output, err := cmd.CombinedOutput()

    if err != nil {
        // Try to determine if it's a connection issue
        errorStr := string(output)
        if strings.Contains(errorStr, "could not connect") ||
           strings.Contains(errorStr, "connection refused") {
            info.Status = "disconnected"
        } else if strings.Contains(errorStr, "timeout") {
            info.Status = "connecting"
        }
        return
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("psql", "-V")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get connection count (if we have permission)
    cmd = exec.Command("psql", "-h", "localhost", "-c",
        "SELECT count(*) FROM pg_stat_activity", "-t", "-q")
    connOutput, _ := cmd.Output()
    if len(connOutput) > 0 {
        info.Connections, _ = strconv.Atoi(strings.TrimSpace(string(connOutput)))
    }
}

func (m *DatabaseConnectionMonitor) checkMySQL(info *DatabaseInfo) {
    cmd := exec.Command("mysqladmin", "ping", "-h", "localhost")
    err := cmd.Run()

    if err != nil {
        info.Status = "disconnected"
        return
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("mysqladmin", "-V")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get connections
    cmd = exec.Command("mysqladmin", "-h", "localhost", "status")
    statusOutput, _ := cmd.Output()
    statusStr := string(statusOutput)

    // Parse: Threads: 5 Questions: 1000 Slow: 0
    re := regexp.MustEach(`Threads: (\d+)`)
    matches := re.FindStringSubmatch(statusStr)
    if len(matches) >= 2 {
        info.Connections, _ = strconv.Atoi(matches[1])
    }
}

func (m *DatabaseConnectionMonitor) checkMongoDB(info *DatabaseInfo) {
    cmd := exec.Command("mongosh", "--eval", "db.adminCommand('ping')", "--quiet")
    err := cmd.Run()

    if err != nil {
        info.Status = "disconnected"
        return
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("mongosh", "--version")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get connections (simplified - would need more complex query in production)
    info.Connections = 1 // Placeholder
}

func (m *DatabaseConnectionMonitor) checkRedis(info *DatabaseInfo) {
    cmd := exec.Command("redis-cli", "ping")
    output, err := cmd.Output()

    if err != nil {
        info.Status = "disconnected"
        return
    }

    if strings.TrimSpace(string(output)) != "PONG" {
        info.Status = "disconnected"
        return
    }

    info.Status = "connected"

    // Get version
    cmd = exec.Command("redis-cli", "--version")
    versionOutput, _ := cmd.Output()
    info.Version = strings.TrimSpace(string(versionOutput))

    // Get client count
    cmd = exec.Command("redis-cli", "client", "list")
    clientsOutput, _ := cmd.Output()
    clients := strings.Split(string(clientsOutput), "\n")
    info.Connections = len(clients)
}

func (m *DatabaseConnectionMonitor) processDatabaseStatus(info *DatabaseInfo) {
    lastInfo := m.dbState[info.Name]

    if lastInfo == nil {
        m.dbState[info.Name] = info
        if info.Status == "connected" && m.config.SoundOnConnect {
            m.onDatabaseConnected(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        if info.Status == "connected" {
            if m.config.SoundOnConnect {
                m.onDatabaseConnected(info)
            }
        } else if info.Status == "disconnected" {
            if m.config.SoundOnDisconnect {
                m.onDatabaseDisconnected(info)
            }
        }
    }

    // Check for pool warnings
    if info.PoolPercent >= float64(m.config.PoolWarning) {
        if lastInfo.PoolPercent < float64(m.config.PoolWarning) {
            if m.config.SoundOnPoolHigh {
                m.onPoolHigh(info)
            }
        }
    }

    m.dbState[info.Name] = info
}

func (m *DatabaseConnectionMonitor) onDatabaseConnected(info *DatabaseInfo) {
    key := fmt.Sprintf("connect:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["connect"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DatabaseConnectionMonitor) onDatabaseDisconnected(info *DatabaseInfo) {
    key := fmt.Sprintf("disconnect:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["disconnect"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DatabaseConnectionMonitor) onPoolHigh(info *DatabaseInfo) {
    key := fmt.Sprintf("pool:%s", info.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["pool_high"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DatabaseConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| mysqladmin | System Tool | Free | MySQL admin tool |
| mongosh | System Tool | Free | MongoDB shell |
| redis-cli | System Tool | Free | Redis CLI |

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
| macOS | Supported | Uses psql, mysqladmin, mongosh, redis-cli |
| Linux | Supported | Uses psql, mysqladmin, mongosh, redis-cli |
