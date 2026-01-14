# Feature: Waveform Preview

Visual waveform display for sound files during preview.

## Summary

Display a visual representation of sound files to help users understand the audio before selecting.

## Motivation

- See sound duration visually
- Identify loud/quiet sections
- Better sound selection experience

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Waveform Generation Tools

| Tool | Output | Platform |
|------|--------|----------|
| `ffmpeg` + scripts | ASCII/PNG | macOS, Linux |
| `sox` | ASCII | macOS, Linux |
| `waveform` (npm) | ASCII/PNG | Cross-platform |

### ASCII Waveform (Simple)

```bash
# Generate ASCII waveform
ffprobe -v quiet -print_format json -show_format -show_streams input.aiff | \
  jq -r '.streams[0].duration' | \
  python3 waveform.py input.aiff

# Output:
# ▁▂▃▂▁▁▂▃▄▄▃▂▁▁▂▃▂▁▁▁▂▃▄▄▄▃▂▁▁▁▁▁▁
```

### Implementation

```go
type Waveform struct {
    Width     int
    Height    int
    Character string
}

func (w *Waveform) Generate(audioPath string) (string, error) {
    // Get audio info
    info, err := getAudioInfo(audioPath)
    if err != nil {
        return "", err
    }

    // Sample audio at width intervals
    samples := w.sampleAudio(audioPath, w.Width)

    // Normalize to height
    normalized := w.normalize(samples)

    // Build ASCII output
    return w.render(normalized), nil
}

func (w *Waveform) render(samples []float64) string {
    levels := []string{" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

    var output strings.Builder
    for _, sample := range samples {
        idx := int(sample * float64(len(levels)-1))
        if idx >= len(levels) {
            idx = len(levels) - 1
        }
        output.WriteString(levels[idx])
    }
    return output.String()
}
```

### Preview Output

```
$ /ccbell:preview bundled:stop --waveform

Sound: bundled:stop
Duration: 1.234s
Volume: 0.50 (normalized)

▁▂▃▂▁▁▂▃▄▄▄▃▂▁▁▁▁▁▁▁▁▁▁

$ /ccbell:preview custom:sound.mp3 --waveform --width 80

Sound: custom:sound.mp3
Duration: 3.456s
Volume: 0.75

▁▁▂▃▂▁▁▂▃▄▄▄▃▂▁▁▂▃▄▄▄▃▂▁▁▂▃▄▄▄▃▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
```

### Commands

```bash
/ccbell:preview bundled:stop --waveform     # Show waveform
/ccbell:preview bundled:stop -w 60          # 60 chars wide
/ccbell:preview bundled:stop -h 10          # 10 levels high
/ccbell:browse --waveform                   # Browse with waveforms
```

---

## Audio Player Compatibility

Waveform preview doesn't interact with audio playback:
- Uses ffprobe for audio analysis
- Doesn't call audio player
- Purely visual feature

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffprobe | External tool | Free | Part of ffmpeg |

---

## References

### Research Sources

- [FFprobe JSON output](https://ffmpeg.org/ffprobe.html)
- [ASCII waveform generation](https://github.com/nicolashug/sound-waveform)

### ccbell Implementation Research

- [Audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Uses ffmpeg/ffprobe
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
