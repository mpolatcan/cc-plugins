# Feature: Audio Spectrum Analyzer

Visual display of audio frequency spectrum during playback.

## Summary

Display real-time frequency analysis of notification sounds during preview.

## Motivation

- Visualize sound characteristics
- Debug audio quality issues
- Fun visual feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Spectrum Visualization

| Tool | Output | Platform |
|------|--------|----------|
| FFmpeg + script | ASCII art | macOS, Linux |
| SoX | ASCII art | macOS, Linux |
| Custom Go | Terminal UI | Cross-platform |

### FFmpeg Approach

```bash
# Show frequency data
ffmpeg -i sound.aiff -lavfi "showwavespic=colors=white" -frames:v 1 waveform.png

# Real-time spectrum (with visualization tool)
ffplay -i sound.aiff -showmode 1  # Shows spectrum
```

### ASCII Spectrum

```go
type SpectrumConfig struct {
    Width     int
    Height    int
    Character string
}

func generateSpectrumASCII(audioPath string, cfg *SpectrumConfig) (string, error) {
    // Get frequency data via ffprobe
    cmd := exec.Command("ffprobe", "-v", "quiet",
        "-show_entries", "frame=pkt_pts_time,pts",
        "-of", "csv=p=0", audioPath)

    // Process frequency data and generate ASCII bars
    bars := make([]string, cfg.Width)
    for i := 0; i < cfg.Width; i++ {
        bars[i] = generateBar(i, cfg.Height)
    }

    return strings.Join(bars, "\n"), nil
}
```

### Commands

```bash
/ccbell:spectrum preview bundled:stop     # Show spectrum
/ccbell:spectrum preview bundled:stop --width 60
/ccbell:spectrum compare sound1.aiff sound2.aiff
/ccbell:test all --spectrum               # Show spectrum during test
```

### Output

```
$ ccbell:spectrum preview bundled:stop

Sound: bundled:stop
Duration: 1.234s

                    ██████
                ████████████
            ████████████████
        ████████████████████
    ████████████████████████
████████████████████████████████████████████

Frequency Range: 20Hz - 20kHz
Peak: -3.2 dB
RMS: -18.5 dB
```

---

## Audio Player Compatibility

Spectrum analysis uses ffprobe/ffmpeg:
- Pre-play analysis or parallel visualization
- Doesn't modify audio player
- No player changes required

---

## Implementation

### Data Collection

```go
func getFrequencyData(audioPath string) ([]float64, error) {
    cmd := exec.Command("ffprobe", "-v", "quiet",
        "-show_entries", "frame=pkt_pts_time,pts",
        "-of", "csv=p=0", audioPath)

    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    // Parse and process frequency data
    return processFrequencyData(output), nil
}
```

### ASCII Bar Generation

```go
func generateBar(frequencyIndex, height int) string {
    levels := []string{
        " ",
        "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█",
    }

    level := int(float64(height) * getAmplitude(frequencyIndex))
    if level >= len(levels) {
        level = len(levels) - 1
    }

    return levels[level]
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

- [FFmpeg showwavespic](https://ffmpeg.org/ffmpeg-filters.html#showwavespic)
- [Audio frequency analysis](https://en.wikipedia.org/wiki/Frequency_analysis)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
