# Feature: Sound Randomization

Play random sounds from a pool for each notification event.

## Summary

Instead of a single sound per event, allow users to define multiple sounds that are randomly selected when an event triggers. This adds variety and helps users recognize different events even without looking.

## Motivation

- Reduces notification fatigue from repetitive sounds
- Better event recognition: users learn to associate specific sounds with events
- Fun factor: variety makes notifications more engaging

## Technical Feasibility

### Current State

ccbell already supports per-event sounds:
```json
{
  "events": {
    "stop": "bundled:stop"
  }
}
```

### Required Changes

| Component | Change |
|-----------|--------|
| Config Schema | Change `sound` to `sounds` (array) for each event |
| Selection Logic | Random index from array when event triggers |
| UI/Config | Multi-select sound picker in configure command |

### Implementation

#### Config Change

```json
{
  "events": {
    "stop": {
      "sounds": [
        "bundled:stop",
        "bundled:stop_alt1",
        "custom:/path/to/custom1.wav",
        "custom:/path/to/custom2.mp3"
      ],
      "weight": [1, 1, 1, 1]  // Optional: weighted random
    }
  }
}
```

#### Random Selection Logic

```go
func (c *CCBell) playRandomSound(event string) error {
    eventConfig := c.config.Events[event]
    if len(eventConfig.Sounds) == 0 {
        return fmt.Errorf("no sounds configured for %s", event)
    }

    // Simple random
    idx := rand.Intn(len(eventConfig.Sounds))

    // Weighted random (if weights configured)
    if len(eventConfig.Weights) > 0 {
        idx = weightedRandom(eventConfig.Weights)
    }

    sound := eventConfig.Sounds[idx]
    return c.playSound(sound)
}
```

#### Weighted Random

```go
func weightedRandom(weights []int) int {
    total := 0
    for _, w := range weights {
        total += w
    }
    r := rand.Intn(total)
    cumulative := 0
    for i, w := range weights {
        cumulative += w
        if r < cumulative {
            return i
        }
    }
    return len(weights) - 1
}
```

## Configuration

### Command: `/ccbell:configure` → Sound Selection

```
Select sounds for 'stop' event:
  Current: bundled:stop
  [1] Add another sound...
  [2] Remove sound
  [3] Shuffle order
  [4] Configure weights
  [5] Done

Add sound:
  [1] Bundled sounds
  [2] Custom sound file
  [3] URL

Selected sounds (random order):
  1. bundled:stop (weight: 1)
  2. custom:/Users/me/sounds/bell2.wav (weight: 2)
  3. https://example.com/alert.mp3 (weight: 1)
```

### Config Schema

```json
{
  "type": "object",
  "properties": {
    "events": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "properties": {
          "sounds": {
            "type": "array",
            "items": { "type": "string" }
          },
          "weights": {
            "type": "array",
            "items": { "type": "number", "minimum": 0 },
            "minItems": 0
          },
          "shuffle": { "type": "boolean" }
        }
      }
    }
  }
}
```

### Example Config

```json
{
  "events": {
    "stop": {
      "sounds": [
        "bundled:stop",
        "custom:/Users/me/sounds/chime1.aiff",
        "custom:/Users/me/sounds/chime2.aiff"
      ],
      "weights": [3, 1, 1],
      "shuffle": true
    },
    "permission_prompt": {
      "sounds": [
        "custom:/Users/me/sounds/ding1.wav",
        "custom:/Users/me/sounds/ding2.wav",
        "custom:/Users/me/sounds/ding3.wav"
      ],
      "weights": [1, 1, 1]
    }
  }
}
```

## Audio Format Support

| Format | via Native Player | via Go Library |
|--------|-------------------|----------------|
| AIFF | ✅ macOS | ❌ (convert needed) |
| WAV | ✅ | ✅ (oto + go-audio) |
| MP3 | ❌ (macOS) | ✅ (oto + go-minimp3) |
| M4A | ❌ | ✅ (requires decoder) |
| OGG | ❌ | ✅ (oto + vorbis) |

**Recommendation:** Use native players (afplay, paplay) for bundled AIFF files. Use Go libraries for custom sounds to support MP3/WAV.

## Commands

### Test Random Sounds

```bash
/ccbell:test stop --random
Plays random sound from stop pool

/ccbell:test stop --all
Plays all sounds in stop pool sequentially
```

### Manage Sound Pools

```bash
/ccbell:sounds list stop
stop: 3 sounds
  1. bundled:stop (weight: 3)
  2. custom:/path/chime1.aiff (weight: 1)
  3. custom:/path/chime2.aiff (weight: 1)

/ccbell:sounds add stop custom:/path/new-sound.wav
/ccbell:sounds remove stop 2
/ccbell:sounds weights stop 5 1 1
```

## UI Mockup (Configure Flow)

```
=== ccbell:configure ===

Current profile: default

Events:
[1] stop          - 3 sounds (weights: 3/1/1)
[2] permission    - 1 sound
[3] idle          - 1 sound
[4] subagent      - 2 sounds (weights: 1/1)

Select event to configure (1-4): 1

=== Configure 'stop' sounds ===

Sounds (will play randomly):
  1. [X] bundled:stop        [weight: 3] [test]
  2. [X] custom:chime1.aiff  [weight: 1] [test] [remove]
  3. [X] custom:chime2.aiff  [weight: 1] [test] [remove]

Actions:
  [a] Add sound
  [w] Configure weights
  [s] Shuffle mode
  [d] Done

Select action: a
  [1] Bundled sounds
  [2] Custom file
  [3] URL

Sound source: 2
File path: /Users/me/sounds/ding.wav
Added 'custom:/Users/me/sounds/ding.wav'
Weight (default 1): 1

Sounds (will play randomly):
  1. [X] bundled:stop        [weight: 3] [test]
  2. [X] custom:chime1.aiff  [weight: 1] [test] [remove]
  3. [X] custom:chime2.aiff  [weight: 1] [test] [remove]
  4. [X] custom:ding.wav     [weight: 1] [test] [remove]

Select action: d

Events:
[1] stop          - 4 sounds
...
```

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Too many sounds bloat config | Limit max sounds per event (e.g., 10) |
| Users forget which sounds are configured | Always show pool in status command |
| Randomness feels unpredictable | Add "weighted" mode for favorites |
| Audio format issues | Fallback to first working sound |

## Future Enhancements

- **Sound categories:** Group sounds by mood (energetic, calm, urgent)
- **Time-based selection:** Different pools for day/night
- **Learning:** Track which sounds user responds to, weight accordingly
- **Seasonal packs:** Halloween, Christmas sound pools

## Dependencies

| Dependency | Purpose | Link |
|------------|---------|------|
| go-audio/wav | WAV decoding | `github.com/go-audio/wav` |
| go-minimp3 | MP3 decoding | `github.com/cowork-ai/go-minimp3` |
| ebitengine/oto | Cross-platform playback | `github.com/ebitengine/oto/v3` |
