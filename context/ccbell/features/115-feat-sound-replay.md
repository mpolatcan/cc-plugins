# Feature: Sound Replay

Replay recently played sounds.

## Summary

Quickly replay the last played sound or select from recent sounds.

## Motivation

- Replay missed sounds
- Review notifications
- Quick access to recent

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Replay Options

| Option | Description | Example |
|--------|-------------|---------|
| Last | Replay last sound | replay last |
| Recent | Select from recent | replay recent |
| History | Browse sound history | replay history |

### Implementation

```go
type ReplayConfig struct {
    Enabled       bool  `json:"enabled"`
    MaxHistory    int   `json:"max_history"`    // keep N sounds
    IncludeEvents bool  `json:"include_events"` // include event type
    PerEvent      bool  `json:"per_event"`      // separate history per event
}

type ReplayEntry struct {
    SoundID     string    `json:"sound_id"`
    SoundPath   string    `json:"sound_path"`
    EventType   string    `json:"event_type"`
    PlayedAt    time.Time `json:"played_at"`
    Volume      float64   `json:"volume"`
}
```

### Commands

```bash
/ccbell:replay                    # Replay last sound
/ccbell:replay last               # Replay last sound
/ccbell:replay recent             # Show recent sounds
/ccbell:replay history            # Show full history
/ccbell:replay 3                  # Replay 3rd recent
/ccbell:replay clear              # Clear history
/ccbell:replay volume 0.8         # Replay with volume
/ccbell:replay stop               # Stop replaying
```

### Output

```
$ ccbell:replay recent

=== Recent Sounds ===

[1] bundled:stop         (just now)
[2] bundled:subagent     (2 min ago)
[3] custom:notification  (5 min ago)
[4] bundled:stop         (12 min ago)
[5] bundled:idle_prompt  (25 min ago)

[Replay 1] [Replay 2] [Replay 3] [Clear] [More]

$ ccbell:replay 2

Replaying: bundled:subagent (played at 2:30 PM)
Volume: 50% (original)
```

---

## Audio Player Compatibility

Replay uses existing audio player:
- Calls `player.Play()` with stored path
- Same format support
- No player changes required

---

## Implementation

### History Tracking

```go
type ReplayManager struct {
    config  *ReplayConfig
    history []ReplayEntry
    mutex   sync.Mutex
}

func (r *ReplayManager) Record(soundID, soundPath, eventType string, volume float64) {
    r.mutex.Lock()
    defer r.mutex.Unlock()

    entry := ReplayEntry{
        SoundID:   soundID,
        SoundPath: soundPath,
        EventType: eventType,
        PlayedAt:  time.Now(),
        Volume:    volume,
    }

    r.history = append([]ReplayEntry{entry}, r.history...)

    // Trim to max history
    if len(r.history) > r.config.MaxHistory {
        r.history = r.history[:r.config.MaxHistory]
    }

    r.saveHistory()
}
```

### Replay Playback

```go
func (r *ReplayManager) Replay(index int) error {
    r.mutex.Lock()
    defer r.mutex.Unlock()

    if index < 0 || index >= len(r.history) {
        return fmt.Errorf("invalid history index: %d", index)
    }

    entry := r.history[index]

    player := audio.NewPlayer(r.pluginRoot)
    return player.Play(entry.SoundPath, entry.Volume)
}
```

### Interactive Selection

```go
func (r *ReplayManager) ShowRecent(count int) string {
    r.mutex.Lock()
    defer r.mutex.Unlock()

    display := "=== Recent Sounds ===\n\n"

    limit := count
    if limit > len(r.history) {
        limit = len(r.history)
    }

    for i := 0; i < limit; i++ {
        entry := r.history[i]
        ago := time.Since(entry.PlayedAt).Truncate(time.Minute)

        display += fmt.Sprintf("[%d] %-25s (%s ago)\n", i+1, entry.SoundID, ago)
    }

    return display
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
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - History persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
