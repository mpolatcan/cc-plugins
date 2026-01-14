# Feature: Sound Event Randomization

Play random sounds from a configured set.

## Summary

Randomly select and play sounds from a pool for variety and surprise.

## Motivation

- Prevent notification fatigue
- Add variety to alerts
- Dynamic sound selection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Randomization Types

| Type | Description | Example |
|------|-------------|---------|
| Uniform | Equal probability | Any sound equally likely |
| Weighted | Probabilistic selection | Sound A: 50%, B: 30%, C: 20% |
| Sequential | Cycle through list | A → B → C → A... |
| Adaptive | Based on time/context | Different day vs night sounds |

### Configuration

```go
type RandomConfig struct {
    Enabled     bool              `json:"enabled"`
    Pools       map[string]*SoundPool `json:"pools"`
    DefaultPool string            `json:"default_pool"`
}

type SoundPool struct {
    ID          string        `json:"id"`
    Name        string        `json:"name"`
    Sounds      []PoolSound   `json:"sounds"`
    Selection   string        `json:"selection"` // "random", "weighted", "sequential", "adaptive"
    RememberLast bool         `json:"remember_last"` // Don't repeat immediately
}

type PoolSound struct {
    Sound       string  `json:"sound"`
    Weight      float64 `json:"weight"` // For weighted selection
    TimeOfDay   string  `json:"time_of_day,omitempty"` // "day", "night", "any"
}
```

### Commands

```bash
/ccbell:random list                # List sound pools
/ccbell:random create "Alerts" --sounds alert1,alert2,alert3 --weight 1,1,1
/ccbell:random create "Day Night" --sounds day:day,night:night --adaptive
/ccbell:random pool <event>        # Set pool for an event
/ccbell:random test <pool>         # Play random sound from pool
/ccbell:random history             # Show play history
```

### Output

```
$ ccbell:random list

=== Sound Event Randomization ===

Pools: 2

[1] Alerts
    Sounds: 3
    Selection: weighted
    Remember Last: Yes
    [Play Random] [Edit] [Delete]

    alert1 (weight: 1.0)
    alert2 (weight: 1.0)
    alert3 (weight: 1.0)

[2] Day Night
    Sounds: 2
    Selection: adaptive
    [Play Random] [Edit] [Delete]

    day (time: day)
    night (time: night)

Event Assignments:
  stop → Alerts
  permission_prompt → Day Night

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Randomization doesn't play sounds:
- Selection feature only
- No player changes required

---

## Implementation

### Random Selection

```go
type RandomManager struct {
    config   *RandomConfig
    lastPlayed map[string]string // Track last per pool
    mutex    sync.Mutex
    rng      *rand.Rand
}

func (m *RandomManager) Select(poolID string) (string, error) {
    pool, ok := m.config.Pools[poolID]
    if !ok {
        return "", fmt.Errorf("pool not found: %s", poolID)
    }

    // Filter by time of day for adaptive selection
    available := m.filterByTime(pool.Sounds)

    // Remove last played if required
    if pool.RememberLast && len(available) > 1 {
        last := m.lastPlayed[poolID]
        available = m.removeSound(available, last)
    }

    switch pool.Selection {
    case "weighted":
        return m.weightedSelect(available)
    case "sequential":
        return m.sequentialSelect(poolID, available)
    default:
        return m.randomSelect(available)
    }
}

func (m *RandomManager) weightedSelect(sounds []PoolSound) string {
    total := 0.0
    for _, s := range sounds {
        total += s.Weight
    }

    r := m.rng.Float64() * total
    cumulative := 0.0
    for _, s := range sounds {
        cumulative += s.Weight
        if r <= cumulative {
            return s.Sound
        }
    }
    return sounds[0].Sound // Fallback
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go math/rand |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event configuration
- [Player resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound path resolution

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
