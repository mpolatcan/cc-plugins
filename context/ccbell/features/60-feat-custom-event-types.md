# Feature: Custom Event Types

Create user-defined event types beyond the standard four.

## Summary

Allow users to define custom event types with their own sounds and configurations.

## Motivation

- More granular notification control
- Support for Claude Code extensions
- Personalized event taxonomy

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Custom Event Structure

Current `ValidEvents` is a static map:
```go
var ValidEvents = map[string]bool{
    "stop":              true,
    "permission_prompt": true,
    "idle_prompt":       true,
    "subagent":          true,
}
```

**Key Finding**: Can extend to support dynamic events.

### Configuration

```json
{
  "custom_events": {
    "enabled": true,
    "events": {
      "error": {
        "trigger": "error",
        "sound": "bundled:alert",
        "volume": 0.7,
        "cooldown": 5
      },
      "success": {
        "trigger": "success",
        "sound": "bundled:complete",
        "volume": 0.5
      },
      "long_response": {
        "trigger": "long_response",
        "condition": "tokens > 5000",
        "sound": "bundled:lengthy",
        "volume": 0.6
      }
    }
  }
}
```

### Implementation

```go
type CustomEventConfig struct {
    Enabled  bool                   `json:"enabled"`
    Events   map[string]*CustomEvent `json:"events"`
}

type CustomEvent struct {
    Trigger   string  `json:"trigger"`
    Sound     string  `json:"sound"`
    Volume    float64 `json:"volume"`
    Cooldown  int     `json:"cooldown"`
    Condition string  `json:"condition,omitempty"`
}

func (c *CCBell) triggerCustomEvent(name string) error {
    if c.customEvents == nil || !c.customEvents.Enabled {
        return fmt.Errorf("custom events disabled")
    }

    event, ok := c.customEvents.Events[name]
    if !ok {
        return fmt.Errorf("unknown custom event: %s", name)
    }

    // Check cooldown
    if c.isInCooldown(name) {
        return nil
    }

    // Resolve and play sound
    player := audio.NewPlayer(pluginRoot)
    soundPath, _ := player.ResolveSoundPath(event.Sound, name)

    return player.Play(soundPath, event.Volume)
}
```

### Hook Integration

```json
{
  "hooks": [
    {
      "events": ["CustomEvent"],
      "matcher": "error|failed",
      "type": "command",
      "command": "ccbell trigger error"
    },
    {
      "events": ["CustomEvent"],
      "matcher": "success|complete",
      "type": "command",
      "command": "ccbell trigger success"
    }
  ]
}
```

### Commands

```bash
/ccbell:event list              # List all events (standard + custom)
/ccbell:event create error --sound bundled:alert --volume 0.7
/ccbell:event edit error --volume 0.5
/ccbell:event delete error
/ccbell:event trigger error     # Manually trigger
```

---

## Audio Player Compatibility

Custom events use existing audio player:
- Same `player.Play()` method
- Same format support
- No player changes required

---

## Implementation

### Event Validation

```go
func ValidateCustomEvent(name, sound string, volume float64) error {
    // Validate event name format
    if !eventTypeRegex.MatchString(name) {
        return errors.New("invalid event name format")
    }

    // Check volume range
    if volume < 0 || volume > 1 {
        return errors.New("volume must be 0.0-1.0")
    }

    return nil
}
```

### Dynamic Event Registry

```go
type EventRegistry struct {
    standard map[string]bool
    custom   map[string]*CustomEvent
}

func (r *EventRegistry) IsValid(eventType string) bool {
    return r.standard[eventType] || r.custom[eventType] != nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) - Base event types
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Custom events config
- [Hooks](https://github.com/mpolatcan/ccbell/blob/main/hooks/hooks.json) - Hook integration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Config + hooks |
| Linux | ✅ Supported | Config + hooks |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
