# Feature: Sound API

REST API for programmatic sound control.

## Summary

HTTP API for controlling ccbell from other applications.

## Motivation

- Integration with other tools
- Remote control
- Automation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/v1/sounds | List sounds |
| POST | /api/v1/play | Play a sound |
| POST | /api/v1/stop | Stop playback |
| GET | /api/v1/config | Get config |
| PUT | /api/v1/config | Update config |
| GET | /api/v1/events | List events |
| POST | /api/v1/events/:event/trigger | Trigger event |
| GET | /api/v1/health | Health check |

### API Response

```go
type APIResponse struct {
    Success bool        `json:"success"`
    Data    interface{} `json:"data,omitempty"`
    Error   string      `json:"error,omitempty"`
    RequestID string    `json:"request_id"`
}

type SoundListResponse struct {
    Sounds     []SoundInfo `json:"sounds"`
    Total      int         `json:"total"`
    Page       int         `json:"page"`
    PageSize   int         `json:"page_size"`
}
```

### Configuration

```go
type APIConfig struct {
    Enabled     bool   `json:"enabled"`
    Host        string `json:"host"`        // "127.0.0.1"
    Port        int    `json:"port"`        // 8080
    AuthToken   string `json:"auth_token"`  // optional
    CORSEnabled bool   `json:"cors_enabled"`
    RateLimit   int    `json:"rate_limit"`  // requests per minute
}
```

### Commands

```bash
/ccbell:api enable                   # Enable API
/ccbell:api disable                  # Disable API
/ccbell:api set port 8080            # Set port
/ccbell:api set auth mytoken         # Set auth token
/ccbell:api set cors enable          # Enable CORS
/ccbell:api status                   # Show API status
/ccbell:api test                     # Test API endpoints
/ccbell:api docs                     # Show API documentation
```

### Output

```
$ ccbell:api status

=== Sound API ===

Status: Enabled
Host: 127.0.0.1
Port: 8080
Auth: Yes (token set)
CORS: Disabled

Endpoints:
  GET  /api/v1/sounds       - List sounds
  POST /api/v1/play         - Play sound
  GET  /api/v1/config       - Get config
  PUT  /api/v1/config       - Update config
  POST /api/v1/events/:id   - Trigger event

[curl http://127.0.0.1:8080/api/v1/sounds]
[Configure] [Disable] [Docs]
```

---

## Audio Player Compatibility

API uses existing audio player:
- API calls `player.Play()` internally
- Same format support
- No player changes required

---

## Implementation

### HTTP Server

```go
func (a *APIManager) Start() error {
    router := mux.NewRouter()

    // Health check
    router.HandleFunc("/api/v1/health", a.healthCheck)

    // Sounds
    router.HandleFunc("/api/v1/sounds", a.listSounds)

    // Playback
    router.HandleFunc("/api/v1/play", a.playSound).Methods("POST")
    router.HandleFunc("/api/v1/stop", a.stopPlayback).Methods("POST")

    // Config
    router.HandleFunc("/api/v1/config", a.getConfig).Methods("GET")
    router.HandleFunc("/api/v1/config", a.updateConfig).Methods("PUT")

    // Events
    router.HandleFunc("/api/v1/events", a.listEvents)
    router.HandleFunc("/api/v1/events/{event}/trigger", a.triggerEvent).Methods("POST")

    // Start server
    addr := fmt.Sprintf("%s:%d", a.config.Host, a.config.Port)
    return router.Run(addr)
}
```

### Play Handler

```go
func (a *APIManager) playSound(w http.ResponseWriter, r *http.Request) {
    var req PlayRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        a.respondError(w, "Invalid request", http.StatusBadRequest)
        return
    }

    player := audio.NewPlayer(a.pluginRoot)
    path, err := player.ResolveSoundPath(req.Sound, "")
    if err != nil {
        a.respondError(w, err.Error(), http.StatusBadRequest)
        return
    }

    volume := req.Volume
    if volume == 0 {
        volume = 0.5
    }

    if err := player.Play(path, volume); err != nil {
        a.respondError(w, err.Error(), http.StatusInternalServerError)
        return
    }

    a.respond(w, APIResponse{
        Success: true,
        Data: map[string]string{
            "sound": req.Sound,
            "path":  path,
        },
    })
}
```

### Authentication

```go
func (a *APIManager) authMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if a.config.AuthToken == "" {
            next.ServeHTTP(w, r)
            return
        }

        token := r.Header.Get("Authorization")
        if token != "Bearer "+a.config.AuthToken {
            a.respondError(w, "Unauthorized", http.StatusUnauthorized)
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
| gorilla/mux | External library | Free | HTTP routing |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - API playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

### Research Sources

- [Go HTTP routing](https://pkg.go.dev/github.com/gorilla/mux)
- [REST API design](https://restfulapi.net/)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
