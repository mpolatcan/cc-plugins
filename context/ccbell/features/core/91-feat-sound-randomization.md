# Feature: Sound Randomization

Play random sounds for events.

## Summary

Randomly select from a pool of sounds for notification variety.

## Motivation

- Avoid notification fatigue
- Add variety to notifications
- Discover preferred sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Randomization Types

| Type | Description | Example |
|------|-------------|---------|
| Pool | Choose from sound pool | ["sound1", "sound2", "sound3"] |
| Weighted | Probabilistic selection | {"sound1": 0.5, "sound2": 0.3, "sound3": 0.2} |
| Sequential | Cycle through sounds | Round-robin order |
| Smart | Based on time/context | Day: soft, Night: silent |

### Configuration

```go
type RandomConfig struct {
    Enabled      bool              `json:"enabled"`
    Type         string            `json:"type"` // "pool", "weighted", "sequential"
    Pool         []string          `json:"pool"`        // sound IDs
    Weights      map[string]float64 `json:"weights"`     // sound -> probability
    SequentialIndex int             `json:"seq_index"`   // for sequential
    ExcludeLast  int                `json:"exclude_last"` // don't repeat last N
    MinInterval  int                `json:"min_interval"` // min plays before repeat
}

type RandomState struct {
    LastPlayed   string    `json:"last_played"`
    PlayCount    int       `json:"play_count"`
    SequentialIdx int      `json:"sequential_index"`
}
```

### Commands

```bash
/ccbell:random enable                  # Enable for all events
/ccbell:random disable                 # Disable randomization
/ccbell:random pool stop sound1 sound2 sound3
/ccbell:random weighted stop sound1:0.5 sound2:0.3 sound3:0.2
/ccbell:random add stop sound4         # Add to pool
/ccbell:random remove stop sound4      # Remove from pool
/ccbell:random list stop               # Show pool
/ccbell:random sequential stop         # Sequential mode
/ccbell:random test                    # Preview random selection
```

### Output

```
$ ccbell:random list stop

=== Random Pool for 'stop' ===

Pool: 5 sounds
Type: Weighted

[1] bundled:stop        40% ████████████████
[2] bundled:soft        30% ████████████
[3] custom:bell         15% ██████
[4] custom:chime        10% ████
[5] bundled:gentle       5% ██

Last played: bundled:soft (2 plays ago)
Sequential index: 2/5

[Edit] [Test] [Reset] [Disable]
```

---

## Audio Player Compatibility

Randomization uses existing audio player:
- Selects sound path, then calls `player.Play()`
- Same format support
- No player changes required

---

## Implementation

### Weighted Selection

```go
func (r *RandomManager) Select(config *RandomConfig) (string, error) {
    if len(config.Pool) == 0 {
        return "", fmt.Errorf("empty sound pool")
    }

    // Handle exclude last
    if config.ExcludeLast > 0 && r.state.LastPlayed != "" {
        pool := filterLastN(config.Pool, r.state.LastPlayed, config.ExcludeLast)
        config.Pool = pool
    }

    switch config.Type {
    case "weighted":
        return r.weightedSelect(config)
    case "sequential":
        return r.sequentialSelect(config)
    case "pool":
        return r.randomSelect(config)
    default:
        return r.randomSelect(config)
    }
}

func (r *RandomManager) weightedSelect(config *RandomConfig) (string, error) {
    rand := rand.Float64()
    cumulative := 0.0

    for _, sound := range config.Pool {
        cumulative += config.Weights[sound]
        if rand <= cumulative {
            r.updateState(sound)
            return sound, nil
        }
    }

    // Fallback to last sound
    return config.Pool[len(config.Pool)-1], nil
}
```

### State Tracking

```go
func (r *RandomManager) updateState(playedSound string) {
    r.state.LastPlayed = playedSound
    r.state.PlayCount++
    r.state.SequentialIdx = (r.state.SequentialIdx + 1) % len(r.config.Pool)
    r.saveState()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Go standard library (math/rand) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
