# Feature: TTS Announcements

Text-to-speech notifications for Claude Code events.

## Summary

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS.

## Motivation

- Users who prefer voice announcements over sound effects
- Accessibility: spoken notifications help users who are deaf or hard of hearing
- Context-aware: TTS can include event details (e.g., "Claude finished in 3.2 seconds")

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | High |
| **Estimated Effort** | 7-10 days |

---

## Technical Feasibility

### Audio Playback (for TTS output)

The current `internal/audio/player.go` supports native players:
- **macOS**: `afplay`
- **Linux**: `mpv`, `paplay`, `aplay`, `ffplay`

**Key Finding**: TTS output can use the existing audio player infrastructure by generating WAV files from TTS engines.

### TTS Engines

| Engine | Size | Quality | Platform | Cost |
|--------|------|---------|----------|------|
| **Flite** | ~2MB | Robotic | macOS, Linux | Free |
| **eSpeak NG** | ~3MB | Robotic | macOS, Linux | Free |
| **Piper** | ~50MB | Natural | Python | Free |
| **Kokoro** | ~100MB | Excellent | Python | Free |

### Recommended: Flite (for size)

| Aspect | Details |
|--------|---------|
| Size | ~2MB binary |
| Quality | Robotic, but clear |
| Go Bindings | [gen2brain/flite-go](https://github.com/gen2brain/flite-go) |
| Voices | Single US English |
| Platform | macOS, Linux |
| License | BSD-style |

**Usage:**
```go
import "github.com/gen2brain/flite-go/flite"

flite.TextToSpeech("Claude finished", "voice.wav")
// Play "voice.wav" with existing player
```

### Alternative: eSpeak NG

```bash
espeak-ng -w output.wav "Claude finished" && play output.wav
```

---

## Implementation Approach

### Phase 1: Flite Integration

1. **Download Flite binary** on first use (similar to ccbell binary download)
   - Platform-specific builds from [flite releases](https://github.com/festvox/flite/releases)
   - Fallback to system `flite` if installed

2. **Create TTS wrapper in ccbell:**

```go
func (c *CCBell) speak(text string) error {
    wavFile := filepath.Join(c.cacheDir, "tts", randomName()+".wav")
    if err := c.runFlite(text, wavFile); err != nil {
        return err
    }
    return c.playAudio(wavFile)
}
```

3. **Add TTS config:**

```json
{
  "tts": {
    "enabled": true,
    "engine": "flite", // "flite", "espeak", "piper"
    "voice": "kal",
    "phrases": {
      "stop": "Claude finished",
      "permission_prompt": "Permission needed",
      "idle_prompt": "Claude is waiting",
      "subagent": "Subagent task complete"
    }
  }
}
```

### Phase 2: Multiple Engines

```go
func findTTSEngine() string {
    if _, err := exec.LookPath("piper"); err == nil {
        return "piper"
    }
    if _, err := exec.LookPath("espeak-ng"); err == nil {
        return "espeak"
    }
    // Download flite as fallback
    return "flite"
}
```

---

## Feasibility Research

### Audio Player Compatibility

TTS requires audio playback, which uses the existing player infrastructure:
- TTS generates WAV files
- Existing players play the WAV files

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Flite | External binary | Free | Download on first use |
| eSpeak NG | External binary | Free | Package install |
| Piper | Python CLI | Free | Optional, higher quality |
| flite-go | Go library | Free | Wrapper for Flite |

### Supported Platforms

| Platform | Flite | eSpeak NG | Piper |
|----------|-------|-----------|-------|
| macOS | ✅ | ✅ | ✅ (Python) |
| Linux | ✅ | ✅ | ✅ |

Note: ccbell only supports macOS and Linux. Windows is not supported.

### Caching Strategy

Cache TTS output to avoid regenerating:
- Hash text + voice + engine → WAV file
- LRU cache with size limits (e.g., 100MB)

---


---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### Research Sources

- [Flite TTS](http://cmuflite.org/)
- [Flite Go Bindings](https://github.com/gen2brain/flite-go)
- [eSpeak NG](https://github.com/espeak-ng/espeak-ng)
- [Piper TTS](https://github.com/rhasspy/piper)
- [Kokoro TTS](https://github.com/hexgrad/Kokoro-82M)

### ccbell Implementation Research

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - For playing generated TTS WAV files
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L34-L91) - macOS `say` available, Linux needs package install
- [ffplay as fallback](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Can play any format TTS generates
