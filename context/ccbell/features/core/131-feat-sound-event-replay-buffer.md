# Feature: Sound Event Replay Buffer

Buffer and replay missed events.

## Summary

Store recent events and replay them when needed.

## Motivation

- Recover missed notifications
- Review recent events
- Event logging

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Buffer Configuration

```go
type ReplayBufferConfig struct {
    Enabled      bool    `json:"enabled"`
    MaxEvents    int     `json:"max_events"`     // max events to store
    MaxDuration  int     `json:"max_duration"`   // max time to keep
    IncludeSound bool    `json:"include_sound"`  // store sound data
    AutoReplay   bool    `json:"auto_replay"`    // auto-replay on start
    PerEvent     bool    `json:"per_event"`      // separate buffers
}

type BufferedEvent struct {
    ID          string    `json:"id"`
    EventType   string    `json:"event_type"`
    SoundID     string    `json:"sound_id"`
    SoundPath   string    `json:"sound_path"`
    Volume      float64   `json:"volume"`
    Timestamp   time.Time `json:"timestamp"`
    Duration    time.Duration `json:"duration"`
}
```

### Commands

```bash
/ccbell:buffer status              # Show buffer status
/ccbell:buffer list                # List buffered events
/ccbell:buffer replay <id>         # Replay specific event
/ccbell:buffer replay last         # Replay last event
/ccbell:buffer replay all          # Replay all events
/ccbell:buffer clear               # Clear buffer
/ccbell:buffer limit 50            # Set max 50 events
/ccbell:buffer duration 1h         # Keep for 1 hour
/ccbell:buffer pause               # Pause buffering
```

### Output

```
$ ccbell:buffer list

=== Event Replay Buffer ===

Status: Active
Events: 12 / 100 max
Duration: 2h 15m / 24h max

Buffered Events:

[1] Today 10:30 AM
    Event: stop
    Sound: bundled:stop
    Volume: 50%
    [Replay] [Clear]

[2] Today 10:28 AM
    Event: subagent
    Sound: custom:complete
    Volume: 60%
    [Replay] [Clear]

[3] Today 10:15 AM
    Event: permission_prompt
    Sound: bundled:permission_prompt
    Volume: 50%
    [Replay] [Clear]

...

[Replay All] [Clear All] [Configure]
```

---

## Audio Player Compatibility

Replay buffer uses existing audio player:
- Calls `player.Play()` for replay
- Same format support
- No player changes required

---

## Implementation

### Event Buffering

```go
func (b *BufferManager) Record(eventType, soundID, soundPath string, volume float64) {
    event := &BufferedEvent{
        ID:        generateID(),
        EventType: eventType,
        SoundID:   soundID,
        SoundPath: soundPath,
        Volume:    volume,
        Timestamp: time.Now(),
    }

    b.buffer = append([]*BufferedEvent{event}, b.buffer...)

    // Trim to max events
    if len(b.buffer) > b.config.MaxEvents {
        b.buffer = b.buffer[:b.config.MaxEvents]
    }

    // Remove expired events
    b.cleanupExpired()

    b.saveBuffer()
}
```

### Event Replay

```go
func (b *BufferManager) Replay(eventID string) error {
    event := b.findEvent(eventID)
    if event == nil {
        return fmt.Errorf("event not found: %s", eventID)
    }

    player := audio.NewPlayer(b.pluginRoot)
    return player.Play(event.SoundPath, event.Volume)
}

func (b *BufferManager) ReplayAll() error {
    for _, event := range b.buffer {
        if err := b.Replay(event.ID); err != nil {
            return err
        }
        // Small delay between replays
        time.Sleep(500 * time.Millisecond)
    }
    return nil
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Replay playback
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event storage

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
