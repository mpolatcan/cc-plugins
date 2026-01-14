# Feature: Sound Event Macros

Macro support for complex event sequences.

## Summary

Define macros that execute multiple actions.

## Motivation

- Complex automation
- Multiple actions
- Custom workflows

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Macro Actions

| Action | Description | Example |
|--------|-------------|---------|
| Play | Play a sound | play stop |
| Wait | Wait N milliseconds | wait 500 |
| Volume | Set volume | volume 0.7 |
| Repeat | Repeat N times | repeat 3 |
| If | Conditional | if condition |

### Configuration

```go
type MacroConfig struct {
    Enabled     bool              `json:"enabled"`
    Macros      map[string]*Macro `json:"macros"`
}

type Macro struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Actions     []MacroAction `json:"actions"`
    Enabled     bool     `json:"enabled"`
}

type MacroAction struct {
    Type    string `json:"type"` // "play", "wait", "volume", "repeat", "if"
    Sound   string `json:"sound,omitempty"`
    Volume  float64 `json:"volume,omitempty"`
    Duration int   `json:"duration,omitempty"` // ms
    Repeat  int    `json:"repeat,omitempty"`
    Condition string `json:"condition,omitempty"`
    ThenActions []MacroAction `json:"then_actions,omitempty"`
}

type MacroExecution struct {
    MacroID    string        `json:"macro_id"`
    StartTime  time.Time     `json:"start_time"`
    ActionsRun int           `json:"actions_run"`
    Status     string        `json:"status"` // "running", "completed", "failed"
}
```

### Commands

```bash
/ccbell:macro list                  # List macros
/ccbell:macro create alert-sequence # Create macro
/ccbell:macro add play stop         # Add action
/ccbell:macro add wait 500          # Add wait
/ccbell:macro add volume 0.8        # Add volume change
/ccbell:macro run alert-sequence    # Run macro
/ccbell:macro test alert-sequence   # Test macro
/ccbell:macro delete alert-sequence # Delete macro
/ccbell:macro export alert-sequence # Export macro
```

### Output

```
$ ccbell:macro list

=== Sound Macros ===

Status: Enabled
Macros: 3

[1] Alert Sequence
    Description: Triple alert with increasing volume
    Actions: 7
    Enabled: Yes
    [Run] [Edit] [Export] [Delete]

[2] Gentle Reminder
    Description: Soft reminder with fade out
    Actions: 5
    Enabled: Yes
    [Run] [Edit] [Export] [Delete]

[3] Busy Indicator
    Description: Shows I'm in focus mode
    Actions: 3
    Enabled: No
    [Run] [Edit] [Export] [Delete]

[Create New]

$ ccbell:macro run alert-sequence

=== Running: Alert Sequence ===

[1/7] Play: bundled:stop (vol=0.5)
[2/7] Wait: 500ms
[3/7] Play: bundled:stop (vol=0.6)
[4/7] Wait: 500ms
[5/7] Play: bundled:stop (vol=0.7)
[6/7] Wait: 1000ms
[7/7] Volume: 0.5

Status: COMPLETED (2.5s)
```

---

## Audio Player Compatibility

Macros use existing audio player:
- Executes `player.Play()` in sequence
- Same format support
- No player changes required

---

## Implementation

### Macro Execution

```go
type MacroExecutor struct {
    config  *MacroConfig
    player  *audio.Player
    running bool
}

func (e *MacroExecutor) Run(macroID string) error {
    macro, ok := e.config.Macros[macroID]
    if !ok {
        return fmt.Errorf("macro not found: %s", macroID)
    }

    return e.executeActions(macro.Actions)
}

func (e *MacroExecutor) executeActions(actions []MacroAction) error {
    for i, action := range actions {
        switch action.Type {
        case "play":
            if err := e.play(action.Sound, action.Volume); err != nil {
                return fmt.Errorf("action %d: %w", i+1, err)
            }
        case "wait":
            time.Sleep(time.Duration(action.Duration) * time.Millisecond)
        case "volume":
            e.currentVolume = action.Volume
        case "repeat":
            for r := 0; r < action.Repeat; r++ {
                if err := e.executeActions(action.ThenActions); err != nil {
                    return err
                }
            }
        case "if":
            if e.evaluateCondition(action.Condition) {
                if err := e.executeActions(action.ThenActions); err != nil {
                    return err
                }
            }
        }
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Macro playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
