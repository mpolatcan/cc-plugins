# Feature: Sound Event Chains

Define sequences of sounds that play in order.

## Summary

Create sound chains where multiple sounds play in sequence, with configurable delays between each.

## Motivation

- Notification escalation
- Multi-stage alerts
- Rich notification patterns

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Chain Types

| Type | Description | Example |
|------|-------------|---------|
| Sequential | Play sounds one after another | A → B → C |
| Parallel | Play multiple sounds together | A + B simultaneously |
| Conditional | Play based on conditions | If X then A else B |
| Loop | Repeat sequence N times | A → B → A → B... |

### Configuration

```go
type ChainConfig struct {
    Enabled     bool              `json:"enabled"`
    Chains      map[string]*Chain `json:"chains"`
}

type Chain struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Steps       []ChainStep `json:"steps"`
    Repeat      int      `json:"repeat"` // 0 = infinite
    ContinueOnFail bool  `json:"continue_on_fail"`
}

type ChainStep struct {
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume"` // 0-1, overrides chain default
    DelayMs     int     `json:"delay_ms"` // before this step
    Condition   string  `json:"condition,omitempty"` // "always", "first_only", "last_only"
}
```

### Commands

```bash
/ccbell:chain list                  # List chains
/ccbell:chain create "Escalate" --sounds stop:0.5,alert:0.7,urgent:1.0
/ccbell:chain add "Parallel Alert" --sounds alert1,alert2 --parallel
/ccbell:chain play <id>             # Play a chain
/ccbell:chain delete <id>           # Remove chain
/ccbell:chain test <id>             # Test chain
```

### Output

```
$ ccbell:chain list

=== Sound Event Chains ===

Chains: 3

[1] Escalate
    Steps: 3 (sequential)
    Repeat: 1
    [Play] [Edit] [Delete]

    [1] stop (0.5) → 500ms → [2] alert (0.7) → 500ms → [3] urgent (1.0)

[2] Parallel Alert
    Steps: 2 (parallel)
    [1] alert1 + [2] alert2 (simultaneous)

[3] Morning Routine
    Steps: 5 (sequential + loop)
    Repeat: 3
    [Play] [Edit] [Delete]

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Chain playback works with all audio players:
- Sequential: Uses existing playback with delays
- Parallel: Requires multiple player instances
- All players support non-blocking playback

---

## Implementation

### Chain Execution

```go
type ChainManager struct {
    config  *ChainConfig
    player  *audio.Player
}

func (m *ChainManager) Play(chainID string) error {
    chain, ok := m.config.Chains[chainID]
    if !ok {
        return fmt.Errorf("chain not found: %s", chainID)
    }

    for i := 0; i <= chain.Repeat || chain.Repeat == 0; i++ {
        if err := m.playSteps(chain.Steps, i); err != nil {
            if !chain.ContinueOnFail {
                return err
            }
        }
    }
    return nil
}

func (m *ChainManager) playSteps(steps []ChainStep, iteration int) error {
    for _, step := range steps {
        if !m.shouldPlayStep(step, iteration) {
            continue
        }

        if step.DelayMs > 0 {
            time.Sleep(time.Duration(step.DelayMs) * time.Millisecond)
        }

        volume := derefFloat(step.Volume, 0.5)
        if err := m.player.Play(step.Sound, volume); err != nil {
            return err
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

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Non-blocking playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Sound playback entry point
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Cooldown tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | afplay with delays |
| Linux | ✅ Supported | mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
