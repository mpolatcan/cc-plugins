# Feature: Sound Event Socket Monitor

Play sounds for socket state changes, connection limits, and port activity.

## Summary

Monitor network sockets for state changes, connection counts, and port listening events, playing sounds for socket events.

## Motivation

- Socket awareness
- Connection monitoring
- Port listening alerts
- Connection limit warnings
- Network security

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Socket Events

| Event | Description | Example |
|-------|-------------|---------|
| Socket Opened | New socket | opened |
| Socket Closed | Socket closed | closed |
| Port Listening | New listener | listening |
| Connection Limit | Near max | limit hit |
| Too Many CLOSE_WAIT | Too many states | 100+ |
| Port Closed | Listener removed | closed |

### Configuration

```go
type SocketMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPorts        []string          `json:"watch_ports"` // "80", "443", "*"
    ConnectionLimit   int               `json:"connection_limit"` // 1000
    CloseWaitLimit    int               `json:"close_wait_limit"` // 100
    SoundOnListen     bool              `json:"sound_on_listen"`
    SoundOnClose      bool              `json:"sound_on_close"`
    SoundOnLimit      bool              `json:"sound_on_limit"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:socket status               # Show socket status
/ccbell:socket add 80               # Add port to watch
/ccbell:socket limit 1000           # Set connection limit
/ccbell:socket sound listen <sound>
/ccbell:socket test                 # Test socket sounds
```

### Output

```
$ ccbell:socket status

=== Sound Event Socket Monitor ===

Status: Enabled
Connection Limit: 1000
Close-WAIT Limit: 100

Socket Status:

[1] Port 80 (http)
    Status: LISTENING
    State: LISTEN
    Connections: 45
    Local Address: 0.0.0.0:80
    Sound: bundled:socket-http

[2] Port 443 (https)
    Status: LISTENING
    State: LISTEN
    Connections: 128
    Local Address: 0.0.0.0:443
    Sound: bundled:socket-https

[3] Port 8080
    Status: CLOSE_WAIT *** HIGH ***
    State: CLOSE-WAIT
    Connections: 150 *** HIGH ***
    Local Address: 127.0.0.1:8080
    Sound: bundled:socket-8080 *** WARNING ***

Recent Events:

[1] Port 8080: Too Many CLOSE-WAIT (5 min ago)
       150 > 100 threshold
       Sound: bundled:socket-closewait
  [2] Port 3306: New Listener (1 hour ago)
       MySQL listening on 0.0.0.0:3306
       Sound: bundled:socket-listen
  [3] Port 8080: Socket Opened (2 hours ago)
       10 new connections
       Sound: bundled:socket-open

Socket Statistics:
  Total Ports: 3
  Listening: 2
  Close-WAIT: 1
  Total Connections: 323

Sound Settings:
  Listen: bundled:socket-listen
  Close: bundled:socket-close
  Limit: bundled:socket-limit
  Close-WAIT: bundled:socket-closewait

[Configure] [Add Port] [Test All]
```

---

## Audio Player Compatibility

Socket monitoring doesn't play sounds directly:
- Monitoring feature using netstat, ss, lsof
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Socket Monitor

```go
type SocketMonitor struct {
    config        *SocketMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    socketState   map[string]*SocketInfo
    lastEventTime map[string]time.Time
}

type SocketInfo struct {
    Port      string
    Protocol  string // "tcp", "udp"
    Status    string // "listening", "established", "close-wait", "closed"
    State     string
    Connections int
    LocalAddr string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| netstat | System Tool | Free | Network statistics |
| ss | System Tool | Free | Socket statistics |
| lsof | System Tool | Free | Open files |

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
| macOS | Supported | Uses netstat, lsof |
| Linux | Supported | Uses ss, netstat |
