# Feature: Sound Mixer

Mix multiple sounds together.

## Summary

Mix sounds together for layered notifications.

## Motivation

- Layer multiple sounds
- Create unique notifications
- Sound combinations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Mix Options

| Option | Description | Example |
|--------|-------------|---------|
| Overlay | Mix on top | Sound A + Sound B |
| Crossfade | Smooth transition | Fade A in, B out |
| Duck | Lower A when B plays | Priority mix |

### Configuration

```go
type MixConfig struct {
    Sounds       []MixSound `json:"sounds"`
    Output       string     `json:"output"`
    MixType      string     `json:"mix_type"`      // "overlay", "crossfade", "duck"
    MasterVolume float64    `json:"master_volume"`
    FadeInMs     int        `json:"fade_in_ms"`
    FadeOutMs    int        `json:"fade_out_ms"`
}

type MixSound struct {
    ID          string  `json:"id"`
    Volume      float64 `json:"volume"`
    StartOffset int     `json:"start_offset_ms"` // delay before playing
    Duration    int     `json:"duration_ms"`     // max duration
}
```

### Commands

```bash
/ccbell:mix sound1.aiff sound2.aiff -o output.aiff
/ccbell:mix sound1.aiff sound2.aiff --type overlay
/ccbell:mix sound1.aiff sound2.aiff --type crossfade --fade 500
/ccbell:mix sound1.aiff sound2.aiff --type duck --priority sound2
/ccbell:mix preset create "attention" sound1 sound2
/ccbell:mix preset use attention
```

### Output

```
$ ccbell:mix sound1.aiff sound2.aiff --type crossfade

=== Sound Mixer ===

Input:
  [1] sound1.aiff (1.2s, 80% volume)
  [2] sound2.aiff (0.8s, 100% volume)

Mix Type: Crossfade (500ms)

Timeline:
  0.0s: [████████████████████████] sound1 starts
  0.7s: [██████████████▓▓▓▓▓▓▓▓▓▓] crossfade
  1.2s: [▓▓▓▓▓▓▓▓▓▓██████████████] sound2 starts
  2.0s: [▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓] sound2 ends

Output Duration: 2.0s
[Create] [Preview] [Adjust] [Cancel]
```

---

## Audio Player Compatibility

Mixer doesn't play sounds:
- Uses ffmpeg for mixing
- No player changes required
- Output is mixed audio file

---

## Implementation

### FFmpeg Mixing

```go
func (m *Mixer) Mix(config *MixConfig) error {
    args := []string{"-y"}

    // Add inputs
    for _, sound := range config.Sounds {
        args = append(args, "-i", sound.Path)
    }

    // Build filter complex based on mix type
    filter := m.buildMixFilter(config)

    if filter != "" {
        args = append(args, "-filter_complex", filter)
        args = append(args, "-map", "[out]")
    } else {
        // Simple concatenation
        for i := range config.Sounds {
            args = append(args, "-map", fmt.Sprintf("%d:a", i))
        }
    }

    args = append(args, config.Output)

    return exec.Command("ffmpeg", args...).Run()
}

func (m *Mixer) buildMixFilter(config *MixConfig) string {
    switch config.MixType {
    case "crossfade":
        return fmt.Sprintf("[0:a][1:a]acrossfade=c=%d:o=%d[out]",
            config.FadeOutMs/1000, config.FadeOutMs/1000)
    case "duck":
        return fmt.Sprintf("[0:a][1:a]sidechaincompress=threshold=0.01:ratio=4[out]")
    default: // overlay
        return fmt.Sprintf("[0:a][1:a]amix=inputs=2:duration=longest[out]")
    }
}
```

### Timeline-based Mixing

```go
func (m *Mixer) mixTimeline(config *MixConfig) error {
    // Create timeline-based filter
    filter := ""

    for i, sound := range config.Sounds {
        // Apply volume
        filter += fmt.Sprintf("[%d:a]volume=%.2f[v%d];", i, sound.Volume, i)

        // Add delay if needed
        if sound.StartOffset > 0 {
            filter += fmt.Sprintf("[v%d]adelay=%d|%d[d%d];", i, sound.StartOffset, sound.StartOffset, i)
        }
    }

    // Combine all
    inputs := ""
    for i := range config.Sounds {
        if sound := config.Sounds[i]; sound.StartOffset > 0 {
            inputs += fmt.Sprintf("[d%d]", i)
        } else {
            inputs += fmt.Sprintf("[v%d]", i)
        }
    }
    filter += fmt.Sprintf("%samix=inputs=%d:duration=longest[out]", inputs, len(config.Sounds))

    return m.runFFmpegFilter(config.Sounds, filter, config.Output)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio mixing |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg amix](https://ffmpeg.org/ffmpeg-filters.html#amix)
- [FFmpeg acrossfade](https://ffmpeg.org/ffmpeg-filters.html#acrossfade)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
