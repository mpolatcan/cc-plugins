# Feature: Sound Event Database Monitor

Play sounds for database connection status and query performance events.

## Summary

Monitor database connections, query performance, and database server health, playing sounds for database events.

## Motivation

- Connection failure alerts
- Query performance feedback
- Database availability
- Replication lag warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Database Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Lost | DB unreachable | Connection refused |
| Connection Restored | DB available | 200 OK |
| Slow Query | Query > threshold | > 1s |
| Connection Pool | Pool exhausted | Max connections |
| Replication Lag | Replica behind | > 5s lag |

### Configuration

```go
type DatabaseMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Connections       []DBConnection    `json:"connections"`
    SoundOnDisconnect bool              `json:"sound_on_disconnect"`
    SoundOnConnect    bool              `json:"sound_on_connect"`
    SoundOnSlowQuery  bool              `json:"sound_on_slow_query"`
    QueryThresholdMs  int               `json:"query_threshold_ms"` // 1000 default
    CheckInterval     int               `json:"check_interval_sec"` // 30 default
    Sounds            map[string]string `json:"sounds"`
}

type DBConnection struct {
    Name         string `json:"name"`
    Driver       string `json:"driver"` // "postgres", "mysql", "sqlite"
    ConnectionString string `json:"connection_string"`
}

type DatabaseEvent struct {
    DBName       string
    EventType    string // "connected", "disconnected", "slow_query", "pool_exhausted"
    Query        string
    DurationMs   int
    ErrorMessage string
}
```

### Commands

```bash
/ccbell:database status               # Show database status
/ccbell:database add "mydb" postgres://...
/ccbell:database remove "mydb"
/ccbell:database sound disconnect <sound>
/ccbell:database sound slow <sound>
/ccbell:database test                 # Test database sounds
```

### Output

```
$ ccbell:database status

=== Sound Event Database Monitor ===

Status: Enabled
Query Threshold: 1000ms

Watched Databases: 2

[1] mydb (PostgreSQL)
    Status: CONNECTED
    Connections: 15/100
    Latency: 5ms
    Last Check: 10s ago
    Sound: bundled:stop

[2] cache (Redis)
    Status: CONNECTED
    Connections: 5/1000
    Latency: 1ms
    Last Check: 10s ago
    Sound: bundled:stop

Recent Events:
  [1] mydb: Connected (5 min ago)
       Connection restored
  [2] mydb: Slow Query (1 hour ago)
       "SELECT * FROM large_table" (2500ms)
  [3] cache: Connected (2 hours ago)

Sound Settings:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Slow Query: bundled:stop
  Pool Exhausted: bundled:stop

[Configure] [Add Database] [Test All]
```

---

## Audio Player Compatibility

Database monitoring doesn't play sounds directly:
- Monitoring feature using database drivers
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Database Monitor

```go
type DatabaseMonitor struct {
    config          *DatabaseMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    dbState         map[string]*DBStatus
}

type DBStatus struct {
    Name          string
    Driver        string
    Connected     bool
    LastCheck     time.Time
    LatencyMs     int
    ConnectionCount int
    LastError     string
}

func (m *DatabaseMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.dbState = make(map[string]*DBStatus)
    go m.monitor()
}

func (m *DatabaseMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    // Initial check
    m.checkAllDatabases()

    for {
        select {
        case <-ticker.C:
            m.checkAllDatabases()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DatabaseMonitor) checkAllDatabases() {
    for _, conn := range m.config.Connections {
        m.checkDatabase(conn)
    }
}

func (m *DatabaseMonitor) checkDatabase(conn DBConnection) {
    status := m.dbState[conn.Name]
    if status == nil {
        status = &DBStatus{
            Name:   conn.Name,
            Driver: conn.Driver,
        }
        m.dbState[conn.Name] = status
    }

    // Perform health check
    result := m.performHealthCheck(conn)

    status.LastCheck = time.Now()
    status.LatencyMs = result.LatencyMs

    if result.Connected {
        if !status.Connected {
            // Just connected
            status.Connected = true
            m.onDatabaseConnected(conn.Name)
        }
        status.LastError = ""
    } else {
        if status.Connected {
            // Just disconnected
            status.Connected = false
            status.LastError = result.ErrorMessage
            m.onDatabaseDisconnected(conn.Name, result.ErrorMessage)
        }
    }
}

func (m *DatabaseMonitor) performHealthCheck(conn DBConnection) *DBCheckResult {
    result := &DBCheckResult{}

    start := time.Now()

    switch conn.Driver {
    case "postgres":
        result = m.checkPostgres(conn.ConnectionString)
    case "mysql":
        result = m.checkMySQL(conn.ConnectionString)
    case "redis":
        result = m.checkRedis(conn.ConnectionString)
    case "sqlite":
        result = m.checkSQLite(conn.ConnectionString)
    }

    result.LatencyMs = int(time.Since(start).Milliseconds())
    return result
}

func (m *DatabaseMonitor) checkPostgres(connStr string) *DBCheckResult {
    result := &DBCheckResult{}

    // Parse connection string
    u, err := url.Parse(connStr)
    if err != nil {
        result.ErrorMessage = err.Error()
        return result
    }

    // Simple connection test using psql command
    cmd := exec.Command("psql", connStr, "-c", "SELECT 1")
    output, err := cmd.CombinedOutput()

    if err != nil {
        result.Connected = false
        result.ErrorMessage = string(output)
    } else {
        result.Connected = true
    }

    return result
}

func (m *DatabaseMonitor) checkMySQL(connStr string) *DBCheckResult {
    result := &DBCheckResult{}

    // Extract host/port from connection string
    u, err := url.Parse(connStr)
    if err != nil {
        result.ErrorMessage = err.Error()
        return result
    }

    // Use mysql client
    cmd := exec.Command("mysql", "-e", "SELECT 1")
    cmd.Env = append(os.Environ(), "MYSQL_PWD="+u.Query().Get("password"))
    output, err := cmd.CombinedOutput()

    if err != nil {
        result.Connected = false
        result.ErrorMessage = string(output)
    } else {
        result.Connected = true
    }

    return result
}

func (m *DatabaseMonitor) checkRedis(connStr string) *DBCheckResult {
    result := &DBCheckResult{}

    cmd := exec.Command("redis-cli", "ping")
    output, err := cmd.Output()

    if err != nil {
        result.Connected = false
        result.ErrorMessage = err.Error()
    } else if strings.TrimSpace(string(output)) == "PONG" {
        result.Connected = true
    }

    return result
}

func (m *DatabaseMonitor) checkSQLite(connStr string) *DBCheckResult {
    result := &DBCheckResult{}

    // SQLite is local, just check if file exists
    u, err := url.Parse(connStr)
    if err != nil {
        result.ErrorMessage = err.Error()
        return result
    }

    path := u.Path
    if _, err := os.Stat(path); os.IsNotExist(err) {
        result.Connected = false
        result.ErrorMessage = "database file not found"
    } else {
        result.Connected = true
    }

    return result
}

func (m *DatabaseMonitor) onDatabaseConnected(name string) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DatabaseMonitor) onDatabaseDisconnected(name string, errorMsg string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *DatabaseMonitor) onSlowQuery(name string, query string, durationMs int) {
    if !m.config.SoundOnSlowQuery {
        return
    }

    sound := m.config.Sounds["slow_query"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| psql | System Tool | Free | PostgreSQL client |
| mysql | System Tool | Free | MySQL client |
| redis-cli | System Tool | Free | Redis client |
| database/sql | Go Stdlib | Free | Database access |

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
| macOS | Supported | Uses CLI tools |
| Linux | Supported | Uses CLI tools |
| Windows | Not Supported | ccbell only supports macOS/Linux |
