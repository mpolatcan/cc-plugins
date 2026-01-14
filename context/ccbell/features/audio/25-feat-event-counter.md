# Feature: Event Counter

Track how many times each notification event has fired.

## Summary

Maintain a running count of notifications per event type, stored in state and displayable via status command.

## Motivation

- Monitor notification frequency over time
- Identify noisy event patterns
- Support the notification dashboard feature

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current State Management

The current `internal/state/state.go` stores:
- `LastPlayed` timestamps
- `Cooldowns` state

**Key Finding**: Adding event counters is a simple extension.

### State Extension

```go
type State struct {
    LastPlayed   map[string]time.Time `json:"lastPlayed,omitempty"`
    Cooldowns    map[string]time.Time `json:"cooldowns,omitempty"`
    EventCounters map[string]int      `json:"eventCounters,omitempty"`
}
```

### Counter Update

```go
func (s *State) IncrementCounter(eventType string) {
    if s.EventCounters == nil {
        s.EventCounters = make(map[string]int)
    }
    s.EventCounters[eventType]++
}

// Get counter for specific event
func (s *State) GetCounter(eventType string) int {
    if s.EventCounters == nil {
        return 0
    }
    return s.EventCounters[eventType]
}
```

### Commands

```bash
/ccbell:status counters     # Show event counters
/ccbell:status counters --reset  # Reset counters
/ccbell:stats events        # Show statistics

# Output
Event Counters:
  stop:              1,234
  permission_prompt:   456
  idle_prompt:         789
  subagent:            123

Total: 2,602
```

---

## Audio Player Compatibility

Event counters don't interact with audio playback:
- Purely state tracking feature
- No changes to player required
- Updates before/after playback

---

## Implementation

### State Integration

```go
// In main.go, after successful playback
state := stateManager.Load()
state.IncrementCounter(eventType)
stateManager.Save(state)
```

### Reset Capability

```go
func (s *State) ResetCounters() {
    s.EventCounters = make(map[string]int)
}
```

### Stats Display

```go
func displayCounters(state *State) {
    total := 0
    for event, count := range state.EventCounters {
        fmt.Printf("  %-20s %6d\n", event+":", count)
        total += count
    }
    fmt.Printf("\nTotal: %d\n", total)
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

- [Current state](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State struct to extend
- [State file](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - JSON persistence pattern
- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | State tracking |
| Linux | ✅ Supported | State tracking |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
