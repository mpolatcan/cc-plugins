# Feature: Sound Event Database Connection Monitor

Play sounds for database connection pool events and connection issues.

## Summary

Monitor database connections, pool utilization, and connection errors, playing sounds for database events.

## Motivation

- Database awareness
- Connection pool alerts
- Query performance feedback
- Database health monitoring
- Connection error detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Database Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Added | New connection | Pool +1 |
| Connection Closed | Connection returned | Pool -1 |
| Pool Exhausted | No connections available | Pool at max |
| Query Slow | Query exceeds threshold | > 5s query |
| Deadlock Detected | Database deadlock | Lock wait timeout |
| Replication Lag | Replication delayed | Lag > 10s |

### Configuration

```go
type DatabaseConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Connections       []DBConnectionConfig `json:"connections"`
    PoolWarning       int               `json:"pool_warning_pct"` // 90 default
    QueryThreshold    int               `json:"query_threshold_ms"` // 5000 default
    LagThreshold      int               `json:"lag_threshold_sec"` // 10 default
    SoundOnPool       bool              `json:"sound_on_pool"`
    SoundOnSlow       bool              `json:"sound_on_slow"]
    SoundOnLag        bool              `json:"sound_on_lag"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type DBConnectionConfig struct {
    Name     string `json:"name"` // "postgres-main"
    Type     string `json:"type"` // "postgresql", "mysql", "redis"
    Host     string `json:"host"`
    Port     int    `json:"port"`
    User     string `json:"user"`
    Password string `json:"password"`
}

type DatabaseConnectionEvent struct {
    Database  string
    Type      string
    PoolSize  int
    PoolMax   int
    Queries   int
    Lag       int // seconds
    EventType string // "pool_warning", "pool_exhausted", "slow_query", "lag", "error"
}
```

### Commands

```bash
/ccbell:db status                     # Show database status
/ccbell:db add postgres-main          # Add database to watch
/ccbell:db remove postgres-main
/ccbell:db pool 90                    # Set pool warning threshold
/ccbell:db sound pool <sound>
/ccbell:db test                       # Test database sounds
```

### Output

```
$ ccbell:db status

=== Sound Event Database Connection Monitor ===

Status: Enabled
Pool Warning: 90%
Query Threshold: 5000ms
Pool Sounds: Yes
Slow Query Sounds: Yes

Monitored Databases: 3

[1] postgres-main (PostgreSQL)
    Pool: 45/100 (45%)
    Active Queries: 12
    Avg Query Time: 45 ms
    Replication Lag: 0.2s
    Sound: bundled:db-postgres

[2] mysql-replica (MySQL)
    Pool: 85/100 (85%) *** WARNING ***
    Active Queries: 8
    Avg Query Time: 120 ms
    Replication Lag: 5.1s
    Sound: bundled:db-mysql

[3] redis-cache (Redis)
    Pool: N/A
    Connected Clients: 50
    Avg Latency: 1 ms
    Memory Used: 2.5 GB
    Sound: bundled:db-redis

Recent Events:
  [1] mysql-replica: Pool Warning (5 min ago)
       85/100 connections used
  [2] postgres-main: Slow Query (10 min ago)
       Query exceeded 5000ms threshold
  [3] mysql-replica: Replication Lag (1 hour ago)
       Lag: 5.1s > 10s threshold

Database Statistics:
  Total Connections: 135
  Pool Warnings: 5
  Slow Queries: 12

Sound Settings:
  Pool Warning: bundled:db-pool
  Slow Query: bundled:db-slow
  Replication Lag: bundled:db-lag

[Configure] [Add Database] [Test All]
```

---

## Audio Player Compatibility

Database monitoring doesn't play sounds directly:
- Monitoring feature using psql/mysql client
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
    dbState         map[string]*DBInfo
    lastEventTime   map[string]time.Time
}

type DBInfo struct {
    Name       string
    Type       string
    PoolSize   int
    PoolMax    int
    Queries    int
    AvgQueryMs float64
    Lag        float64
    LastCheck  time.Time
}

func (m *DatabaseConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.dbState = make(map[string]*DBInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DatabaseConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
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

func (m *DatabaseConnectionMonitor) checkAllDatabases() {
    for _, conn := range m.config.Connections {
        m.checkDatabase(&conn)
    }
}

func (m *DatabaseConnectionMonitor) checkDatabase(conn *DBConnectionConfig) {
    var info *DBInfo

    switch conn.Type {
    case "postgresql":
        info = m.checkPostgreSQL(conn)
    case "mysql":
        info = m.checkMySQL(conn)
    case "redis":
        info = m.checkRedis(conn)
    default:
        return
    }

    if info == nil {
        return
    }

    info.Name = conn.Name
    info.Type = conn.Type
    info.LastCheck = time.Now()

    lastInfo := m.dbState[conn.Name]
    if lastInfo == nil {
        m.dbState[conn.Name] = info
        return
    }

    // Evaluate events
    m.evaluateDBEvents(conn.Name, info, lastInfo)
    m.dbState[conn.Name] = info
}

func (m *DatabaseConnectionMonitor) checkPostgreSQL(conn *DBConnectionConfig) *DBInfo {
    cmd := exec.Command("psql", "-h", conn.Host, "-p", strconv.Itoa(conn.Port),
        "-U", conn.User, "-d", "postgres", "-c",
        "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &DBInfo{}
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if _, err := strconv.Atoi(line); err == nil {
            info.Queries, _ = strconv.Atoi(line)
            break
        }
    }

    // Get max connections
    cmd = exec.Command("psql", "-h", conn.Host, "-p", strconv.Itoa(conn.Port),
        "-U", conn.User, "-d", "postgres", "-c",
        "SHOW max_connections")
    output, _ = cmd.Output()
    maxStr := strings.TrimSpace(string(output))
    info.PoolMax, _ = strconv.Atoi(maxStr)

    // Calculate pool size from active + idle
    info.PoolSize = info.Queries + 10 // Estimate idle connections

    return info
}

func (m *DatabaseConnectionMonitor) checkMySQL(conn *DBConnectionConfig) *DBInfo {
    cmd := exec.Command("mysql", "-h", conn.Host, "-P", strconv.Itoa(conn.Port),
        "-u", conn.User, fmt.Sprintf("-p%s", conn.Password), "-e",
        "SHOW GLOBAL STATUS LIKE 'Threads_connected'")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &DBInfo{}

    // Parse connected threads
    re := regexp.MustCompile(`Threads_connected\s+(\d+)`)
    match := re.FindStringSubmatch(string(output))
    if match != nil {
        info.PoolSize, _ = strconv.Atoi(match[1])
    }

    // Get max connections
    cmd = exec.Command("mysql", "-h", conn.Host, "-P", strconv.Itoa(conn.Port),
        "-u", conn.User, fmt.Sprintf("-p%s", conn.Password), "-e",
        "SHOW VARIABLES LIKE 'max_connections'")
    output, _ = cmd.Output()
    re = regexp.MustCompile(`max_connections\s+(\d+)`)
    match = re.FindStringSubmatch(string(output))
    if match != nil {
        info.PoolMax, _ = strconv.Atoi(match[1])
    }

    return info
}

func (m *DatabaseConnectionMonitor) checkRedis(conn *DBConnectionConfig) *DBInfo {
    cmd := exec.Command("redis-cli", "-h", conn.Host, "-p", strconv.Itoa(conn.Port), "INFO")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &DBInfo{}

    re := regexp.MustCompile(`connected_clients:(\d+)`)
    match := re.FindStringSubmatch(string(output))
    if match != nil {
        info.PoolSize, _ = strconv.Atoi(match[1])
    }

    re = regexp.MustCompile(`maxclients:(\d+)`)
    match = re.FindStringSubmatch(string(output))
    if match != nil {
        info.PoolMax, _ = strconv.Atoi(match[1])
    }

    return info
}

func (m *DatabaseConnectionMonitor) evaluateDBEvents(name string, newInfo *DBInfo, lastInfo *DBInfo) {
    // Check pool warning
    poolPct := float64(newInfo.PoolSize) / float64(newInfo.PoolMax) * 100
    lastPoolPct := float64(lastInfo.PoolSize) / float64(lastInfo.PoolMax) * 100

    if poolPct >= float64(m.config.PoolWarning) && lastPoolPct < float64(m.config.PoolWarning) {
        m.onPoolWarning(name, newInfo)
    }

    // Check pool exhausted
    if newInfo.PoolSize >= newInfo.PoolMax && lastInfo.PoolSize < lastInfo.PoolMax {
        m.onPoolExhausted(name, newInfo)
    }

    // Check replication lag
    if newInfo.Lag >= float64(m.config.LagThreshold) && lastInfo.Lag < float64(m.config.LagThreshold) {
        m.onReplicationLag(name, newInfo)
    }
}

func (m *DatabaseConnectionMonitor) onPoolWarning(name string, info *DBInfo) {
    if !m.config.SoundOnPool {
        return
    }

    key := fmt.Sprintf("pool_warning:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["pool_warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DatabaseConnectionMonitor) onPoolExhausted(name string, info *DBInfo) {
    key := fmt.Sprintf("pool_exhausted:%s", name)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["pool_exhausted"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *DatabaseConnectionMonitor) onReplicationLag(name string, info *DBInfo) {
    if !m.config.SoundOnLag {
        return
    }

    key := fmt.Sprintf("lag:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["lag"]
        if sound != "" {
            m.player.Play(sound, 0.5)
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
| mysql | System Tool | Free | MySQL client |
| redis-cli | System Tool | Free | Redis client |

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
| macOS | Supported | Uses psql, mysql, redis-cli |
| Linux | Supported | Uses psql, mysql, redis-cli |
