# Feature: Sound Transcoding

Convert sounds between audio formats.

## Summary

Convert audio files between different formats and bitrates.

## Motivation

- Optimize file sizes
- Ensure format compatibility
- Batch conversion

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Supported Formats

| Input | Output | Notes |
|-------|--------|-------|
| WAV | MP3, FLAC, AAC | Compression |
| AIFF | WAV, MP3 | Format change |
| MP3 | WAV, FLAC | Quality improvement |
| FLAC | WAV, MP3 | Compression |

### Configuration

```go
type TranscodeConfig struct {
    InputFormat  string  `json:"input_format"`
    OutputFormat string  `json:"output_format"`
    Bitrate      int     `json:"bitrate"`       // kbps
    SampleRate   int     `json:"sample_rate"`   // Hz
    Channels     int     `json:"channels"`      // 1=mono, 2=stereo
    Quality      int     `json:"quality"`       // 0-9 (lower=better)
    PreserveMeta bool    `json:"preserve_meta"` // Keep metadata
}

type TranscodePreset struct {
    Name    string         `json:"name"`
    Config  *TranscodeConfig `json:"config"`
}
```

### Commands

```bash
/ccbell:transcode input.wav output.mp3       # Convert file
/ccbell:transcode --bitrate 192 input.wav output.mp3
/ccbell:transcode --preset web input.aiff output/
/ccbell:transcode batch "*.wav" --output /tmp
/ccbell:transcode preset add "Web Optimized"
/ccbell:transcode preset list               # List presets
/ccbell:transcode preset use web
```

### Output

```
$ ccbell:transcode input.wav output.mp3

=== Sound Transcoding ===

Input: input.wav (45.2 MB, 2:30)
Output: output.mp3 (4.5 MB, 2:30)

Settings:
  Format: MP3
  Bitrate: 192 kbps
  Sample Rate: 44100 Hz
  Channels: Stereo

Progress: [====================] 100%

Result: Success
  Size reduction: 90%
  Output: output.mp3

[Play] [Open] [Convert Another]
```

---

## Audio Player Compatibility

Transcoding doesn't play sounds:
- File conversion feature
- Uses ffmpeg for conversion
- No player changes required

---

## Implementation

### FFmpeg Conversion

```go
func (t *Transcoder) Transcode(inputPath, outputPath string, config *TranscodeConfig) error {
    args := []string{"-y", "-i", inputPath}

    // Apply audio settings
    if config.SampleRate > 0 {
        args = append(args, "-ar", fmt.Sprintf("%d", config.SampleRate))
    }
    if config.Channels > 0 {
        args = append(args, "-ac", fmt.Sprintf("%d", config.Channels))
    }

    // Output format specific
    switch config.OutputFormat {
    case "mp3":
        args = append(args, "-b:a", fmt.Sprintf("%dk", config.Bitrate))
        args = append(args, outputPath)
    case "aac":
        args = append(args, "-b:a", fmt.Sprintf("%dk", config.Bitrate))
        args = append(args, "-f", "adts", outputPath)
    case "flac":
        args = append(args, outputPath)
    default:
        args = append(args, outputPath)
    }

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

### Batch Processing

```go
func (t *Transcoder) Batch(pattern, outputDir string, config *TranscodeConfig) ([]TranscodeResult, error) {
    files, err := filepath.Glob(pattern)
    if err != nil {
        return nil, err
    }

    results := []TranscodeResult{}
    for _, file := range files {
        outputPath := filepath.Join(outputDir, changeExt(filepath.Base(file), config.OutputFormat))

        if err := t.Transcode(file, outputPath, config); err != nil {
            results = append(results, TranscodeResult{
                Input:  file,
                Status: "failed",
                Error:  err.Error(),
            })
        } else {
            results = append(results, TranscodeResult{
                Input:   file,
                Output:  outputPath,
                Status:  "success",
                SizeKB:  getFileSize(outputPath),
            })
        }
    }

    return results, nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio/video conversion |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg audio options](https://ffmpeg.org/ffmpeg.html#Audio-Options)
- [FFmpeg codecs](https://ffmpeg.org/ffmpeg-codecs.html#Audio-Codecs)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
