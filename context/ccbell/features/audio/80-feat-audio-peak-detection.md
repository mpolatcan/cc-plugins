# Feature: Audio Peak Detection

Detect audio peaks for optimal playback timing.

## Summary

Analyze audio to find peak levels for timing-sensitive playback.

## Motivation

- Sync with visual cues at peaks
- Avoid missing quiet notifications
- Optimal volume adjustment

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Peak Analysis

```bash
# Get peak levels
ffmpeg -i input.aiff -af "volumedetect" -f null /dev/null

# Output:
# [Parsed_volumedetect_0 @ 0x...] mean_volume: -20.5 dB
# max_volume: -3.2 dB
# histogram_0: 6
# histogram_1: 80
# ...
```

### Implementation

```go
type PeakAnalysis struct {
    SoundPath       string
    MeanVolume      float64  // dB
    PeakVolume      float64  // dB
    PeakPosition    float64  // seconds
    DynamicRange    float64  // dB
    ClippingDetected bool
    SamplePeaks     []float64
}
```

### Commands

```bash
/ccbell:peak analyze bundled:stop
/ccbell:peak analyze bundled:stop --json
/ccbell:peak find bundled:stop     # Find peak position
/ccbell:peak compare sound1 sound2 # Compare peaks
/ccbell:peak normalize bundled:stop  # Normalize to peak
```

### Output

```
$ ccbell:peak analyze bundled:stop

=== Peak Analysis ===

Sound: bundled:stop
Duration: 1.234s

Peak Information:
  Peak volume: -3.2 dB
  Mean volume: -18.5 dB
  Dynamic range: 15.3 dB
  Peak position: 0.234s

Waveform:
                    ████
                ██████████
            ████████████████
        ████████████████████
    ████████████████████████
███████████████████████████████████

Peak marker: ▼ at 0.234s

Status: No clipping detected
Recommendation: Good dynamic range for notifications
```

### Peak-Based Triggers

```go
type PeakTriggerConfig struct {
    Enabled       bool    `json:"enabled"`
    TriggerAtPeak bool    `json:"trigger_at_peak"`
    MinPeakDb     float64 `json:"min_peak_db"`
    FallbackDelay string  `json:"fallback_delay"`
}
```

---

## Audio Player Compatibility

Peak detection uses ffprobe:
- Pre-play analysis
- No player changes required
- Can delay playback to peak position

---

## Implementation

### Peak Analysis

```go
func analyzePeak(audioPath string) (*PeakAnalysis, error) {
    cmd := exec.Command("ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", "-show_streams", audioPath)

    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    // Parse and extract peak information
    // Use volumedetect filter

    return &PeakAnalysis{
        SoundPath:   audioPath,
        PeakVolume:  parseMaxVolume(output),
        MeanVolume:  parseMeanVolume(output),
        PeakPosition: findPeakPosition(audioPath),
    }, nil
}
```

### Peak-Aligned Playback

```go
func (c *CCBell) playAtPeak(soundPath string, volume float64) error {
    analysis, _ := analyzePeak(soundPath)

    // Wait until peak position
    if c.peakConfig.TriggerAtPeak && analysis.PeakPosition > 0 {
        delay := analysis.PeakPosition * time.Second
        log.Debug("Waiting %v for peak", delay)
        time.Sleep(delay)
    }

    return c.player.Play(soundPath, volume)
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

- [FFmpeg volumedetect](https://ffmpeg.org/ffmpeg-filters.html#volumedetect)
- [Audio peak detection](https://en.wikipedia.org/wiki/Peak_(audio))

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffprobe available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
