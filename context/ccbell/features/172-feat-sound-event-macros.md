# Feature: Sound Event Macros

Record and replay event sequences.

## Summary

Record a sequence of sound events and replay them as a macro.

## Motivation

- Automate workflows
- Replay patterns
- Quick demo/playback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Macro Features

| Feature | Description | Example |
|---------|-------------|---------|
| Record | Capture event sequence | Start → [events] → Stop |
| Replay | Play recorded sequence | Play macro N times |
| Edit | Modify macro steps | Add, remove, reorder |
| Export/Import | Share macros | JSON format |

### Configuration

```go
type MacroConfig struct {
    Enabled     bool              `json:"enabled"`
    Macros      map[string]*Macro `json:"macros"`
    Recording   *RecordingSession `json:"recording,omitempty"`
}

type Macro struct {
    ID          string      `json:"id"`
    Name        string      `json:"name"`
    Description string      `json:"description"`
    Steps       []MacroStep `json:"steps"`
    Repeat      int         `json:"repeat"` // 0 = infinite
    Speed       float64     `json:"speed"` // 1.0 = normal
    CreatedAt   time.Time   `json:"created_at"`
    UsageCount  int         `json:"usage_count"`
}

type MacroStep struct {
    EventType   string  `json:"event_type"`
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume"`
    DelayMs     int     `json:"delay_ms"` // After this event
    Timestamp   int64   `json:"timestamp"` // When recorded
}

type RecordingSession struct {
    Active      bool      `json:"active"`
    Name        string    `json:"name"`
    StartTime   time.Time `json:"start_time"`
    Steps       []MacroStep `json:"steps"`
}
```

### Commands

```bash
/ccbell:macro list                  # List macros
/ccbell:macro record <name>         # Start recording
/ccbell:macro stop                  # Stop recording, save macro
/ccbell:macro play <id>             # Play macro
/ccbell:macro play <id> --repeat 3  # Play N times
/ccbell:macro edit <id>             # Edit macro steps
/ccbell:macro delete <id>           # Delete macro
/ccbell:macro export <id>           # Export to JSON
/ccbell:macro import <path>         # Import from JSON
```

### Output

```
$ ccbell:macro list

=== Sound Event Macros ===

Macros: 2

[1] Morning Routine
    Steps: 5
    Duration: ~30s
    Repeat: 1
    Usage: 12 times
    [Play] [Edit] [Export] [Delete]

    [1] stop → [2] subagent → [3] permission_prompt → ...

[2] Alert Sequence
    Steps: 3
    Duration: ~5s
    Repeat: 3
    Usage: 5 times
    [Play] [Edit] [Export] [Delete]

Recording:
  Status: Not recording
  [Record <name>]

[Configure] [Create] [Import]
```

---

## Audio Player Compatibility

Macros work with all audio players:
- Uses existing playback
- No player changes required

---

## Implementation

### Macro Recording and Playback

```go
type MacroManager struct {
    config   *MacroConfig
    player   *audio.Player
    recording bool
    mutex    sync.Mutex
}

func (m *MacroManager) StartRecording(name string) error {
    m.mutex.Lock()
    defer m.mutex.Unlock()

    if m.recording {
        return errors.New("already recording")
    }

    m.config.Recording = &RecordingSession{
        Active:    true,
        Name:      name,
        StartTime: time.Now(),
        Steps:     []MacroStep{},
    }
    m.recording = true
    return nil
}

func (m *MacroManager) RecordStep(eventType string, cfg *config.Event) {
    if !m.recording || m.config.Recording == nil {
        return
    }

    step := MacroStep{
        EventType: eventType,
        Sound:     cfg.Sound,
        Volume:    derefFloat(cfg.Volume, 0.5),
        Timestamp: time.Now().UnixMilli(),
    }

    m.config.Recording.Steps = append(m.config.Recording.Steps, step)
}

func (m *MacroManager) Play(macroID string, repeat int) error {
    macro, ok := m.config.Macros[macroID]
    if !ok {
        return fmt.Errorf("macro not found: %s", macroID)
    }

    for i := 0; i <= repeat || repeat == 0; i++ {
        for _, step := range macro.Steps {
            volume := derefFloat(step.Volume, 0.5)
            if err := m.player.Play(step.Sound, volume); err != nil {
                return err
            }

            if step.DelayMs > 0 {
                time.Sleep(time.Duration(float64(step.DelayMs)/macro.Speed) * time.Millisecond)
            }
        }
    }

    macro.UsageCount++
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

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
