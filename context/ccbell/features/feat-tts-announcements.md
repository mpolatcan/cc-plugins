# Feature: TTS Announcements 🗣️

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS.

## Motivation

- Users who prefer voice announcements over sound effects
- Accessibility: spoken notifications help users who are deaf or hard of hearing
- Context-aware: TTS can include event details (e.g., "Claude finished in 3.2 seconds")

---

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
| **Estimated Effort** | 7-10 days |

---

## Technical Feasibility

### Audio Playback (for TTS output)

The current `internal/audio/player.go` supports native players:
- **macOS**: `afplay`
- **Linux**: `mpv`, `paplay`, `aplay`, `ffplay`

**Key Finding**: TTS output can use the existing audio player infrastructure by generating WAV files from TTS engines.

### TTS Engines

| Engine | Size | Quality | Platform | CPU | GPU | License |
|--------|------|---------|----------|-----|-----|---------|
| **macOS `say`** | Built-in | Good | macOS | ✅ | - | Built-in |
| **Flite** | ~2MB | Robotic | macOS, Linux | ✅ | - | BSD-style |
| **eSpeak NG** | ~3MB | Robotic | macOS, Linux | ✅ | - | GPL |
| **Piper** | 20-60MB | Natural | Python | ✅ | Optional | Apache 2.0 |
| **Kokoro-82M** | ~500MB | Excellent | Python/ONNX | ✅ | Optional | Apache 2.0 |
| **Kokoro ONNX** | ~150MB | Excellent | Cross-platform | ✅ | - | Apache 2.0 |
| **Suno Bark** | 1-4GB | Excellent | Python | ⚠️ | ✅ Recommended | MIT |
| **NeuTTS Air** | ~2GB | Super-realistic | Python/GGML | ✅ | Optional | Apache 2.0 |
| **NeuTTS Nano** | ~800MB | Excellent | Python/GGML | ✅ | - | NeuTTS Open License |

### NeuTTS Air (Recommended for Desktop)

| Aspect | Details |
|--------|---------|
| **Parameters** | 0.7B total (0.5B LLM backbone) |
| **Architecture** | Qwen2-based LLM + NeuCodec neural audio codec |
| **Model Size** | ~2GB (GGML/GGUF quantized) |
| **Quality** | Best-in-class ultra-realistic, natural intonation |
| **Voice Cloning** | 3-15 seconds reference audio |
| **Context Window** | 2048 tokens (~30 seconds audio) |
| **CPU Performance** | Real-time on mid-range devices |
| **Watermarking** | Built-in Perth audio watermarker |
| **License** | Apache 2.0 |

**Installation:**
```bash
# Install dependencies
brew install espeak  # macOS
# or
sudo apt install espeak  # Ubuntu/Debian

# Install Python package
pip install neuttsair torch

# Download models (Q4 quantized for efficiency)
huggingface-cli download neuphonic/neutts-air-q4-gguf --local-dir ~/.claude/ccbell/models/neutts-air
huggingface-cli download neuphonic/neucodec --local-dir ~/.claude/ccbell/models/neucodec
```

**Performance Benchmarks:**

| Device | Speed |
|--------|-------|
| AMD Ryzen 9 HX 370 (CPU) | 221 tokens/s |
| iMac M4 16GB (CPU) | 195 tokens/s |
| NVIDIA RTX 4090 (GPU) | 19,268 tokens/s |

**Usage:**
```python
from neuttsair.neutts import NeuTTSAir
import soundfile as sf

tts = NeuTTSAir(
    backbone_repo="neuphonic/neutts-air-q4-gguf",
    backbone_device="cpu",
    codec_repo="neuphonic/neucodec",
    codec_device="cpu"
)

# Encode reference voice
ref_codes = tts.encode_reference("my-voice.wav")

# Generate speech
wav = tts.infer("Claude finished", ref_codes, "")
sf.write("speech.wav", wav, 24000)
```

---

### NeuTTS Nano (Recommended for Mobile/Embedded)

| Aspect | Details |
|--------|---------|
| **Parameters** | ~229M total (~120M active) |
| **Architecture** | LM + NeuCodec (single codebook) |
| **Model Size** | ~800MB (GGML/GGUF quantized) |
| **Quality** | Excellent for its parameter size |
| **Voice Cloning** | 3+ seconds reference audio |
| **Context Window** | 2048 tokens (~30 seconds audio) |
| **CPU Performance** | Real-time on mobile devices |
| **Watermarking** | Built-in Perth audio watermarker |
| **License** | NeuTTS Open License 1.0 |

**Performance Benchmarks:**

| Device | Speed |
|--------|-------|
| Galaxy A25 5G (CPU only) | 45 tokens/s |
| AMD Ryzen 9 HX 370 (CPU) | 221 tokens/s |
| iMac M4 16GB (CPU) | 195 tokens/s |
| NVIDIA RTX 4090 (GPU) | 19,268 tokens/s |

**Best For:**
- Raspberry Pi 4/5
- Mobile devices
- Resource-constrained Linux systems
- Headless servers

---

### Recommended: Piper (Best Balance)

| Aspect | Details |
|--------|---------|
| **Model Size** | 20-60MB per voice |
| **Quality** | Natural, neural voice synthesis |
| **CPU Performance** | Real-time on Raspberry Pi 4/5 |
| **GPU** | Optional, improves speed |
| **Voices** | Multiple English + multilingual |
| **License** | Apache 2.0 |

**Installation:**
```bash
# Via pip
pip install piper-tts

# Download a voice model
curl -L -o en_US-lessac-medium.onnx \
  https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_en_US_lessac_medium.onnx
curl -L -o en_US-lessac-medium.onnx.json \
  https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_en_US_lessac_medium.onnx.json
```

**Usage:**
```bash
echo "Claude finished" | piper --model en_US-lessac-medium.onnx --output_file speech.wav
```

### Recommended: Kokoro-82M ONNX (Best Quality/Size Ratio)

| Aspect | Details |
|--------|---------|
| **Parameters** | 82 million |
| **Model Size** | ~150MB (ONNX quantized) |
| **Quality** | Comparable to larger models |
| **CPU Performance** | Fast inference |
| **GPU** | Optional (WebGPU, CUDA) |
| **Voices** | Multiple American English voices |
| **License** | Apache 2.0 |

**Installation:**
```bash
# Via pip
pip install kokoro transformers onnxruntime

# Or use transformers.js for Node.js
npm install kokoro-js
```

**Usage (Python):**
```python
from kokoro import KPipeline
import soundfile as sf

pipeline = KPipeline(lang_code='a')

# Generate audio
generator = pipeline("Claude finished", voice='af_bella')
audio = next(generator)
sf.write("speech.wav", audio, 24000)
```

**Usage (Node.js):**
```javascript
import { KokoroTTS } from "kokoro-js";

const tts = await KokoroTTS.from_pretrained("onnx-community/Kokoro-82M-v1.0-ONNX", {
  dtype: "q8",  // Options: fp32, fp16, q8, q4
  device: "cpu",
});

const audio = await tts.generate("Claude finished", { voice: "af_bella" });
audio.save("speech.wav");
```

### macOS Built-in: `say`

| Aspect | Details |
|--------|---------|
| **Availability** | Built into all macOS |
| **Quality** | Good, natural voices |
| **Voices** | Many (Samantha, Victoria, etc.) |
| **Latency** | Very fast |
| **Offline** | Yes |

**Usage:**
```bash
say "Claude finished"
say -v Samantha "Permission needed"
```

### Piper vs Kokoro vs NeuTTS Comparison

| Criteria | Piper | Kokoro-82M | NeuTTS Air | NeuTTS Nano |
|----------|-------|------------|------------|-------------|
| **Model Size** | 20-60MB | ~150MB | ~2GB | ~800MB |
| **CPU Only** | ✅ Real-time | ✅ Fast | ✅ Real-time | ✅ Real-time |
| **Voice Quality** | Good | Excellent | Super-realistic | Excellent |
| **Multilingual** | ✅ | English + Spanish | English | English |
| **Voice Cloning** | ❌ | ❌ | ✅ | ✅ |
| **Setup Complexity** | Low | Medium | Medium | Medium |
| **Python Dependency** | Yes | Yes (or Node.js) | Yes | Yes |
| **Best For** | Raspberry Pi | General use | Desktop/premium | Mobile/embedded |

### Suno Bark (Not Recommended for ccbell)

| Aspect | Details |
|--------|---------|
| **Model Size** | 1-4GB |
| **GPU Memory** | 4-8GB VRAM recommended |
| **Quality** | Excellent |
| **Use Case** | Not suitable - too heavy |
| **Reason** | Exceeds Claude Code hook constraints |

**Warning:** Bark requires significant resources and cannot run within Claude Code hook timeout constraints.

---

## Caching Strategy

Cache TTS output to avoid regenerating:
- Hash text + voice + engine → WAV file
- LRU cache with size limits (e.g., 100MB)
- Cache directory: `~/.claude/ccbell/tts-cache/`

---

## Implementation

### Phase 1: macOS Built-in `say`

```go
func (c *CCBell) speak(text string) error {
    cmd := exec.Command("say", text)
    return cmd.Run()
}
```

### Phase 2: Piper Integration

```bash
# Install
pip install piper-tts

# Download voice model
curl -L -o en_US-lessac-medium.onnx \
  https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_en_US_lessac_medium.onnx
```

```go
func (c *CCBell) speakPiper(text string) error {
    cmd := exec.Command("piper",
        "--model", c.config.TTS.ModelPath,
        "--output_file", c.outputFile,
    )
    stdin, _ := cmd.StdinPipe()
    stdin.WriteString(text)
    stdin.Close()
    return cmd.Run()
}
```

### Phase 3: Kokoro Integration

```go
func (c *CCBell) speakKokoro(text string) error {
    // Use subprocess to call Python script
    script := fmt.Sprintf(`
from kokoro import KPipeline
pipeline = KPipeline(lang_code='a')
audio = next(pipeline("%s", voice="%s"))
import soundfile as sf
sf.write("%s", audio, 24000)
`, text, c.config.TTS.Voice, c.outputFile)

    cmd := exec.Command("python3", "-c", script)
    return cmd.Run()
}
```

### Configuration

```json
{
  "tts": {
    "enabled": true,
    "engine": "auto", // "say", "piper", "kokoro", "auto"
    "voice": "af_bella", // Kokoro voice
    "model_path": "~/.claude/ccbell/voices/en_US-lessac-medium.onnx",
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

### Engine Detection

```go
func findTTSEngine() string {
    // Priority order: say > piper > kokoro
    if runtime.GOOS == "darwin" {
        if _, err := exec.LookPath("say"); err == nil {
            return "say"
        }
    }
    if _, err := exec.LookPath("piper"); err == nil {
        return "piper"
    }
    // Kokoro requires Python
    return "kokoro"
}
```

---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses `say` (macOS) or TTS CLI tools |
| **Timeout Safe** | ⚠️ Needs Care | Piper/Kokoro may exceed 30s on first run |
| **Dependencies** | ⚠️ External | Requires TTS engine installation |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- **macOS:** Use built-in `say` command (no install needed)
- **Linux:** Requires Piper or Kokoro installation
- **First Run:** Model download may exceed hook timeout
- **Recommendation:** Download models during installation, not at runtime
- **Caching:** Essential for performance (avoid regenerating same phrases)

---

## References

### Research Sources

- [Piper TTS - GitHub](https://github.com/rhasspy/piper) - Fast, local neural TTS system
- [Piper Voices](https://github.com/rhasspy/piper/tree/master/voices) - Available voice models
- [Kokoro-82M - Hugging Face](https://huggingface.co/hexgrad/Kokoro-82M) - 82M parameter TTS model
- [Kokoro-82M ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX) - ONNX quantized version
- [Kokoro JS - npm](https://www.npmjs.com/package/kokoro-js) - Node.js/browser TTS library
- [Flite TTS](http://cmuflite.org/) - Lightweight TTS engine
- [eSpeak NG](https://github.com/espeak-ng/espeak-ng) - Compact TTS engine
- [Suno Bark - GitHub](https://github.com/suno-ai/bark) - Transformer-based TTS (not recommended)

### NeuTTS Resources

- [NeuTTS Air - Hugging Face](https://huggingface.co/neuphonic/neutts-air) - Air model repository
- [NeuTTS Air Q4 GGUF](https://huggingface.co/neuphonic/neutts-air-q4-gguf) - Quantized version
- [NeuTTS Air Q8 GGUF](https://huggingface.co/neuphonic/neutts-air-q8-gguf) - Higher quality quantized
- [NeuTTS Nano - Hugging Face](https://huggingface.co/neuphonic/neutts-nano) - Nano model repository
- [NeuTTS Nano Q4 GGUF](https://huggingface.co/neuphonic/neutts-nano-q4-gguf) - Quantized version
- [NeuTTS Air - GitHub](https://github.com/neuphonic/neutts-air) - Official repository
- [NeuCodec - Hugging Face](https://huggingface.co/neuphonic/neucodec) - Neural audio codec
- [NeuTTS Demo - Hugging Face Spaces](https://huggingface.co/spaces/neuphonic/neutts-air) - Live demo
- [NeuTTS Official](https://www.neutts.org/) - Project website

### TTS Performance Research

- [Piper on Raspberry Pi](https://medium.com/@vadikus/easy-guide-to-text-to-speech-on-raspberry-pi-5-using-piper-tts-cc5ed537a7f6) - CPU-based deployment
- [Kokoro Installation Guide](https://dev.to/nodeshiftcloud/a-step-by-step-guide-to-install-kokoro-82m-locally-for-fast-and-high-quality-tts-58ed) - Local setup
- [Kokoro ONNX Performance](https://kokorotts.net/models/Kokoro/Kokoro-82m) - Performance benchmarks

### ccbell Implementation Research

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - For playing generated TTS WAV files
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L34-L91) - macOS `say` available, Linux needs package install
- [ffplay as fallback](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Can play any format TTS generates

---

[Back to Feature Index](index.md)
