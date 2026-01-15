---
name: TTS Announcements
description: Play spoken announcements instead of or alongside audio files
category: sound
---

# Feature: TTS Announcements

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS.

## Table of Contents

1. [Summary](#summary)
2. [Benefit](#benefit)
3. [Priority & Complexity](#priority--complexity)
4. [Feasibility](#feasibility)
   - [Claude Code](#claude-code)
   - [Audio Player](#audio-player)
   - [External Dependencies](#external-dependencies)
5. [Usage in ccbell Plugin](#usage-in-ccbell-plugin)
6. [Repository Impact](#repository-impact)
   - [cc-plugins](#cc-plugins)
   - [ccbell](#ccbell)
7. [Implementation Plan](#implementation-plan)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
8. [External Dependencies](#external-dependencies-1)
9. [Research Details](#research-details)
10. [Research Sources](#research-sources)

## Summary

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS for accessibility and hands-free awareness.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Voice announcements help users with hearing impairments |
| :memo: Use Cases | Hands-free awareness, rich context announcements |
| :dart: Value Proposition | Personalized experience, accessibility-first |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🟢 Low | |
| :construction: Complexity | 🔴 High | |
| :warning: Risk Level | 🔴 High | |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `tts` command with configure, voices, test options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for TTS execution |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay (macOS) | macOS native audio player | |
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
| :computer: Platform Support | macOS `say`, Linux Piper/Kokoro |
| :musical_note: Audio Formats | TTS generates audio on demand |

### External Dependencies

Are external tools or libraries required?

TTS engines (say, piper, kokoro) required for non-macOS platforms.

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported (native `say` command) |
| ✅ | Linux supported (Piper, Kokoro, MeloTTS) |
| ⚠️  | External dependencies required (TTS engines) |
| ❌ | Windows not supported |

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:tts configure`, `/ccbell:tts voices`, `/ccbell:tts test stop` |
| :wrench: Configuration | Adds `tts` section with engine, voice, phrases, cache options |
| :gear: Default Behavior | Uses native TTS when available (macOS say) |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `tts.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `tts` section |
| `audio/player.go` | :speaker: TTS integration with audio playback |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add/update command documentation
4. Add/update hooks configuration
5. Add new sound files if applicable

### ccbell

Steps required in ccbell repository:

1. Add tts section to config structure
2. Create internal/tts/tts.go
3. Implement TTSManager with Speak() method
4. Support multiple engines: say (macOS), piper, kokoro
5. Add caching for generated speech
6. Add tts command with configure/voices/test options
7. Update version in main.go
8. Tag and release vX.X.X
9. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| say | macOS | Native TTS | ✅ |
| piper | Linux | Fast, local neural TTS | ✅ |
| kokoro | Linux | 82M parameter lightweight TTS | ✅ |
| neutts-air | Cross-platform | 748M parameter on-device TTS with voice cloning | ➖ |
| neutts-nano | Cross-platform | Lightweight on-device TTS | ➖ |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New tts command can be added.

### Claude Code Hooks

No new hooks needed - TTS integrated into main flow.

### Audio Playback

TTS output played through audio player or native command.

### TTS Engine Options Research

#### 1. NeuTTS Air (Recommended - New)
- **Parameters**: 748M (0.5B LLM backbone with Qwen2 architecture)
- **Platform**: CPU-based, runs on phones, laptops, Raspberry Pi
- **Key Features**:
  - World's first super-realistic on-device TTS speech language model
  - Instant voice cloning with 3-10 seconds of reference audio
  - Real-time performance
  - Built-in security (fully offline)
  - No cloud/API keys required
- **Performance**: Optimized for speed and low power usage
- **License**: Open-source (Apache 2.0)
- **Benchmark Devices**: Galaxy A25 5G, AMD Ryzen 9HX 370, iMac M4 16GB, NVIDIA RTX 4090
- **GitHub**: https://github.com/neuphonic/neutts-air

#### 2. NeuTTS Nano
- **Purpose**: Lightweight alternative to NeuTTS Air
- **Use Case**: Resource-constrained devices
- **Platform**: CPU-based, optimized for mobile/embedded
- **Features**: Similar voice cloning capabilities at smaller model size

#### 3. Kokoro-82M (Recommended - Lightweight)
- **Parameters**: 82M (very lightweight)
- **Quality**: Comparable to larger models despite small size
- **Platform**: CPU inference
- **Key Features**:
  - High-quality, natural-sounding speech
  - Fast inference
  - Apache 2.0 license (free for commercial use)
  - Excellent voice expressiveness
- **Performance**: 44% win rate on TTS Arena V2
- **Hugging Face**: https://huggingface.co/hexgrad/Kokoro-82M
- **Web Interface**: Kokoro Web for browser usage

#### 4. Piper TTS
- **Parameters**: Varies by model (typically 40-500M)
- **Platform**: Optimized for Raspberry Pi, CPU inference
- **Key Features**:
  - Fast, local neural TTS
  - Multiple high-quality voices available
  - Easy installation via pip (`pip install piper-tts`)
  - Cross-platform (Linux, macOS)
- **GitHub**: https://github.com/rhasspy/piper
- **Best For**: Low-resource environments, Raspberry Pi

#### 5. Orpheus TTS
- **Parameters**: 3B (Llama-3b backbone)
- **Quality**: State-of-the-art open-source TTS
- **Key Features**:
  - Human-sounding speech quality
  - Multi-lingual support
  - Robust voice cloning
  - Apache License 2.0
- **Use Case**: High-quality local TTS when resources allow
- **GitHub**: https://github.com/canopyai/Orpheus-TTS

#### 6. XTTS-v2 (Coqui AI)
- **Parameters**: ~500M
- **Key Features**:
  - Voice cloning with 6-second audio clip
  - Multi-language support (17+ languages)
  - High-quality voice synthesis
- **Considerations**: Requires Python <3.12, larger model size
- **GitHub**: https://github.com/coqui-ai/TTS

#### 7. Bark (Suno AI)
- **Parameters**: Multiple variants available
- **Key Features**:
  - Multi-speaker support
  - Voice cloning capabilities
  - Can generate expressive speech
- **Considerations**: Higher resource requirements

#### 8. Kyutai Pocket TTS (New - January 2026)
- **URL**: https://kyutai.org/tts
- **Parameters**: 100M (very lightweight)
- **Platform**: CPU-based, real-time inference
- **Key Features**:
  - Released January 2026, cutting-edge model
  - Lightweight enough for real-time CPU processing
  - High-quality voice synthesis
  - Open-source with permissive licensing
- **Best For**: Modern deployments, CPU-constrained environments

#### 9. MeloTTS (Lightweight - Recommended)
- **URL**: https://github.com/myshell-ai/MeloTTS
- **Parameters**: Lightweight, optimized for CPU
- **Platform**: CPU inference, real-time capable
- **Key Features**:
  - High-quality multi-lingual TTS
  - Supports English, Spanish, French, Chinese, Japanese, Korean
  - Optimized for real-time inference on CPUs
  - C++ implementation available (MeloTTS.cpp)
  - Apache 2.0 license
- **Install**: `pip install melo-tts`
- **Best For**: Low-resource devices, production deployments

#### 10. MeloTTS.cpp (C++ Implementation)
- **URL**: https://github.com/apinge/MeloTTS.cpp
- **Purpose**: Pure C++ implementation of MeloTTS
- **Key Features**:
  - No Python dependency
  - Faster inference
  - Easier embedding in Go applications via cgo
  - Minimal memory footprint
- **Best For**: Go integration, performance-critical applications

#### 11. ChatTTS (Dialogue-Optimized)
- **URL**: https://github.com/2noise/ChatTTS
- **Purpose**: TTS designed for dialogue scenarios (LLM assistants)
- **Key Features**:
  - Optimized for conversational AI
  - Natural prosody and emotion
  - Supports笑声 (laughter) tokens
  - Chinese and English support
- **BentoML Integration**: https://github.com/bentoml/BentoChatTTS
- **Best For**: LLM assistant applications, conversational interfaces

#### 12. Larynx (Offline TTS)
- **URL**: https://github.com/rhasspy/larynx
- **Purpose**: Offline, open-source TTS library
- **Key Features**:
  - Optimized for low-power devices
  - Multiple voice models
  - Can use Piper models
- **Best For**: Embedded systems, offline-first applications

#### 13. OpenAI TTS-compatible APIs
For cloud or API-based TTS with local fallback:

| Provider | Quality | Cost | Latency |
|----------|---------|------|---------|
| OpenAI TTS | Excellent | Pay-per-use | Low |
| ElevenLabs | Excellent | Subscription | Low |
| Speechmatics | Excellent | Enterprise | Low |

### BentoML Deployment for TTS

**BentoML** simplifies packaging and serving TTS models:

```python
# bentoml service for Piper TTS
import bentoml
from bentoml.io import AudioIO

runner = bentoml.piper.get("piper:latest").to_runner()
svc = bentoml.Service("piper-tts", runners=[runner])

@svc.api(input=AudioIO(), output=AudioIO())
def synthesize(text):
    return runner.generate.sync(text)
```

**Benefits**:
- One-command model serving
- Auto-generated APIs
- Scaling and batching
- Multiple model support

### TTS Features Summary

- Multiple engine support (say, piper, kokoro, neutts-air, neutts-nano, orpheus, melo-tts, kyutai, chat-tts, larynx)
- Configurable phrases per event
- Voice selection per engine
- Caching for performance
- Works alongside or instead of sounds
- Voice cloning support (NeuTTS Air, Kokoro, Orpheus, XTTS-v2)
- CPU-optimized options for resource-constrained environments
- BentoML deployment for production serving

## Research Sources

| Source | Description |
|--------|-------------|
| [NeuTTS Air - GitHub](https://github.com/neuphonic/neutts-air) | :books: NeuTTS Air - 748M parameter on-device TTS with voice cloning |
| [NeuTTS Air - Hugging Face](https://huggingface.co/neuphonic/neutts-air) | :books: NeuTTS Air model page with benchmarks |
| [NeuTTS Air - Official Site](https://www.neutts.org/) | :books: NeuTTS Air official documentation |
| [Kokoro-82M - Hugging Face](https://huggingface.co/hexgrad/Kokoro-82M) | :books: Kokoro TTS - 82M lightweight open-source TTS |
| [Kokoro TTS - Official](https://kokorottsai.com/) | :books: Kokoro TTS official site |
| [Piper TTS - GitHub](https://github.com/rhasspy/piper) | :books: Piper TTS - Fast local neural TTS |
| [Orpheus TTS - GitHub](https://github.com/canopyai/Orpheus-TTS) | :books: Orpheus TTS - SOTA open-source TTS on Llama-3b |
| [XTTS-v2 - Hugging Face](https://huggingface.co/coqui/XTTS-v2) | :books: XTTS-v2 - Coqui AI multilingual voice cloning |
| [Kyutai Pocket TTS](https://kyutai.org/tts) | :books: Kyutai Pocket TTS - 100M parameter CPU-real-time TTS (Jan 2026) |
| [MeloTTS - GitHub](https://github.com/myshell-ai/MeloTTS) | :books: MeloTTS - Multi-lingual lightweight CPU-optimized TTS |
| [MeloTTS.cpp - GitHub](https://github.com/apinge/MeloTTS.cpp) | :books: Pure C++ implementation for Go integration |
| [ChatTTS - GitHub](https://github.com/2noise/ChatTTS) | :books: ChatTTS - Dialogue-optimized TTS for LLM assistants |
| [BentoChatTTS - BentoML](https://github.com/bentoml/BentoChatTTS) | :books: BentoChatTTS - ChatTTS deployment with BentoML |
| [Larynx - GitHub](https://github.com/rhasspy/larynx) | :books: Larynx - Offline TTS library |
| [The Top Open-Source TTS Models - Modal](https://modal.com/blog/open-source-tts) | :books: Comparison of open-source TTS models |
| [BentoML - Open Source TTS Models 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models) | :books: Comprehensive TTS model comparison |
| [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
