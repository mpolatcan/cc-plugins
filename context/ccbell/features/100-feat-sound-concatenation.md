# Feature: Sound Concatenation

Join multiple sounds into one.

## Summary

Combine multiple audio files into a single sound for compound notifications.

## Motivation

- Create compound sounds
- Build sound sequences
- Sound collage creation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Concatenation Types

| Type | Description | Use Case |
|------|-------------|----------|
| Sequential | Play one after another | Sequence |
| Overlap | Blend sounds together | Crossfade |
| Gap | Add silence between | Spacing |

### Configuration

```go
type ConcatConfig struct {
    Sounds      []string `json:"sounds"`        // input sounds
    Output      string   `json:"output"`        // output file
    GapMs       int      `json:"gap_ms"`        // silence between (ms)
    CrossfadeMs int      `json:"crossfade_ms"`  // crossfade duration
    Order       string   `json:"order"`         // "sequential", "random"
    Repeat      int      `json:"repeat"`        // repeat count (-1=infinite)
}

type ConcatPreset struct {
    Name        string   `json:"name"`
    Sounds      []string `json:"sounds"`
    GapMs       int      `json:"gap_ms"`
    CrossfadeMs int      `json:"crossfade_ms"`
}
```

### Commands

```bash
/ccbell:concat sound1.aiff sound2.aiff sound3.aiff -o output.aiff
/ccbell:concat "*.aiff" --output combined.aiff
/ccbell:concat sound1.aiff sound2.aiff --gap 500
/ccbell:concat sound1.aiff sound2.aiff --crossfade 100
/ccbell:concat preset create "Attention" sound1 sound2
/ccbell:concat preset use attention
/ccbell:concat --repeat 3 sound1.aiff sound2.aiff
```

### Output

```
$ ccbell:concat sound1.aiff sound2.aiff sound3.aiff -o output.aiff

=== Sound Concatenation ===

Input:
  [1] sound1.aiff (1.2s)
  [2] sound2.aiff (0.8s)
  [3] sound3.aiff (1.5s)

Settings:
  Gap: 0ms
  Crossfade: 0ms
  Repeat: 1

Output:
  Duration: 3.5s
  Format: AIFF
  Path: output.aiff

Preview:
  [██████████|██████████|██████████] 3.5s

[Create] [Add Sound] [Remove] [Preview]
```

---

## Audio Player Compatibility

Concatenation doesn't play sounds:
- File creation feature
- Uses ffmpeg for concatenation
- No player changes required

---

## Implementation

### FFmpeg Concatenation

```go
func (c *ConcatManager) Concat(config *ConcatConfig) error {
    // Create concat filter
    filter := ""
    for i, sound := range config.Sounds {
        inputIdx := i
        if i > 0 {
            if config.CrossfadeMs > 0 {
                // Crossfade between sounds
                filter += fmt.Sprintf("[%d:a][%d:a]acrossfade=c=%d:o=%d;", i-1, i, config.CrossfadeMs, config.CrossfadeMs)
            } else if config.GapMs > 0 {
                // Add silence gap
                filter += fmt.Sprintf("[%d:a]adelay=%d|%d[%d:a];", i, config.GapMs, config.GapMs, i)
                if i == len(config.Sounds)-1 {
                    filter += fmt.Sprintf("[%d:a]", i)
                }
            }
        } else {
            filter += fmt.Sprintf("[%d:a]", i)
        }
    }

    args := []string{"-y"}

    // Add input files
    for _, sound := range config.Sounds {
        args = append(args, "-i", sound)
    }

    // Build complex filter
    if filter != "" {
        args = append(args, "-filter_complex", filter)
    }

    // Add concat outputs
    concatOutputs := ""
    for i := 0; i < len(config.Sounds); i++ {
        if i > 0 && config.CrossfadeMs == 0 && config.GapMs == 0 {
            concatOutputs += fmt.Sprintf("[%d:a]", i)
        }
    }
    if concatOutputs != "" {
        args = append(args, "-map", concatOutputs)
    }

    args = append(args, config.Output)

    return exec.Command("ffmpeg", args...).Run()
}
```

### Playlist File Method

```go
func (c *ConcatManager) concatWithPlaylist(sounds []string, outputPath string) error {
    // Create playlist file
    playlist := filepath.Join(os.TempDir(), "ccbell_concat.txt")
    file, _ := os.Create(playlist)
    defer os.Remove(playlist)

    for _, sound := range sounds {
        fmt.Fprintf(file, "file '%s'\n", sound)
    }

    // Use ffmpeg concat demuxer
    cmd := exec.Command("ffmpeg", "-y", "-f", "concat", "-safe", "0",
        "-i", playlist, "-c", "copy", outputPath)

    return cmd.Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio concatenation |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg concat demuxer](https://ffmpeg.org/ffmpeg-formats.html#concat)
- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html#Audio-Filters)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
