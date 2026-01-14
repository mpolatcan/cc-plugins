# Feature: Sound Event Chains

Chain multiple events together.

## Summary

Create chains of events that trigger sequentially.

## Motivation

- Event sequences
- Cascading notifications
- Multi-stage alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Chain Components

| Component | Description | Example |
|-----------|-------------|---------|
| Events | List of events | A -> B -> C |
| Delays | Delay between events | 1s, 2s, 3s |
| Conditions | When to trigger | Always or conditional |
| Fallback | On failure | Skip or stop |

### Configuration

```go
type ChainConfig struct {
    Enabled     bool              `json:"enabled"`
    Chains      map[string]*Chain `json:"chains"`
}

type Chain struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Events      []ChainEvent `json:"events"`
    Trigger     string   `json:"trigger"` // event type to trigger chain
    ContinueOnFail bool  `json:"continue_on_fail"`
    Enabled     bool     `json:"enabled"`
}

type ChainEvent struct {
    EventType   string `json:"event_type"`
    SoundID     string `json:"sound_id"`
    Volume      float64 `json:"volume"`
    DelayMs     int    `json:"delay_ms"` // delay before this event
}
```

### Commands

```bash
/ccbell:chain list                  # List chains
/ccbell:chain create "Morning Alert" # Create chain
/ccbell:chain add event stop bundled:stop
/ccbell:chain add event subagent custom:complete --delay 1000
/ccbell:chain trigger stop          # Trigger chain
/ccbell:chain enable <id>           # Enable chain
/ccbell:chain disable <id>          # Disable chain
/ccbell:chain delete <id>           # Remove chain
/ccbell:chain test <id>             # Test chain
```

### Output

```
$ ccbell:chain list

=== Sound Event Chains ===

Status: Enabled
Chains: 2

[1] Morning Alert
    Trigger: stop
    Events: 3
    Continue on fail: Yes
    Enabled: Yes
    [Run] [Edit] [Export] [Delete]

    [1] stop (bundled:stop) - delay 0ms
    [2] subagent (custom:complete) - delay 1000ms
    [3] permission_prompt (bundled:permission) - delay 2000ms

    [Run] [Edit] [Export] [Delete]

[2] Priority Sequence
    Trigger: permission_prompt
    Events: 2
    Continue on fail: No
    Enabled: Yes
    [Run] [Edit] [Export] [Delete]

[Create]
```

---

## Audio Player Compatibility

Chains use existing audio player:
- Sequential `player.Play()` calls
- Same format support
- No player changes required

---

## Implementation

### Chain Execution

```go
type ChainExecutor struct {
    config  *ChainConfig
    player  *audio.Player
}

func (e *ChainExecutor) Execute(chainID string, triggerEvent string) error {
    chain, ok := e.config.Chains[chainID]
    if !ok {
        return fmt.Errorf("chain not found: %s", chainID)
    }

    if chain.Trigger != triggerEvent {
        return nil // Not triggered
    }

    for i, event := range chain.Events {
        // Delay before this event
        if event.DelayMs > 0 && i > 0 {
            time.Sleep(time.Duration(event.DelayMs) * time.Millisecond)
        }

        // Play sound
        path, err := e.player.ResolveSoundPath(event.SoundID, "")
        if err != nil {
            if !chain.ContinueOnFail {
                return fmt.Errorf("chain failed at event %d: %w", i, err)
            }
            continue
        }

        if err := e.player.Play(path, event.Volume); err != nil {
            if !chain.ContinueOnFail {
                return fmt.Errorf("playback failed at event %d: %w", i, err)
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Chain execution
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Chain config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
