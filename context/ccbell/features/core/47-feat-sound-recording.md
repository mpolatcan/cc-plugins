# Feature: Sound Recording

Record custom sounds using the microphone.

## Summary

Record and save custom notification sounds directly from the microphone.

## Motivation:

- Create personal notification sounds
- Quick sound creation without external tools
- Record environmental sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Recording Tools

| Platform | Tool | Native Support | Feasibility |
|----------|------|----------------|-------------|
| macOS | `afrecord` | No | ⚠️ SoX required |
| macOS | `sox` | No | ⚠️ SoX required |
| Linux | `arecord` | Yes | ✅ ALSA |
| Linux | `ffmpeg` | Yes | ✅ Cross-distro |

### Implementation with FFmpeg

```bash
# Record 3 seconds
ffmpeg -f avfoundation -i ":0" -t 3 -y output.aiff

# Record with gain
ffmpeg -f avfoundation -i ":0" -af "volume=2.0" -t 3 output.aiff

# Linux PulseAudio
ffmpeg -f pulse -i default -t 3 output.aiff
```

### Recording Interface

```go
func recordSound(outputPath string, duration time.Duration) error {
    args := []string{"-y"}

    switch detectPlatform() {
    case PlatformMacOS:
        args = append(args, "-f", "avfoundation", "-i", ":0")
    case PlatformLinux:
        args = append(args, "-f", "pulse", "-i", "default")
    }

    args = append(args, "-t", fmt.Sprintf("%d", int(duration.Seconds())))
    args = append(args, outputPath)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

### Commands

```bash
/ccbell:record start output.aiff           # Start recording
/ccbell:record start output.aiff --5sec    # 5 second recording
/ccbell:record start output.aiff --preview # Preview before saving
/ccbell:record stop                        # Stop recording
/ccbell:record --install stop              # Record and set as stop sound
```

### Interactive Recording

```
$ /ccbell:record

=== Sound Recording ===

Press [r] to start recording
Press [s] to stop
Press [p] to preview
Press [e] to edit name and save
Press [q] to quit

[r] Recording... (max 5 seconds, press [s] to stop)

[s] Recording stopped (2.3 seconds)

Preview? [y/n]: y
[Playing sound...]

Save as: my-sound.aiff
Saved to: /Users/me/.claude/ccbell/sounds/my-sound.aiff

Installed as: bundled:my-sound
```

---

## Audio Player Compatibility

Sound recording creates files for playback:
- Recorded files play via existing players
- Supports same formats as other sounds
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Already supported |

---

## References

### Research Sources

- [FFmpeg audio input](https://ffmpeg.org/ffmpeg.html#Audio-Options)
- [ALSA arecord](https:// Eastman.org/man-pages/arecord.1.html)

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg (avfoundation) |
| Linux | ✅ Supported | Via ffmpeg (pulse/alsa) |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
