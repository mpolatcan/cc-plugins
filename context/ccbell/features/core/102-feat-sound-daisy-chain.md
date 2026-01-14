# Feature: Sound Daisy Chain

Chain sounds to play sequentially.

## Summary

Create chains of sounds that play in sequence for complex notifications.

## Motivation

- Multi-part notifications
- Attention-grabbing sequences
- Progressive alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Chain Types

| Type | Description | Example |
|------|-------------|---------|
| Linear | A -> B -> C | Alert -> Reminder -> End |
| Conditional | Play B if A fails | Fallback sounds |
| Parallel | A and B together | Layered sounds |

### Configuration

```go
type SoundChain struct {
    ID          string      `json:"id"`
    Name        string      `json:"name"`
    Steps       []*ChainStep `json:"steps"`
    OnComplete  string      `json:"on_complete"`  // command after chain
    OnFail      string      `json:"on_fail"`      // command if fails
    Repeat      int         `json:"repeat"`        // -1 = infinite
    Loop        bool        `json:"loop"`          // loop entire chain
}

type ChainStep struct {
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume"`
    DelayMs     int     `json:"delay_ms"`    // before playing
    DurationMs  int     `json:"duration_ms"` // max play time
    Required    bool    `json:"required"`    // fail chain if fails
    Condition   string  `json:"condition"`   // "previous_failed", "always"
}
```

### Commands

```bash
/ccbell:chain list                    # List chains
/ccbell:chain create alert-sequence   # Create chain
/ccbell:chain add step alert-sequence bundled:alert --delay 0
/ccbell:chain add step alert-sequence bundled:reminder --delay 1000
/ccbell:chain add step alert-sequence bundled:end --delay 500
/ccbell:chain run alert-sequence      # Run chain
/ccbell:chain enable alert-sequence   # Enable chain
/ccbell:chain bind stop alert-sequence # Bind to event
/ccbell:chain delete alert-sequence   # Remove chain
```

### Output

```
$ ccbell:chain list

=== Sound Chains ===

[1] Alert Sequence
    Steps: 3
    Total Duration: 2.5s
    Loop: No

    [1] bundled:alert (0ms delay)
    [2] bundled:reminder (1000ms delay)
    [3] bundled:end (500ms delay)

    Bound to: (none)
    Enabled: Yes
    [Run] [Edit] [Bind] [Delete]

[2] Progressive Alert
    Steps: 5
    Total Duration: 10s
    Loop: Yes

    [1] soft (0ms) -> [2] medium (2000ms) -> [3] loud (4000ms)...
    Bound to: permission_prompt
    Enabled: Yes
    [Run] [Edit] [Unbind] [Delete]

[Create New Chain]
```

---

## Audio Player Compatibility

Daisy chain uses existing audio player:
- Sequential `player.Play()` calls
- Same format support
- No player changes required

---

## Implementation

### Chain Execution

```go
func (c *ChainManager) Run(chainID string) error {
    chain, ok := c.chains[chainID]
    if !ok {
        return fmt.Errorf("chain not found: %s", chainID)
    }

    player := audio.NewPlayer(c.pluginRoot)

    for {
        stepNum := 0
        for _, step := range chain.Steps {
            stepNum++

            // Check condition
            if !c.shouldPlayStep(step, stepNum) {
                continue
            }

            // Delay before playing
            if step.DelayMs > 0 {
                time.Sleep(time.Duration(step.DelayMs) * time.Millisecond)
            }

            // Play sound
            path, err := player.ResolveSoundPath(step.Sound, "")
            if err != nil {
                if step.Required {
                    return fmt.Errorf("required sound failed: %s", step.Sound)
                }
                continue
            }

            if err := player.Play(path, step.Volume); err != nil {
                if step.Required {
                    return err
                }
                continue
            }

            // Wait for sound duration
            if step.DurationMs > 0 {
                time.Sleep(time.Duration(step.DurationMs) * time.Millisecond)
            }
        }

        // Check loop
        if !chain.Loop && chain.Repeat <= 0 {
            break
        }
        chain.Repeat--

        if chain.Repeat == 0 && !chain.Loop {
            break
        }
    }

    return nil
}
```

### Event Binding

```go
func (c *ChainManager) BindToEvent(chainID, eventType string) error {
    chain, ok := c.chains[chainID]
    if !ok {
        return fmt.Errorf("chain not found: %s", chainID)
    }

    // Update event config to use chain
    eventCfg := c.config.GetEventConfig(eventType)
    eventCfg.Sound = fmt.Sprintf("chain:%s", chainID)

    return c.config.Save()
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Sequential playback
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Sound paths

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
