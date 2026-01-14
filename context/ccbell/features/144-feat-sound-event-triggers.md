# Feature: Sound Event Triggers

Custom triggers for sound playback.

## Summary

Define custom triggers that cause sounds to play.

## Motivation

- Flexible automation
- External triggers
- Integration hooks

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Trigger Types

| Type | Description | Example |
|------|-------------|---------|
| File | File created/modified | watch /path |
| Signal | Signal received | SIGUSR1 |
| HTTP | HTTP endpoint | POST /trigger |
| FIFO | Named pipe | /tmp/ccbell |

### Configuration

```go
type TriggerConfig struct {
    Enabled     bool              `json:"enabled"`
    Triggers    map[string]*Trigger `json:"triggers"`
}

type Trigger struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Type        string   `json:"type"` // "file", "signal", "http", "fifo"
    Config      TriggerConfig `json:"config"`
    EventType   string   `json:"event_type"`
    Sound       string   `json:"sound"`
    Volume      float64  `json:"volume"`
    Enabled     bool     `json:"enabled"`
}

type TriggerConfig struct {
    Path        string   `json:"path,omitempty"` // file path
    Signal      int      `json:"signal,omitempty"` // signal number
    Port        int      `json:"port,omitempty"` // HTTP port
    Pattern     string   `json:"pattern,omitempty"` // file pattern
}
```

### Commands

```bash
/ccbell:trigger add file /path/to/file --event stop
/ccbell:trigger add signal SIGUSR1 --event permission_prompt
/ccbell:trigger add http 8080 --event subagent
/ccbell:trigger add fifo /tmp/ccbell-trigger --event idle_prompt
/ccbell:trigger list                    # List triggers
/ccbell:trigger enable <id>             # Enable trigger
/ccbell:trigger disable <id>            # Disable trigger
/ccbell:trigger test <id>               # Test trigger
/ccbell:trigger delete <id>             # Remove trigger
```

### Output

```
$ ccbell:trigger list

=== Sound Triggers ===

Status: Enabled
Triggers: 4

[1] file-watch
    Type: File
    Path: /tmp/*.txt
    Event: stop
    Enabled: Yes
    [Test] [Configure] [Remove]

[2] signal-trigger
    Type: Signal
    Signal: SIGUSR1 (10)
    Event: permission_prompt
    Enabled: Yes
    [Test] [Configure] [Remove]

[3] http-trigger
    Type: HTTP
    Port: 8080
    Endpoint: /trigger
    Event: subagent
    Enabled: Yes
    [Test] [Configure] [Remove]

[4] fifo-trigger
    Type: FIFO
    Path: /tmp/ccbell-trigger
    Event: idle_prompt
    Enabled: No
    [Test] [Configure] [Remove]

[Add] [Start All] [Stop All]
```

---

## Audio Player Compatibility

Triggers use existing audio player:
- Calls `player.Play()` when triggered
- Same format support
- No player changes required

---

## Implementation

### Trigger Handlers

```go
type TriggerManager struct {
    config  *TriggerConfig
    active  map[string]context.CancelFunc
}

func (m *TriggerManager) StartAll() error {
    for id, trigger := range m.config.Triggers {
        if !trigger.Enabled {
            continue
        }

        ctx, cancel := context.WithCancel(context.Background())
        m.active[id] = cancel

        go m.runTrigger(ctx, trigger)
    }
    return nil
}

func (m *TriggerManager) runTrigger(ctx context.Context, trigger *Trigger) {
    switch trigger.Type {
    case "file":
        m.watchFile(ctx, trigger)
    case "signal":
        m.waitForSignal(ctx, trigger)
    case "http":
        m.startHTTPServer(ctx, trigger)
    case "fifo":
        m.watchFIFO(ctx, trigger)
    }
}

func (m *TriggerManager) watchFile(ctx context.Context, trigger *Trigger) {
    watcher, _ := fsnotify.NewWatcher()
    defer watcher.Close()

    watcher.Add(trigger.Config.Path)

    for {
        select {
        case <-ctx.Done():
            return
        case event := <-watcher.Events:
            if event.Op&fsnotify.Create == fsnotify.Create {
                m.fireTrigger(trigger)
            }
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| fsnotify | External library | Free | File watching |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Triggered playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via fsnotify |
| Linux | ✅ Supported | Via fsnotify |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
