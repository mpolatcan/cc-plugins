# Feature: Sound Event API

HTTP API for ccbell.

## Summary

HTTP API for remote control and status queries.

## Motivation

- Remote control
- Integration with other tools
- Web dashboard

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/status | Get current status |
| POST | /api/play | Play a sound |
| GET | /api/config | Get configuration |
| PUT | /api/config | Update configuration |
| GET | /api/events | Event history |
| POST | /api/disable | Disable notifications |
| POST | /api/enable | Enable notifications |

### Configuration

```go
type APIConfig struct {
    Enabled       bool              `json:"enabled"`
    Host          string            `json:"host"` // "localhost" default
    Port          int               `json:"port"` // 8080 default
    AuthToken     string            `json:"auth_token,omitempty"`
    CORSOrigins   []string          `json:"cors_origins,omitempty"`
    RateLimit     int               `json:"rate_limit_per_minute"` // 60 default
}

type APIResponse struct {
    Success bool        `json:"success"`
    Data    interface{} `json:"data,omitempty"`
    Error   string      `json:"error,omitempty"`
}

type PlayRequest struct {
    Sound   string  `json:"sound"`
    Volume  float64 `json:"volume,omitempty"`
    Event   string  `json:"event,omitempty"`
}
```

### Commands

```bash
/ccbell:api status                 # Show API status
/ccbell:api start                  # Start API server
/ccbell:api stop                   # Stop API server
/ccbell:api port 8080              # Set port
/ccbell:api host localhost         # Set host
/ccbell:api token set <token>      # Set auth token
/ccbell:api token generate         # Generate token
/ccbell:api cors add https://example.com
```

### Output

```
$ ccbell:api status

=== Sound Event API ===

Status: Stopped
Host: localhost
Port: 8080
Auth Token: Set (hidden)
CORS: Disabled
Rate Limit: 60/min

Endpoints:
  GET  /api/status       - Get status
  POST /api/play         - Play sound
  GET  /api/config       - Get config
  PUT  /api/config       - Update config
  GET  /api/events       - Event history
  POST /api/disable      - Disable
  POST /api/enable       - Enable

[Start] [Stop] [Configure]
```

---

## Audio Player Compatibility

API doesn't play sounds directly:
- HTTP server
- Triggers playback via existing system

---

## Implementation

### API Server

```go
type APIServer struct {
    config   *APIConfig
    player   *audio.Player
    cfg      *config.Config
    server   *http.Server
    rateLimiter *RateLimiter
}

func (m *APIServer) Start() error {
    m.server = &http.Server{
        Addr:    fmt.Sprintf("%s:%d", m.config.Host, m.config.Port),
        Handler: m.createRouter(),
    }

    return m.server.ListenAndServe()
}

func (m *APIServer) createRouter() http.Handler {
    r := mux.NewRouter()

    // Rate limiting
    r.Use(m.rateLimitMiddleware)

    // Auth middleware
    if m.config.AuthToken != "" {
        r.Use(m.authMiddleware)
    }

    // Routes
    r.HandleFunc("/api/status", m.handleStatus).Methods("GET")
    r.HandleFunc("/api/play", m.handlePlay).Methods("POST")
    r.HandleFunc("/api/config", m.handleConfigGet).Methods("GET")
    r.HandleFunc("/api/config", m.handleConfigPut).Methods("PUT")
    r.HandleFunc("/api/events", m.handleEvents).Methods("GET")
    r.HandleFunc("/api/disable", m.handleDisable).Methods("POST")
    r.HandleFunc("/api/enable", m.handleEnable).Methods("POST")

    return r
}

func (m *APIServer) handlePlay(w http.ResponseWriter, r *http.Request) {
    var req PlayRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        m.writeError(w, "invalid request", http.StatusBadRequest)
        return
    }

    volume := req.Volume
    if volume == 0 {
        volume = 0.5
    }

    soundPath, err := m.player.ResolveSoundPath(req.Sound, req.Event)
    if err != nil {
        m.writeError(w, err.Error(), http.StatusBadRequest)
        return
    }

    if err := m.player.Play(soundPath, volume); err != nil {
        m.writeError(w, err.Error(), http.StatusInternalServerError)
        return
    }

    m.writeJSON(w, APIResponse{Success: true, Data: map[string]string{
        "status":  "playing",
        "sound":   soundPath,
        "volume":  fmt.Sprintf("%.2f", volume),
    }})
}

func (m *APIServer) handleConfigGet(w http.ResponseWriter, r *http.Request) {
    m.writeJSON(w, APIResponse{Success: true, Data: m.cfg})
}

func (m *APIServer) handleConfigPut(w http.ResponseWriter, r *http.Request) {
    var newCfg config.Config
    if err := json.NewDecoder(r.Body).Decode(&newCfg); err != nil {
        m.writeError(w, "invalid config", http.StatusBadRequest)
        return
    }

    if err := newCfg.Validate(); err != nil {
        m.writeError(w, err.Error(), http.StatusBadRequest)
        return
    }

    m.cfg = &newCfg
    m.writeJSON(w, APIResponse{Success: true, Data: "config updated"})
}

func (m *APIServer) rateLimitMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !m.rateLimiter.Allow() {
            http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| gorilla/mux | Go Module | Free | HTTP routing |
| http | Go Stdlib | Free | HTTP server |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Playback via API
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config API
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
