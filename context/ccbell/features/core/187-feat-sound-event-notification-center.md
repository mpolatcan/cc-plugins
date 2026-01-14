# Feature: Sound Event Notification Center

Centralized notification hub.

## Summary

Central hub for all sound notifications with unified management and routing.

## Motivation

- Unified notification management
- Routing and filtering
- Central control

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Notification Types

| Type | Description | Example |
|-------|-------------|---------|
| Sound | Audio notifications | Play sound |
| Log | Log to file | Append to log |
| Callback | HTTP callback | Webhook |
| Command | Run command | Execute script |

### Configuration

```go
type NotificationCenterConfig struct {
    Enabled       bool              `json:"enabled"`
    Handlers      map[string]*Handler `json:"handlers"`
    DefaultHandler string          `json:"default_handler"` // "sound"
    Routing       []*Route          `json:"routes"`
}

type Handler struct {
    ID          string   `json:"id"`
    Type        string   `json:"type"` // "sound", "log", "callback", "command"
    Config      map[string]string `json:"config"`
    Enabled     bool     `json:"enabled"`
}

type Route struct {
    ID          string   `json:"id"`
    EventType   string   `json:"event_type"`
    HandlerID   string   `json:"handler_id"`
    Condition   string   `json:"condition,omitempty"` // Expression
}
```

### Commands

```bash
/ccbell:notify list                 # List handlers
/ccbell:notify create webhook --url https://example.com/callback
/ccbell:notify create log --path /var/log/ccbell.log
/ccbell:notify route stop webhook
/ccbell:notify default sound
/ccbell:notify test                 # Test all handlers
/ccbell:notify delete <id>          # Remove handler
```

### Output

```
$ ccbell:notify list

=== Sound Event Notification Center ===

Status: Enabled

Handlers: 3

[1] Sound
    Type: sound
    Status: Active
    [Edit] [Disable] [Delete]

[2] Webhook
    Type: callback
    URL: https://example.com/callback
    Status: Active
    [Edit] [Disable] [Delete]

[3] Logger
    Type: log
    Path: /var/log/ccbell.log
    Status: Active
    [Edit] [Disable] [Delete]

Routes:
  stop → Sound, Webhook
  permission_prompt → Sound
  idle_prompt → Sound
  subagent → Sound, Logger

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Notification center works with all audio players:
- Uses existing sound handler
- No player changes required

---

## Implementation

### Notification Center

```go
type NotificationCenter struct {
    config   *NotificationCenterConfig
    player   *audio.Player
    logger   *logger.Logger
}

func (m *NotificationCenter) Notify(eventType string, data map[string]interface{}) error {
    routes := m.findRoutes(eventType)

    for _, route := range routes {
        handler, ok := m.config.Handlers[route.HandlerID]
        if !ok || !handler.Enabled {
            continue
        }

        switch handler.Type {
        case "sound":
            m.handleSound(handler, eventType, data)
        case "log":
            m.handleLog(handler, eventType, data)
        case "callback":
            m.handleCallback(handler, eventType, data)
        case "command":
            m.handleCommand(handler, eventType, data)
        }
    }

    return nil
}

func (m *NotificationCenter) handleCallback(handler *Handler, eventType string, data map[string]interface{}) {
    url := handler.Config["url"]
    if url == "" {
        return
    }

    payload, _ := json.Marshal(map[string]interface{}{
        "event":   eventType,
        "data":    data,
        "timestamp": time.Now().Unix(),
    })

    http.Post(url, "application/json", bytes.NewReader(payload))
}

func (m *NotificationCenter) handleLog(handler *Handler, eventType string, data map[string]interface{}) {
    path := handler.Config["path"]
    if path == "" {
        return
    }

    logLine := fmt.Sprintf("[%s] %s: %v\n", time.Now().Format(time.RFC3339), eventType, data)
    os.WriteFile(path, []byte(logLine), 0644)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| http | Go Stdlib | Free | HTTP client |
| json | Go Stdlib | Free | JSON encoding |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound handler
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Logger](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go) - Logging

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
