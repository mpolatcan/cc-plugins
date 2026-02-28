---
name: Sound Packs
description: Allow users to browse, preview, and install AI-generated sound packs that bundle sounds for all notification events
category: sound
---

# Feature: Sound Packs

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs are AI-generated via [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) and distributed via GitHub releases on the [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs) repository.

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
7. [Sound Pack Format](#sound-pack-format)
   - [pack.json Schema](#packjson-schema)
   - [Supported Events](#supported-events)
   - [Release Asset Structure](#release-asset-structure)
8. [Architecture](#architecture)
   - [ccbell-sound-generator](#ccbell-sound-generator)
   - [ccbell-sound-packs](#ccbell-sound-packs)
   - [Theme Presets](#theme-presets)
9. [Implementation Plan](#implementation-plan)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
10. [Custom User Packs](#custom-user-packs)
11. [Research Sources](#research-sources)

## Summary

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Distributed via GitHub releases with one-click installation.

**How it works:**
- **Generation**: AI-powered web app ([ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator)) generates sounds using Stable Audio Open models
- **Distribution**: Packs published as GitHub releases on [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs) with `pack.json` + `*.wav` assets
- **Storage**: `pack.json` manifests in git (small), sound files as release assets (binary)
- **Installation**: Users run `/ccbell:packs install minimal` - no API keys needed

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Install complete sound themes with a single command |
| :memo: Use Cases | AI-generated themes, community creativity, consistent experience |
| :dart: Value Proposition | One-click variety, easy discovery, no manual sound creation |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | High |
| :construction: Complexity | Medium |
| :warning: Risk Level | Medium |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `packs` command with browse/preview/install/use options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash, WebFetch tools for pack management |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Extends ResolveSoundPath() to handle `pack:` scheme |
| :computer: Platform Support | Cross-platform compatible (afplay on macOS, aplay/paplay on Linux) |
| :musical_note: Audio Format | WAV (44.1kHz stereo PCM) |

### External Dependencies

HTTP client for downloading packs from GitHub releases.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:packs browse`, `/ccbell:packs install minimal` |
| :wrench: Configuration | Adds `packs` section and `pack:` sound scheme support |
| :gear: Default Behavior | Browses pack index from GitHub releases |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `packs.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `packs` section |
| `audio/player.go` | :speaker: Extend ResolveSoundPath() for pack scheme |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Sound Pack Format

### pack.json Schema

Each sound pack is defined by a `pack.json` manifest published as a GitHub release asset:

```json
{
  "id": "sci-fi-ambient",
  "name": "Sci-Fi Ambient",
  "description": "Futuristic digital notification sounds",
  "author": "ccbell-sound-generator",
  "version": "1.0.0",
  "events": {
    "stop": "stop.wav",
    "subagent": "subagent.wav",
    "permission_prompt": "permission_prompt.wav",
    "idle_prompt": "idle_prompt.wav",
    "session_start": "session_start.wav",
    "session_end": "session_end.wav",
    "pre_tool_use": "pre_tool_use.wav",
    "post_tool_use": "post_tool_use.wav",
    "subagent_start": "subagent_start.wav",
    "user_prompt_submit": "user_prompt_submit.wav"
  },
  "prompts": {
    "stop": "completion chime, sci-fi, digital synthesizer, technological, 2.0 seconds, 44.1kHz stereo",
    "subagent": "soft confirmation ding, sci-fi, ...",
    "..."
  },
  "source": {
    "provider": "ccbell-sound-generator",
    "model": "stable-audio-open-small",
    "license": "stabilityai/stable-audio-open-1.0"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Pack slug used in install commands and release tags |
| `name` | string | Human-readable display name |
| `description` | string | Short description of the pack |
| `author` | string | Pack creator (defaults to `ccbell-sound-generator`) |
| `version` | string | SemVer version string |
| `events` | object | Maps event names to WAV filenames |
| `prompts` | object | Maps event names to the AI prompt used for generation |
| `source` | object | Generation metadata (provider, model, license) |

### Supported Events

The generator supports all 10 Claude Code hook types:

| Event Name | Hook Type | Description | Category |
|------------|-----------|-------------|----------|
| `stop` | `Stop` | Main agent finished its task | Core |
| `subagent` | `SubagentStop` | Subagent finished its task | Core |
| `permission_prompt` | `PermissionPrompt` | Tool needs user permission | Core |
| `idle_prompt` | `IdlePrompt` | Agent waiting for user input | Core |
| `session_start` | `SessionStart` | New Claude Code session started | Session |
| `session_end` | `SessionEnd` | Claude Code session ended | Session |
| `pre_tool_use` | `PreToolUse` | Before a tool call executes | Tool |
| `post_tool_use` | `PostToolUse` | After a tool completes | Tool |
| `subagent_start` | `SubagentStart` | New subagent spawned | Agent |
| `user_prompt_submit` | `UserPromptSubmit` | User submitted a new prompt | Agent |

### Release Asset Structure

Each pack is published as a GitHub release on [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs):

- **Release tag**: `{pack_id}-v{version}` (e.g., `minimal-v1.0.0`)
- **Assets**: `pack.json` + individual `{event_name}.wav` files (not zipped)

```
Release: minimal-v1.0.0
├── pack.json                    # Pack manifest
├── stop.wav                     # 44.1kHz stereo WAV
├── subagent.wav
├── permission_prompt.wav
├── idle_prompt.wav
├── session_start.wav
├── session_end.wav
├── pre_tool_use.wav
├── post_tool_use.wav
├── subagent_start.wav
└── user_prompt_submit.wav
```

**Audio Specifications:**
- Format: WAV (PCM)
- Sample Rate: 44.1 kHz
- Channels: Stereo
- Size: ~500KB-5MB per file (varies by duration and model)

## Architecture

### ccbell-sound-generator

A full-stack web application deployed on [HuggingFace Spaces](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) for AI-powered sound generation.

| Component | Technology |
|-----------|------------|
| Backend | FastAPI (Python 3.11+), uvicorn |
| Frontend | React 19, TypeScript, Vite 6, Tailwind CSS, shadcn/ui |
| AI Models | Stable Audio Open (Small: 341M params, 1.0: 1.1B params) |
| Audio | torchaudio, PyTorch (CPU) |
| Publishing | PyGithub (publish to ccbell-sound-packs releases) |
| Deployment | HuggingFace Spaces (Docker SDK, free CPU tier) |

**Key API Endpoints:**

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/themes` | List available theme presets |
| `GET` | `/api/hooks` | List supported hook types |
| `POST` | `/api/generate` | Start audio generation (returns job_id) |
| `GET` | `/api/audio/{job_id}` | Download generated WAV file |
| `WS` | `/api/ws/{job_id}` | Real-time generation progress |
| `POST` | `/api/publish` | Publish pack to GitHub release |

**Generation Flow:**

```
User selects theme + hook types + duration + model
          │
          ▼
POST /api/generate → AudioGenerationJob
          │
          ▼
Stable Audio Open model generates audio
(stages: loading_model → preparing → generating → processing_audio → saving → completed)
          │
          ▼
WAV file stored in /tmp/ccbell-audio/{job_id}.wav
          │
          ▼
POST /api/publish → Creates GitHub Release on ccbell-sound-packs
                     with pack.json + {event}.wav assets
```

### ccbell-sound-packs

Repository: [mpolatcan/ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs)

Stores pack metadata in git and sound files as release assets:

```
Git Repository (metadata only)
├── packs/
│   ├── minimal/pack.json         # Committed to git
│   ├── sci-fi/pack.json
│   ├── retro-8bit/pack.json
│   └── ...
└── README.md

GitHub Releases (binary assets)
├── minimal-v1.0.0               # pack.json + stop.wav + subagent.wav + ...
├── sci-fi-v1.0.0                # pack.json + stop.wav + subagent.wav + ...
└── ...
```

| Aspect | Solution |
|--------|----------|
| Repo size | Stays small (no binary bloat) |
| Version control | pack.json changes tracked in git |
| Fast clone | Users don't download all sounds |
| ccbell reads | From release assets via GitHub API |

### Theme Presets

The generator includes 7 built-in themes + custom prompt support:

| Theme | ID | Description | Style |
|-------|----|-------------|-------|
| Sci-Fi | `sci-fi` | Futuristic digital sounds | Digital synth, oscillator, modular synth |
| Retro 8-bit | `retro-8bit` | Classic video game chiptune | Chiptune synth, square/pulse/triangle waves |
| Nature | `nature` | Organic natural elements | Wind chimes, wood percussion, kalimba |
| Minimal | `minimal` | Clean, professional tones | Pure melodic tone, glass chimes, bells |
| Mechanical | `mechanical` | Industrial metallic textures | Metal percussion, anvil, spring resonance |
| Ambient | `ambient` | Warm atmospheric sounds | Synth pads, reverb piano, string ensemble |
| Jazz | `jazz` | Smooth jazz tones | Muted trumpet, upright bass, vibraphone |
| Custom | `custom` | User-written prompts | Free-form text input |

Each theme has **tiered prompt components** (simple, standard, detailed) controlling generation richness:
- **Simple**: 1-2 descriptors per category (fastest generation)
- **Standard**: 2-3 descriptors (balanced)
- **Detailed**: 3-5 descriptors (richest output)

Prompt assembly pattern:
```
"{sound_character}, {style}, {instruments}, {mood}, {duration} seconds, {quality}"
```

**AI Models:**

| Model | Parameters | Max Duration | Default Steps | Sampler |
|-------|-----------|--------------|---------------|---------|
| Small | 341M | 11.0s | 8 | pingpong |
| 1.0 | 1.1B | 47.0s | 100 | dpmpp-3m-sde |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add/update command documentation for `packs` command
4. Add/update hooks configuration

### ccbell

Steps required in ccbell repository:

1. Add packs section to config structure
2. Create `internal/pack/packs.go`
3. Implement PackManager with List/Install/Use/Uninstall methods
4. Extend ResolveSoundPath() to handle `pack:` scheme
5. Add packs command with browse/preview/install/use options
6. Download pack.json + WAV assets from GitHub releases
7. Store installed packs in `~/.claude/ccbell/packs/{pack_id}/`
8. Update version in main.go
9. Tag and release
10. Sync version to cc-plugins

**Installed Pack Layout:**

```
~/.claude/ccbell/packs/
├── minimal/
│   ├── pack.json
│   ├── stop.wav
│   ├── subagent.wav
│   ├── permission_prompt.wav
│   ├── idle_prompt.wav
│   └── ...
├── sci-fi/
│   ├── pack.json
│   └── ...
└── ...
```

## Custom User Packs

Custom user packs allow users to create and use their own sound packs without the generator.

### Local Pack Directory

```
~/.claude/ccbell/packs/
├── my-custom-pack/
│   ├── pack.json
│   ├── stop.wav
│   ├── permission_prompt.wav
│   └── ...
```

**Pros**:
- No network required
- Full user control
- No authentication needed
- Fast iteration
- Compatible with AI-generated or manually sourced sounds

**Cons**:
- No discovery/browsing
- Manual configuration

### Minimum pack.json for Local Packs

Local packs only require core fields:

```json
{
  "id": "my-custom-pack",
  "name": "My Custom Pack",
  "version": "1.0.0",
  "events": {
    "stop": "stop.wav",
    "permission_prompt": "permission_prompt.wav"
  }
}
```

The `prompts` and `source` fields are optional for local packs (they are auto-populated by the generator for published packs).

### Future Commands

```bash
/ccbell:packs create my-pack    # Scaffold a new local pack
/ccbell:packs add stop.wav      # Add sounds to pack
/ccbell:packs local my-pack     # Use local pack
```

## Status

| Status | Description |
|--------|-------------|
| :white_check_mark: | macOS supported |
| :white_check_mark: | Linux supported |
| :white_check_mark: | No external dependencies for users (uses Go stdlib) |
| :white_check_mark: | Cross-platform compatible |
| :white_check_mark: | AI generation via HuggingFace Spaces (free CPU tier) |
| :white_check_mark: | WAV format (44.1kHz stereo PCM) |

## External Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| GitHub API | Download packs from releases | Yes (unauthenticated, 60 req/hr) |
| ccbell-sound-generator | Generate new packs | No (optional, for pack creators) |

### GitHub API Rate Limits

| Request Type | Rate Limit | Notes |
|--------------|------------|-------|
| Unauthenticated | 60 requests/hour | IP-based, sufficient for pack browsing/install |
| Authenticated (PAT) | 5,000 requests/hour | Personal Access Token |

## Research Sources

| Source | Description |
|--------|-------------|
| [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) | AI-powered sound generation web app |
| [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs) | Sound pack distribution repository |
| [Stable Audio Open](https://huggingface.co/stabilityai/stable-audio-open-1.0) | AI model for audio generation |
| [GitHub REST API Rate Limits](https://docs.github.com/en/rest/overview/rate-limits-for-the-rest-api) | GitHub API rate limits |

### Internal Documentation

| Source | Description |
|--------|-------------|
| [Audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | Current audio playback implementation |
| [Sound path resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | Path resolution logic |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | Configuration schema |
