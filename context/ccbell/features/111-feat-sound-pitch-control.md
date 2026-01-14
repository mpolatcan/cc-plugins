# Feature: Sound Pitch Control

Adjust pitch of sounds.

## Summary

Change the pitch of sounds for different effects.

## Motivation

- Sound customization
- Match other sounds
- Create variations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Pitch Options

| Option | Description | Range |
|--------|-------------|-------|
| Semitones | Pitch shift | -12 to +12 |
| Speed | Change playback speed | 0.5x to 2x |
| Formant | Preserve formants | boolean |

### Configuration

```go
type PitchConfig struct {
    Enabled     bool    `json:"enabled"`
    Semitones   float64 `json:"semitones"`   // -12 to +12
    Speed       float64 `json:"speed"`       // 0.5 to 2.0
    PreserveFormant bool `json:"preserve_formant"`
    Tempo       float64 `json:"tempo"`       // maintain tempo with pitch
}

type PitchPreset struct {
    Name      string  `json:"name"`
    Semitones float64 `json:"semitones"`
    Speed     float64 `json:"speed"`
}
```

### Commands

```bash
/ccbell:pitch set 2                 # +2 semitones
/ccbell:pitch set -2                # -2 semitones
/ccbell:pitch set speed 1.5         # 1.5x speed
/ccbell:pitch set tempo 1.2         # 1.2x tempo (faster)
/ccbell:pitch enable preserve       # Preserve formants
/ccbell:pitch apply input.aiff output.aiff --semitones 2
/ccbell:pitch preview               # Preview pitch change
```

### Output

```
$ ccbell:pitch set 2

=== Sound Pitch Control ===

Status: Enabled
Shift: +2 semitones (whole tone)
Speed: 1.0x (unchanged)
Formant Preservation: Off

Preview:
  Original: [██████████] 440Hz (A4)
  Shifted:  [██████████] 494Hz (B4)

[Apply] [Presets] [Fine-tune] [Reset]
```

---

## Audio Player Compatibility

Pitch control doesn't play sounds:
- Pre-processing with ffmpeg
- No player changes required
- Output is modified audio file

---

## Implementation

### FFmpeg Pitch Shift

```go
func (p *PitchManager) ApplyPitch(inputPath, outputPath string, config *PitchConfig) error {
    // Convert semitones to rate
    rate := math.Pow(2, config.Semitones/12.0)

    args := []string{"-y", "-i", inputPath}

    if config.PreserveFormant {
        // Use rubberband for better quality
        args = append(args, "-filter_complex",
            fmt.Sprintf("rubberband=pitch=%f:tempo=%f:formant=correct", rate, config.Tempo))
    } else {
        // Simple pitch shift using atempo
        args = append(args, "-filter_complex",
            fmt.Sprintf("atempo=%f,asetrate=%d", rate, int(44100*rate)))
    }

    args = append(args, outputPath)

    return exec.Command("ffmpeg", args...).Run()
}
```

### Tempo-Invariant Pitch

```go
func (p *PitchManager) applyPitchTempoFixed(inputPath, outputPath string, semitones float64) error {
    // Pitch shift without changing tempo
    rate := math.Pow(2, semitones/12.0)

    // Use rubberband for high quality
    args := []string{
        "-y", "-i", inputPath,
        "-filter_complex", fmt.Sprintf("rubberband=pitch=%f:tempo=1.0", rate),
        outputPath,
    }

    return exec.Command("ffmpeg", args...).Run()
}
```

### Presets

```go
var pitchPresets = map[string]PitchPreset{
    "lower_octave": {
        Name:      "Lower Octave",
        Semitones: -12,
        Speed:     1.0,
    },
    "lower_fifth": {
        Name:      "Perfect Fifth",
        Semitones: -7,
        Speed:     1.0,
    },
    "lower_step": {
        Name:      "Whole Tone Lower",
        Semitones: -2,
        Speed:     1.0,
    },
    "higher_step": {
        Name:      "Whole Tone Higher",
        Semitones: 2,
        Speed:     1.0,
    },
    "higher_octave": {
        Name:      "Higher Octave",
        Semitones: 12,
        Speed:     1.0,
    },
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Pitch shifting |
| rubberband | External tool | Free | High-quality pitch (optional) |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg atempo](https://ffmpeg.org/ffmpeg-filters.html#atempo)
- [Rubberband pitch shifter](https://breakfastquay.com/rubberband/)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
