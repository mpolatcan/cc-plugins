# Feature: Sound Event Dependencies

Play sounds based on other event completions.

## Summary

Define dependencies between events so one event's sound plays only after another completes.

## Motivation

- Event sequencing
- Workflow automation
- Conditional notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Dependency Types

| Type | Description | Example |
|------|-------------|---------|
| After | Play after another event | B after A completes |
| Chained | Sequence of events | A → B → C |
| Parallel | Play with another event | A + B together |
| Conditional | Play if condition met | If A then play B |

### Configuration

```go
type DependencyConfig struct {
    Enabled     bool              `json:"enabled"`
    Dependencies map[string]*Dependency `json:"dependencies"`
}

type Dependency struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Event       string   `json:"event"` // The dependent event
    DependsOn   []string `json:"depends_on"` // Events to wait for
    WaitForComplete bool `json:"wait_for_complete"` // Wait for sound to finish
    TimeoutSec  int      `json:"timeout_sec"` // Max wait time
    Action      string   `json:"action"` // "play", "skip", "queue"
}
```

### Commands

```bash
/ccbell:dep list                    # List dependencies
/ccbell:dep create "After Stop" --event permission_prompt --depends stop
/ccbell:dep create "Chained" --event subagent --depends stop,permission_prompt
/ccbell:dep enable <id>             # Enable dependency
/ccbell:dep disable <id>            # Disable dependency
/ccbell:dep delete <id>             # Remove dependency
/ccbell:dep test                    # Test dependency logic
```

### Output

```
$ ccbell:dep list

=== Sound Event Dependencies ===

Status: Enabled

Dependencies: 2

[1] After Stop
    Event: permission_prompt
    Depends On: stop
    Wait for Complete: Yes
    Timeout: 30s
    Action: play
    Status: Active
    [Edit] [Disable] [Delete]

[2] Chained Workflow
    Event: subagent
    Depends On: [stop, permission_prompt]
    Wait for Complete: No
    Timeout: 60s
    Action: queue
    Status: Active
    [Edit] [Disable] [Delete]

Dependency Graph:
  stop → permission_prompt → subagent

[Configure] [Create] [Test]
```

---

## Audio Player Compatibility

Dependencies work with all audio players:
- Uses existing event system
- No player changes required

---

## Implementation

### Dependency Checking

```go
type DependencyManager struct {
    config   *DependencyConfig
    state    *StateManager
    player   *audio.Player
    mutex    sync.Mutex
}

func (m *DependencyManager) CanPlay(eventType string) (bool, string) {
    dep, ok := m.config.Dependencies[eventType]
    if !ok {
        return true, "" // No dependency
    }

    if !dep.Enabled {
        return true, ""
    }

    for _, parentEvent := range dep.DependsOn {
        parentState, err := m.state.GetLastState(parentEvent)
        if err != nil {
            return false, fmt.Sprintf("cannot check %s: %v", parentEvent, err)
        }

        if !m.isComplete(parentEvent, parentState) {
            return false, fmt.Sprintf("waiting for %s", parentEvent)
        }

        if dep.WaitForComplete {
            if m.isPlaying(parentEvent) {
                return false, fmt.Sprintf("%s is playing", parentEvent)
            }
        }
    }

    return true, ""
}

func (m *DependencyManager) isComplete(eventType string, state *EventState) bool {
    if state == nil {
        return false
    }
    // Check if event was triggered and completed
    return state.LastTriggered && !state.IsPlaying
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event state tracking
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event processing
- [Player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
