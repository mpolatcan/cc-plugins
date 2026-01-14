# Feature: Sound Quality Check

Detect and report issues with sound files.

## Summary

Analyze sound files for common problems like corruption, zero length, or format issues.

## Motivation

- Detect broken sounds before they fail
- Quality assurance for custom sounds
- Prevent silent failures

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Quality Checks

| Check | Tool | What It Detects |
|-------|------|-----------------|
| File exists | os.Stat | Missing files |
| File size | os.Stat | Zero-length files |
| Duration | ffprobe | Zero or very long duration |
| Format | ffprobe | Unsupported formats |
| Sample rate | ffprobe | Unusual sample rates |
| Bit depth | ffprobe | Compatibility issues |

### Implementation

```go
type SoundQualityIssue struct {
    Type    string
    Sound   string
    Message string
    Severity string  // "error", "warning", "info"
}

func CheckSoundQuality(soundPath string) []SoundQualityIssue {
    issues := []SoundQualityIssue{}

    // Check file exists
    info, err := os.Stat(soundPath)
    if os.IsNotExist(err) {
        return []SoundQualityIssue{{
            Type: "missing",
            Sound: soundPath,
            Message: "Sound file does not exist",
            Severity: "error",
        }}
    }

    // Check file size
    if info.Size() == 0 {
        issues = append(issues, SoundQualityIssue{
            Type: "zero_length",
            Sound: soundPath,
            Message: "Sound file has zero size",
            Severity: "error",
        })
    }

    // Check with ffprobe
    info, issues = checkWithFFprobe(soundPath, issues)

    return issues
}

func checkWithFFprobe(soundPath string, issues []SoundQualityIssue) (AudioInfo, []SoundQualityIssue) {
    cmd := exec.Command("ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", "-show_streams", soundPath)

    output, err := cmd.Output()
    if err != nil {
        issues = append(issues, SoundQualityIssue{
            Type: "ffprobe_failed",
            Sound: soundPath,
            Message: fmt.Sprintf("Could not analyze: %v", err),
            Severity: "warning",
        })
        return AudioInfo{}, issues
    }

    // Parse and check
    // Check duration, format, sample rate, etc.

    return info, issues
}
```

### Commands

```bash
/ccbell:check sounds                    # Check all sounds
/ccbell:check bundled:stop              # Check specific sound
/ccbell:check custom:/path/sound.aiff   # Check custom sound
/ccbell:check --json                    # JSON output
/ccbell:check --verbose                 # Detailed output
```

### Output

```
$ ccbell check sounds

=== Sound Quality Check ===

bundled:stop
  [OK] File exists (12.3 KB)
  [OK] Duration: 1.234s
  [OK] Format: AIFF, 44100Hz, mono
  [OK] Bit depth: 16-bit

bundled:permission_prompt
  [OK] File exists (8.5 KB)
  [OK] Duration: 0.456s

custom:/Users/me/sounds/custom.wav
  [WARNING] Sample rate: 96000Hz (unusual but should work)
  [OK] Duration: 2.1s

/custom:/Users/me/sounds/broken.wav
  [ERROR] File exists but ffprobe could not parse
  [ERROR] May be corrupted or in unsupported format

=== Summary ===
Checked: 4 sounds
Passed: 3
Warnings: 1
Errors: 1
```

---

## Audio Player Compatibility

Sound quality check uses ffprobe:
- Pre-play analysis
- Doesn't interact with player
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffprobe | External tool | Free | Part of ffmpeg |

---

## References

### Research Sources

- [ffprobe documentation](https://ffmpeg.org/ffprobe.html)
- [FFprobe JSON format](https://ffmpeg.org/ffprobe.html#Generic-options)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg/ffprobe available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
