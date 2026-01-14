# Feature: Sound Event Sequences

Define and play event sequences.

## Summary

Create named sequences of sounds to play together.

## Motivation

- Complex alerts
- Structured notifications
- Reusable patterns

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Sequence Components

| Component | Description | Example |
|-----------|-------------|---------|
| Sounds | Ordered list | sound1, sound2, sound3 |
| Intervals | Gap between sounds | 500ms, 1s |
| Volume | Per-sound volume | 0.5, 0.6, 0.7 |
| Repeat | Repeat sequence | 2x |

### Configuration

```go
type SequenceConfig struct {
    Enabled     bool              `json:"enabled"`
    Sequences   map[string]*Sequence `json:"sequences"`
}

type Sequence struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Sounds      []SequenceSound `json:"sounds"`
    Repeat      int      `json:"repeat"` // 1 = once, -1 = infinite
    IntervalMs  int      `json:"interval_ms"` // default gap
    Enabled     bool     `json:"enabled"`
}

type SequenceSound struct {
    SoundID     string `json:"sound_id"`
    Volume      float64 `json:"volume"`
    IntervalMs  int    `json:"interval_ms"` // override default
}
```

### Commands

```bash
/ccbell:sequence list               # List sequences
/ccbell:sequence create "Wake Up"   # Create sequence
/ccbell:sequence add bundled:stop   # Add sound
/ccbell:sequence add custom:alert volume=0.7
/ccbell:sequence set repeat 2       # Repeat twice
/ccbell:sequence set interval 500   # 500ms gap
/ccbell:sequence play "Wake Up"     # Play sequence
/ccbell:sequence delete <id>        # Remove sequence
/ccbell:sequence export <id>        # Export sequence
```

### Output

```
$ ccbell:sequence list

=== Sound Event Sequences ===

Status: Enabled
Sequences: 3

[1] Wake Up
    Sounds: 4
    Repeat: 1
    Interval: 500ms
    Enabled: Yes
    [Play] [Edit] [Export] [Delete]

    [1] bundled:stop (vol=0.5)
    [2] bundled:subagent (vol=0.5)
    [3] custom:alert (vol=0.7)
    [4] bundled:permission (vol=0.5)

    [Play] [Edit] [Export] [Delete]

[2] Attention Getter
    Sounds: 2
    Repeat: 3
    Interval: 200ms
    Enabled: Yes
    [Play] [Edit] [Export] [Delete]

[3] Gentle Reminder
    Sounds: 2
    Repeat: 1
    Interval: 1000ms
    Enabled: No
    [Play] [Edit] [Export] [Delete]

[Create]
```

---

## Audio Player Compatibility

Sequences use existing audio player:
- Sequential `player.Play()` calls
- Same format support
- No player changes required

---

## Implementation

### Sequence Playback

```go
type SequencePlayer struct {
    config  *SequenceConfig
    player  *audio.Player
}

func (p *SequencePlayer) Play(sequenceID string) error {
    seq, ok := p.config.Sequences[sequenceID]
    if !ok {
        return fmt.Errorf("sequence not found: %s", sequenceID)
    }

    repeatCount := seq.Repeat
    if repeatCount == 0 {
        repeatCount = 1
    }

    for r := 0; r < repeatCount || repeatCount == -1; r++ {
        if err := p.playSequence(seq); err != nil {
            return err
        }
    }

    return nil
}

func (p *SequencePlayer) playSequence(seq *Sequence) error {
    for i, sound := range seq.Sounds {
        // Resolve sound path
        path, err := p.player.ResolveSoundPath(sound.SoundID, "")
        if err != nil {
            return err
        }

        // Play sound
        if err := p.player.Play(path, sound.Volume); err != nil {
            return err
        }

        // Delay to next sound
        interval := sound.IntervalMs
        if interval == 0 {
            interval = seq.IntervalMs
        }

        if i < len(seq.Sounds)-1 && interval > 0 {
            time.Sleep(time.Duration(interval) * time.Millisecond)
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Sequence playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Sequence config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
