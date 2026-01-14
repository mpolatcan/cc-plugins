# Feature: Sound Chaining

Play multiple sounds sequentially for a single notification event.

## Summary

Define a sequence of sounds that play one after another when an event triggers, creating more elaborate notification patterns.

## Motivation

- Create distinct notification patterns for different event types
- Add emphasis with multi-part sounds (e.g., ding-dong for permission)
- Support "escalating" alerts for critical events

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Current Audio Player Analysis

The current `internal/audio/player.go` uses non-blocking playback:
- `cmd.Start()` - Returns immediately
- No built-in chaining

**Key Finding**: Sound chaining can be implemented by calling `Play()` multiple times with delays.

### Implementation

```go
func (p *Player) PlayChain(sounds []string, volume float64, delay time.Duration) error {
    for i, soundPath := range sounds {
        if err := p.Play(soundPath, volume); err != nil {
            return fmt.Errorf("sound %d failed: %w", i, err)
        }
        if i < len(sounds)-1 {
            time.Sleep(delay)
        }
    }
    return nil
}
```

### Configuration

```json
{
  "events": {
    "permission_prompt": {
      "sound_chain": [
        "bundled:ding",
        "bundled:dong"
      ],
      "chain_delay": "500ms",
      "volume": 0.7
    }
  }
}
```

**Note**: `sound_chain` replaces `sound` for chained events.

### Commands

```bash
/ccbell:configure stop sound-chain bundled:chime1,bundled:chime2
/ccbell:test stop --chain    # Test the sound chain
```

---

## Audio Player Compatibility

Sound chaining uses existing audio players:
- Calls `Play()` for each sound in sequence
- Same format support as individual sounds
- No changes to audio player required

---

## Implementation

### Config Changes

```go
type Event struct {
    Enabled   *bool     `json:"enabled,omitempty"`
    Sound     string    `json:"sound,omitempty"`      // Single sound (legacy)
    SoundChain []string `json:"sound_chain,omitempty"` // Chain of sounds
    ChainDelay string   `json:"chain_delay,omitempty"` // Delay between sounds
    Volume    *float64  `json:"volume,omitempty"`
    Cooldown  *int      `json:"cooldown,omitempty"`
}
```

### Play Logic

```go
func (c *CCBell) playEvent(eventType string) error {
    eventCfg := c.config.GetEventConfig(eventType)

    // Use chain or single sound
    if len(eventCfg.SoundChain) > 0 {
        delay := 500 * time.Millisecond
        if eventCfg.ChainDelay != "" {
            d, _ := time.ParseDuration(eventCfg.ChainDelay)
            delay = d
        }
        return c.player.PlayChain(eventCfg.SoundChain, *eventCfg.Volume, delay)
    }

    return c.player.Play(eventCfg.Sound, *eventCfg.Volume)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Uses existing audio player |

---

## References

### ccbell Implementation Research

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - `Play()` method to call in sequence
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event struct to extend
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) - Add validation for chain

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via afplay |
| Linux | ✅ Supported | Via mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
