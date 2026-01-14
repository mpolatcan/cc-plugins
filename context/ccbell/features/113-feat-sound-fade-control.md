# Feature: Sound Fade Control

Control fade in/out for sounds.

## Summary

Configure fade in and fade out effects for smooth audio transitions.

## Motivation

- Smooth transitions
- Avoid abrupt starts/stops
- Professional sound

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Fade Options

| Option | Description | Range |
|--------|-------------|-------|
| Fade In | Gradual start | 0-5000ms |
| Fade Out | Gradual end | 0-5000ms |
| Curve | Fade curve | linear, log, exp |

### Configuration

```go
type FadeConfig struct {
    Enabled     bool    `json:"enabled"`
    FadeInMs    int     `json:"fade_in_ms"`
    FadeOutMs   int     `json:"fade_out_ms"`
    Curve       string  `json:"curve"`        // "linear", "log", "exp"
    PerEvent    map[string]FadeSettings `json:"per_event"`
}

type FadeSettings struct {
    FadeInMs    int     `json:"fade_in_ms"`
    FadeOutMs   int     `json:"fade_out_ms"`
    Curve       string  `json:"curve"`
}
```

### Commands

```bash
/ccbell:fade in 500                  # 500ms fade in
/ccbell:fade out 500                 # 500ms fade out
/ccbell:fade in 1000 out 500         # Custom both
/ccbell:fade set curve exp           # Exponential curve
/ccbell:fade set event stop in 200   # Stop event: 200ms fade in
/ccbell:fade disable                 # Disable fades
/ccbell:fade apply input.aiff output.aiff
/ccbell:fade preview                 # Preview fade
```

### Output

```
$ ccbell:fade in 500 out 500

=== Sound Fade Control ===

Status: Enabled
Fade In: 500ms (Linear)
Fade Out: 500ms (Linear)

Waveform:
  ░░░░░▓▓▓▓████████▓▓▓▓░░░░░░
        ↑           ↑
      0.5s        1.2s

Per-Event:
  stop: in:200ms, out:300ms
  permission_prompt: in:100ms, out:100ms

[Apply] [Presets] [Customize] [Disable]
```

---

## Audio Player Compatibility

Fade control doesn't play sounds:
- Pre-processing with ffmpeg
- No player changes required
- Output is modified audio file

---

## Implementation

### FFmpeg Fade

```go
func (f *FadeManager) ApplyFade(inputPath, outputPath string, config *FadeConfig) error {
    args := []string{"-y", "-i", inputPath}

    filters := []string{}

    // Fade in
    if config.FadeInMs > 0 {
        filters = append(filters, fmt.Sprintf("afade=t=in:ss=0:d=%d", config.FadeInMs/1000))
    }

    // Fade out
    duration := getDuration(inputPath)
    if config.FadeOutMs > 0 {
        startSec := duration - float64(config.FadeOutMs)/1000.0
        filters = append(filters, fmt.Sprintf("afade=t=out:st=%.3f:d=%d", startSec, config.FadeOutMs/1000))
    }

    if len(filters) > 0 {
        args = append(args, "-af", strings.Join(filters, ","))
    }

    args = append(args, outputPath)

    return exec.Command("ffmpeg", args...).Run()
}
```

### Curve Selection

```go
func (f *FadeManager) getFadeCurve(curve string) string {
    switch curve {
    case "log":
        return "t=in:curve=l:s=0:e=1"
    case "exp":
        return "t=in:curve=s:e=0"
    default: // linear
        return "t=in"
    }
}
```

### Presets

```go
var fadePresets = map[string]FadeConfig{
    "quick": {
        Enabled:   true,
        FadeInMs:  50,
        FadeOutMs: 50,
        Curve:     "linear",
    },
    "smooth": {
        Enabled:   true,
        FadeInMs:  200,
        FadeOutMs: 300,
        Curve:     "linear",
    },
    "gentle": {
        Enabled:   true,
        FadeInMs:  500,
        FadeOutMs: 500,
        Curve:     "log",
    },
    "ambient": {
        Enabled:   true,
        FadeInMs:  1000,
        FadeOutMs: 1000,
        Curve:     "exp",
    },
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio fades |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg afade](https://ffmpeg.org/ffmpeg-filters.html#afade)
- [Fade curves](https://ffmpeg.org/ffmpeg-filters.html#Fade-1)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
