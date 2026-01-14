# Feature: Sound Trimming

Trim sound files to desired duration.

## Summary

Cut audio files to specific start/end times for shorter notifications.

## Motivation

- Create shorter notifications
- Remove silence
- Extract segments

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Trim Options

| Option | Description | Example |
|--------|-------------|---------|
| Start offset | Skip beginning | "0.5s", "1.5s" |
| End offset | Cut from end | "-1s", "-0.5s" |
| Duration | Fixed length | "2s", "500ms" |
| Remove silence | Trim silence | auto-detect |

### Configuration

```go
type TrimConfig struct {
    StartOffset  string  `json:"start_offset"`  // "0s", "500ms", or empty
    EndOffset    string  `json:"end_offset"`    // "0s", "-1s", or empty
    MaxDuration  string  `json:"max_duration"`  // "2s", max length
    RemoveSilence bool   `json:"remove_silence"` // trim silent portions
    SilenceThreshold float64 `json:"silence_threshold"` // dB
    SilenceMaxDuration string `json:"silence_max_duration"` // max trim
    FadeIn       string  `json:"fade_in"`       // "10ms"
    FadeOut      string  `json:"fade_out"`      // "50ms"
}
```

### Commands

```bash
/ccbell:trim input.aiff output.aiff --start 0.5s --end -0.5s
/ccbell:trim input.aiff output.aiff --duration 1s
/ccbell:trim input.aiff output.aiff --remove-silence
/ccbell:trim input.aiff --start 0.5s --end -0.5s --play
/ccbell:trim batch "*.aiff" --max-duration 2s
/ccbell:trim preview input.aiff --start 0.5s --end -0.5s
```

### Output

```
$ ccbell:trim input.aiff output.aiff --start 0.5s --end -0.5s

=== Sound Trimming ===

Input: input.aiff (1.234s)
Output: output.aiff

Settings:
  Start: 0.5s
  End: -0.5s (from end)
  Duration: 0.734s

Preview:
  [======|--------] 0.5s / 1.234s
  ▼ Marker at start (0.5s)      ▲ Marker at end (0.734s)

[Trim] [Adjust Start] [Adjust End] [Cancel]
```

---

## Audio Player Compatibility

Trimming doesn't play sounds:
- File editing feature
- Uses ffmpeg for trimming
- No player changes required

---

## Implementation

### FFmpeg Trimming

```go
func (t *Trimmer) Trim(inputPath, outputPath string, config *TrimConfig) error {
    args := []string{"-y", "-i", inputPath}

    // Build filter for trimming
    filters := []string{}

    // Trim from start
    if config.StartOffset != "" {
        filters = append(filters, fmt.Sprintf("atrim=start=%s", config.StartOffset))
    }

    // Trim from end (set duration)
    if config.MaxDuration != "" {
        filters = append(filters, fmt.Sprintf("atrim=duration=%s", config.MaxDuration))
    } else if config.EndOffset != "" {
        // Calculate actual duration
        duration := getDuration(inputPath)
        endSec := parseDuration(config.EndOffset)
        durationSec := duration - endSec
        if config.StartOffset != "" {
            startSec := parseDuration(config.StartOffset)
            durationSec = durationSec - startSec
        }
        filters = append(filters, fmt.Sprintf("atrim=0:%f", durationSec))
    }

    // Remove silence
    if config.RemoveSilence {
        filters = append(filters, fmt.Sprintf("silenceremove=start_threshold=%g:stop_duration=%s:stop_threshold=%g",
            config.SilenceThreshold, config.SilenceMaxDuration, config.SilenceThreshold))
    }

    // Add fades
    if config.FadeIn != "" {
        filters = append(filters, fmt.Sprintf("afade=t=in:ss=0:d=%s", config.FadeIn))
    }
    if config.FadeOut != "" {
        dur := getDuration(outputPath)
        filters = append(filters, fmt.Sprintf("afade=t=out:st=%s:d=%s", dur-config.FadeOut, config.FadeOut))
    }

    if len(filters) > 0 {
        args = append(args, "-af", strings.Join(filters, ","))
    }

    args = append(args, outputPath)

    return exec.Command("ffmpeg", args...).Run()
}
```

### Silence Detection

```go
func (t *Trimmer) detectSilence(audioPath string) ([]SilenceRegion, error) {
    cmd := exec.Command("ffmpeg", "-i", audioPath,
        "-af", "silencedetect=noise=-30dB:d=0.5",
        "-f", "null", "-")

    output, err := cmd.CombinedOutput()
    if err != nil {
        // ffprobe returns error even on success for this filter
    }

    return parseSilenceRegions(output)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio trimming and filters |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg trim filter](https://ffmpeg.org/ffmpeg-filters.html#trim)
- [FFmpeg silencedetect](https://ffmpeg.org/ffmpeg-filters.html#silencedetect)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
