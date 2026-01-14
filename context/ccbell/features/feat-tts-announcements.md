# Feature: TTS Announcements 🗣️

## Summary

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS.

## Benefit

- **Accessibility-first**: Voice announcements help users with hearing impairments
- **Hands-free awareness**: Know what's happening without looking at the screen
- **Rich context**: TTS can include timing, event details, and custom messages
- **Personalized experience**: Custom voice clones for unique notification sounds

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | High |
| **Category** | Audio |

## Technical Feasibility

### Configuration

```json
{
  "tts": {
    "enabled": true,
    "engine": "say",
    "voice": "Samantha",
    "phrases": {
      "stop": "Claude finished",
      "permission_prompt": "Permission needed",
      "idle_prompt": "Claude is waiting",
      "subagent": "Subagent task complete"
    },
    "cache_enabled": true,
    "cache_size_mb": 100
  }
}
```

### Implementation

```go
type TTSManager struct {
    engine   string
    voice    string
    cacheDir string
}

func (t *TTSManager) Speak(text string) error {
    outputFile := t.getCachedPath(text)

    if _, err := os.Stat(outputFile); err == nil {
        player := audio.NewPlayer()
        return player.Play(outputFile)
    }

    switch t.engine {
    case "say":
        return t.speakMacOS(text)
    case "piper":
        return t.speakPiper(text)
    case "kokoro":
        return t.speakKokoro(text)
    }

    return fmt.Errorf("unknown TTS engine: %s", t.engine)
}

func (t *TTSManager) speakMacOS(text string) error {
    cmd := exec.Command("say", "-v", t.voice, text)
    return cmd.Run()
}

func (t *TTSManager) speakPiper(text string) error {
    cmd := exec.Command("piper",
        "--model", t.modelPath,
        "--output_file", t.outputFile)
    stdin, _ := cmd.StdinPipe()
    stdin.WriteString(text)
    stdin.Close()
    return cmd.Run()
}
```

### Commands

```bash
/ccbell:tts configure             # Configure TTS settings
/ccbell:tts voices                # List available voices
/ccbell:tts test stop             # Test TTS for an event
/ccbell:tts test all              # Test all TTS phrases
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `tts` section with engine, voice, phrases, cache options |
| **Core Logic** | Add | Add `TTSManager` with Speak() and Generate() methods |
| **New File** | Add | `internal/tts/tts.go` for TTS engine abstraction |
| **Main Flow** | Modify | Support TTS as alternative or alongside sounds |
| **Commands** | Add | New `tts` command (configure, voices, phrases) |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/tts.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference TTS options |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Piper TTS - GitHub](https://github.com/rhasspy/piper)
- [Kokoro-82M - Hugging Face](https://huggingface.co/hexgrad/Kokoro-82M)
- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)

---

[Back to Feature Index](index.md)
