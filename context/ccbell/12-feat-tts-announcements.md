# Feature: TTS Announcements

Text-to-speech notifications for Claude Code events.

## Summary

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS.

## Motivation

- Users who prefer voice announcements over sound effects
- Accessibility: spoken notifications help users who are deaf or hard of hearing
- Context-aware: TTS can include event details (e.g., "Claude finished in 3.2 seconds")

## Technical Feasibility

### Audio Playback (for TTS output)

| Library | Platform | Format Support | Go Module | Notes |
|---------|----------|----------------|-----------|-------|
| **ebitengine/oto** | macOS, Windows, Linux | WAV (via decoders) | `github.com/ebitengine/oto/v3` | Low-level, requires decoders |
| **go-minimp3** | Cross-platform | MP3 | `github.com/cowork-ai/go-minimp3` | Pure Go MP3 decoder |
| **go-audio/wav** | Cross-platform | WAV | `github.com/go-audio/wav` | WAV reading/writing |

**Recommended Stack:**
- `ebitengine/oto` for cross-platform audio playback
- `go-audio/wav` for WAV file handling
- Native OS players as fallback (afplay on macOS, paplay on Linux)

### TTS Engines

#### Option 1: Flite (Recommended for size)

| Aspect | Details |
|--------|---------|
| Size | ~2MB binary |
| Quality | Robotic, but clear |
| Go Bindings | [gen2brain/flite-go](https://github.com/gen2brain/flite-go) |
| Voices | Single US English (customizable) |
| Platform | macOS, Linux, Windows |
| License | BSD-style |

**Usage:**
```go
import "github.com/gen2brain/flite-go/flite"

flite.TextToSpeech("Claude finished", "voice.wav")
// Play "voice.wav" with oto
```

#### Option 2: eSpeak NG

| Aspect | Details |
|--------|---------|
| Size | ~3MB binary |
| Quality | Robotic, multiple voices |
| Platform | macOS, Linux, Windows |
| License | GPL |
| CLI | `espeak-ng "text"` |

**Usage:**
```bash
espeak-ng -w output.wav "Claude finished" && play output.wav
```

#### Option 3: Piper (Quality > Size)

| Aspect | Details |
|--------|---------|
| Size | ~50MB with models |
| Quality | Natural, neural |
| Platform | Python CLI |
| License | Apache 2.0 |
| Models | Multiple English voices |

**Usage:**
```bash
echo "Claude finished" | piper --model en_US-lessac-medium.onnx --output_file output.wav
```

#### Option 4: Kokoro (Best Quality)

| Aspect | Details |
|--------|---------|
| Size | ~100MB with models |
| Quality | Excellent, human-like |
| Platform | Python CLI |
| License | CC-BY-4.0 |
| Voices | American/British, male/female |

**Recommendation:** Start with **Flite** for minimum footprint. Add Piper/Kokoro as optional high-quality modes.

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
       "engine": "flite", // "flite", "espeak", "piper", "kokoro"
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

1. **Engine discovery:**
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

2. **Cache TTS output:**
   - Hash text + voice + engine → WAV file
   - Reuse cached WAV for repeated phrases
   - LRU cache with size limits (e.g., 100MB)

## Configuration

### Command: `/ccbell:tts`

Interactive setup for TTS:
```
Enable TTS? [y/n]: y
Select engine [flite/espeak/piper]: flite
Customize phrases:
  stop (default: "Claude finished"): [enter for default]
  permission_prompt (default: "Permission needed"): [enter for default]
  ...
Test phrase: Claude finished
[plays audio]
Save? [y/n]: y
```

### Config Schema

```json
{
  "type": "object",
  "properties": {
    "tts": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "engine": { "type": "string", "enum": ["flite", "espeak", "piper", "kokoro"] },
        "voice": { "type": "string" },
        "volume": { "type": "number", "minimum": 0, "maximum": 1 },
        "rate": { "type": "number", "minimum": 0.5, "maximum": 2 },
        "phrases": {
          "type": "object",
          "properties": {
            "stop": { "type": "string" },
            "permission_prompt": { "type": "string" },
            "idle_prompt": { "type": "string" },
            "subagent": { "type": "string" }
          }
        }
      }
    }
  }
}
```

## Compatibility

| Platform | Flite | eSpeak NG | Piper | Kokoro |
|----------|-------|-----------|-------|--------|
| macOS | ✅ | ✅ | ✅ (Python) | ✅ (Python) |
| Linux | ✅ | ✅ | ✅ | ✅ |
| Windows | ✅ | ✅ | ✅ | ✅ |

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| TTS slow to start | Pre-warm engine, cache common phrases |
| Poor quality perception | Offer multiple engines, let users choose |
| Binary bloat | Download on demand, not bundled |
| Platform issues | Fallback to native audio players |

## Future Enhancements

- **Voice selection:** Multiple voices per engine
- **Custom phrases:** User-defined templates with variables (e.g., "{duration} seconds")
- **SSML support:** Rich text-to-speech markup
- **Event-specific voices:** Different voice per event type
- **Batch announcements:** Queue multiple TTS requests

## References

- [Flite TTS](http://cmuflite.org/)
- [Flite Go Bindings](https://github.com/gen2brain/flite-go)
- [eSpeak NG](https://github.com/espeak-ng/espeak-ng)
- [Piper TTS](https://github.com/rhasspy/piper)
- [Kokoro TTS](https://github.com/hexgrad/Kokoro-82M)
- [Oto Audio Library](https://github.com/ebitengine/oto)
