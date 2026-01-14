# Feature: Sound Equalizer

Equalizer for adjusting sound frequencies.

## Summary

Apply equalizer settings to sounds for frequency adjustment.

## Motivation

- Adjust sound characteristics
- Match different outputs
- Enhance clarity

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### EQ Bands

| Band | Frequency | Default |
|------|-----------|---------|
| Low | 60 Hz | 0 dB |
| Mid-Low | 250 Hz | 0 dB |
| Mid | 1 kHz | 0 dB |
| Mid-High | 4 kHz | 0 dB |
| High | 16 kHz | 0 dB |

### Configuration

```go
type EQConfig struct {
    Enabled     bool          `json:"enabled"`
    Preset      string        `json:"preset"`
    Bands       []EQBand      `json:"bands"`
    PerEvent    map[string]EQSettings `json:"per_event"`
}

type EQBand struct {
    Frequency int     `json:"frequency"` // Hz
    Gain      float64 `json:"gain"`      // dB (-12 to +12)
    Q         float64 `json:"q"`         // bandwidth
}

type EQPreset struct {
    Name    string    `json:"name"`
    Bands   []EQBand  `json:"bands"`
}
```

### Commands

```bash
/ccbell:eq enable                   # Enable EQ
/ccbell:eq disable                  # Disable EQ
/ccbell:eq preset bass              # Bass boost preset
/ccbell:eq preset vocal             # Vocal preset
/ccbell:eq preset flat              # Flat EQ
/ccbell:eq set 60 +6                # 60Hz: +6dB
/ccbell:eq set 1000 -3              # 1kHz: -3dB
/ccbell:eq show                     # Show EQ settings
/ccbell:eq apply input.aiff output.aiff
/ccbell:eq visual                   # Visual EQ display
```

### Output

```
$ ccbell:eq preset bass

=== Sound Equalizer ===

Status: Enabled
Preset: Bass Boost

Frequency Response:
   60Hz  [████████████████████████] +6dB
  250Hz  [████████████████████░░░░] +3dB
    1kHz  [██████████████████████░░] 0dB
    4kHz  [██████████████████████░░] 0dB
   16kHz  [██████████████████████░░] 0dB

Visual:
  ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░
  Low      Mid-Low    Mid    Mid-High  High

[Apply] [Presets] [Fine-tune] [Reset]
```

---

## Audio Player Compatibility

Equalizer doesn't play sounds:
- Pre-processing with ffmpeg
- No player changes required
- Output is modified audio file

---

## Implementation

### FFmpeg Equalizer

```go
func (e *EQManager) ApplyEQ(inputPath, outputPath string, config *EQConfig) error {
    filter := e.buildEQFilter(config)

    args := []string{"-y", "-i", inputPath}
    if filter != "" {
        args = append(args, "-af", filter)
    }
    args = append(args, outputPath)

    return exec.Command("ffmpeg", args...).Run()
}

func (e *EQManager) buildEQFilter(config *EQConfig) string {
    filters := []string{}

    for _, band := range config.Bands {
        filters = append(filters, fmt.Sprintf("equalizer=f=%d:g=%.1f:Q=%.1f",
            band.Frequency, band.Gain, band.Q))
    }

    return strings.Join(filters, ",")
}
```

### Presets

```go
var eqPresets = map[string]EQPreset{
    "flat": {
        Name: "Flat",
        Bands: []EQBand{
            {Frequency: 60, Gain: 0, Q: 1},
            {Frequency: 250, Gain: 0, Q: 1},
            {Frequency: 1000, Gain: 0, Q: 1},
            {Frequency: 4000, Gain: 0, Q: 1},
            {Frequency: 16000, Gain: 0, Q: 1},
        },
    },
    "bass": {
        Name: "Bass Boost",
        Bands: []EQBand{
            {Frequency: 60, Gain: 6, Q: 1},
            {Frequency: 250, Gain: 3, Q: 1},
            {Frequency: 1000, Gain: 0, Q: 1},
            {Frequency: 4000, Gain: 0, Q: 1},
            {Frequency: 16000, Gain: 0, Q: 1},
        },
    },
    "vocal": {
        Name: "Vocal",
        Bands: []EQBand{
            {Frequency: 60, Gain: -3, Q: 1},
            {Frequency: 250, Gain: 0, Q: 1},
            {Frequency: 1000, Gain: 3, Q: 1},
            {Frequency: 4000, Gain: 2, Q: 1},
            {Frequency: 16000, Gain: 0, Q: 1},
        },
    },
    "treble": {
        Name: "Treble Boost",
        Bands: []EQBand{
            {Frequency: 60, Gain: 0, Q: 1},
            {Frequency: 250, Gain: 0, Q: 1},
            {Frequency: 1000, Gain: 0, Q: 1},
            {Frequency: 4000, Gain: 3, Q: 1},
            {Frequency: 16000, Gain: 5, Q: 1},
        },
    },
}
```

### Visual Display

```go
func (e *EQManager) renderVisual(config *EQConfig) string {
    lines := []string{}

    for _, band := range config.Bands {
        bar := e.gainToBar(band.Gain)
        line := fmt.Sprintf("%6dHz [%s] %+.1fdB", band.Frequency, bar, band.Gain)
        lines = append(lines, line)
    }

    return strings.Join(lines, "\n")
}

func (e *EQManager) gainToBar(gain float64) string {
    blocks := int((gain + 12) / 24 * 20) // map -12..+12 to 0..20
    return strings.Repeat("█", blocks) + strings.Repeat("░", 20-blocks)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio equalizer |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg equalizer](https://ffmpeg.org/ffmpeg-filters.html#equalizer)
- [Audio EQ](https://en.wikipedia.org/wiki/Equalization_(audio))

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
