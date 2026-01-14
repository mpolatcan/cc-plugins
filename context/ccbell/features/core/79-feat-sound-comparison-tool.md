# Feature: Sound Comparison Tool

Compare two sounds side by side.

## Summary

Compare sound characteristics between two audio files for selection or analysis.

## Motivation

- Choose between similar sounds
- Debug sound differences
- A/B testing for notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Comparison Data

| Property | Sound A | Sound B | Difference |
|----------|---------|---------|------------|
| Duration | 1.234s | 1.567s | +0.333s |
| File Size | 245 KB | 312 KB | +67 KB |
| Format | AIFF | WAV | - |
| Sample Rate | 44100 | 48000 | +3900 |
| Bit Depth | 16 | 24 | +8 |
| Volume (RMS) | -18dB | -15dB | +3dB |

### Implementation

```go
type SoundComparison struct {
    SoundA       string            `json:"sound_a"`
    SoundB       string            `json:"sound_b"`
    ComparedAt   time.Time         `json:"compared_at"`
    Differences  []PropertyDiff    `json:"differences"`
    Similarity   float64           `json:"similarity_percentage"`
}

type PropertyDiff struct {
    Property    string `json:"property"`
    ValueA      string `json:"value_a"`
    ValueB      string `json:"value_b"`
    Difference  string `json:"difference"`
}
```

### Commands

```bash
/ccbell:compare sound1.aiff sound2.aiff
/ccbell:compare bundled:stop custom:notification
/ccbell:compare bundled:stop --json    # JSON output
/ccbell:compare bundled:stop --verbose # Detailed
/ccbell:compare bundled:stop --visual  # ASCII visualization
```

### Output

```
$ ccbell:compare bundled:stop custom:notification

=== Sound Comparison ===

Sound A: bundled:stop
Sound B: custom:notification

┌──────────────────┬──────────────────┬─────────────┐
│ Property         │ A                │ B           │
├──────────────────┼──────────────────┼─────────────┤
│ Duration         │ 1.234s           │ 1.567s      │ +0.333s
│ File Size        │ 245 KB           │ 312 KB      │ +67 KB
│ Format           │ AIFF             │ WAV         │ -
│ Sample Rate      │ 44100 Hz         │ 48000 Hz    │ +3900 Hz
│ Bit Depth        │ 16-bit           │ 24-bit      │ +8-bit
│ Volume (RMS)     │ -18.5 dB         │ -15.2 dB    │ +3.3 dB
│ Peak Volume      │ -3.2 dB          │ -1.8 dB     │ +1.4 dB
│ Channels         │ Mono             │ Stereo      │ -
└──────────────────┴──────────────────┴─────────────┘

Similarity: 78.5%
Visual comparison:

A: ▁▂▃▂▁▁▂▃▄▄▃▂▁▁▁▁▁▁▁
B: ▁▂▃▂▁▁▂▃▄▄▃▂▁▁▂▃▂▁▁▁▁▁▁

Recommendation: Sound B is louder but larger
```

---

## Audio Player Compatibility

Sound comparison doesn't play sounds:
- Uses ffprobe for analysis
- No player changes required
- Preview uses existing player

---

## Implementation

### Property Extraction

```go
func compareSounds(pathA, pathB string) (*SoundComparison, error) {
    infoA, _ := getSoundInfo(pathA)
    infoB, _ := getSoundInfo(pathB)

    comparison := &SoundComparison{
        SoundA:     pathA,
        SoundB:     pathB,
        ComparedAt: time.Now(),
    }

    // Duration
    comparison.Differences = append(comparison.Differences, PropertyDiff{
        Property: "Duration",
        ValueA:   infoA.Duration.String(),
        ValueB:   infoB.Duration.String(),
        Difference: formatDurationDiff(infoA.Duration, infoB.Duration),
    })

    // File size
    comparison.Differences = append(comparison.Differences, PropertyDiff{
        Property: "File Size",
        ValueA:   formatSize(infoA.FileSize),
        ValueB:   formatSize(infoB.FileSize),
        Difference: formatSizeDiff(infoA.FileSize, infoB.FileSize),
    })

    // Calculate similarity
    comparison.Similarity = calculateSimilarity(infoA, infoB)

    return comparison, nil
}
```

### Visual Waveform

```go
func generateWaveformComparison(pathA, pathB string, width int) (string, error) {
    samplesA, _ := getSamples(pathA, width)
    samplesB, _ := getSamples(pathB, width)

    linesA := make([]string, len(samplesA[0]))
    linesB := make([]string, len(samplesB[0]))

    for i := 0; i < width; i++ {
        linesA[i] = generateBar(int(samplesA[0][i] * 8))
        linesB[i] = generateBar(int(samplesB[0][i] * 8))
    }

    return fmt.Sprintf("A: %s\nB: %s", strings.Join(linesA, ""), strings.Join(linesB, "")), nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffprobe | External tool | Free | Part of ffmpeg |

---

## References

### Research Sources

- [ffprobe JSON output](https://ffmpeg.org/ffprobe.html)
- [Audio metadata fields](https://wiki.hydrogenaud.io/index.php?title=Tagging_FAQ)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffprobe available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
