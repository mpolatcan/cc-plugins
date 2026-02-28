---
name: Sound Packs
description: Allow users to browse, preview, and install AI-generated sound packs that bundle sounds for all notification events
category: sound
---

# Feature: Sound Packs

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs come from two sources:

- **Official packs**: Curated by the admin, distributed via GitHub releases on [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs)
- **User-generated packs**: Created by any user via [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator), installed directly via download URL

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
- **Official distribution**: Admin publishes curated packs as GitHub releases on [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs) with `index.json` catalog
- **User distribution**: Generator provides a download URL for any user's pack (zip with `pack.json` + `*.wav`)
- **Installation**:
  - Official: `/ccbell:packs install minimal` (from catalog)
  - User-generated: `/ccbell:packs install --url <download_url>` (from generator)

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

| Aspect | Production (`ccbell`) | Nightly (`ccbell-nightly`) |
|--------|----------------------|---------------------------|
| :hand: Official Packs | `/ccbell:packs browse`, `/ccbell:packs install minimal` | `/ccbell-nightly:packs browse`, `/ccbell-nightly:packs install minimal` |
| :hand: User Packs | `/ccbell:packs install --url <url>` | `/ccbell-nightly:packs install --url <url>` |
| :wrench: Configuration | Adds `packs` and `activePack` to `~/.claude/ccbell.config.json` | Adds `packs` and `activePack` to `~/.claude/ccbell-nightly.config.json` |
| :file_folder: Packs Directory | `~/.claude/ccbell/packs/` | `~/.claude/ccbell-nightly/packs/` |
| :gear: Default Behavior | Browses official pack index from ccbell-sound-packs | Browses official pack index from ccbell-sound-packs |

### Nightly Variant Isolation

The nightly variant achieves pack directory isolation via the `CCBELL_PACKS_DIR` environment variable exported by the nightly `ccbell.sh` script:

```bash
export CCBELL_PACKS_DIR="$HOME/.claude/ccbell-nightly/packs"
```

The nightly binary reads this env var (falling back to the default `~/.claude/ccbell/packs/` if not set).

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins (both production and nightly variants):

#### Production (`plugins/ccbell/production/`)

| File | Description |
|------|-------------|
| `plugins/ccbell/production/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/production/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/production/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/production/commands/*.md` | :page_facing_up: Add `packs.md` command doc |
| `plugins/ccbell/production/sounds/` | :sound: Audio files (no change) |

#### Nightly (`plugins/ccbell/nightly/`)

| File | Description |
|------|-------------|
| `plugins/ccbell/nightly/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/nightly/scripts/ccbell.sh` | :arrow_down: Download script (version sync, exports `CCBELL_PACKS_DIR`) |
| `plugins/ccbell/nightly/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/nightly/commands/*.md` | :page_facing_up: Add `packs.md` command doc (uses `/ccbell-nightly:` prefix) |
| `plugins/ccbell/nightly/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `packs` and `activePack` sections |
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

The generator supports 10 pack-relevant events mapped to Claude Code hook types:

| Event Name | Hook Type | Matcher | Description | Category |
|------------|-----------|---------|-------------|----------|
| `stop` | `Stop` | - | Main agent finished its task | Core |
| `subagent` | `SubagentStop` | `*` | Subagent finished its task | Core |
| `permission_prompt` | `Notification` | `permission_prompt` | Tool needs user permission | Core |
| `idle_prompt` | `Notification` | `idle_prompt` | Agent waiting for user input | Core |
| `session_start` | `SessionStart` | - | New Claude Code session started | Session |
| `session_end` | `SessionEnd` | - | Claude Code session ended | Session |
| `pre_tool_use` | `PreToolUse` | `*` | Before a tool call executes | Tool |
| `post_tool_use` | `PostToolUse` | `*` | After a tool completes | Tool |
| `subagent_start` | `SubagentStart` | `*` | New subagent spawned | Agent |
| `user_prompt_submit` | `UserPromptSubmit` | - | User submitted a new prompt | Agent |

> **Note:** `permission_prompt` and `idle_prompt` are **matchers** under the `Notification` hook event, not standalone hook types. The `Notification` event also supports `auth_success` and `elicitation_dialog` matchers which may be relevant for future pack events. Claude Code has 17+ hook event types in total; this table lists only the events relevant to sound packs.

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

A full-stack web application for AI-powered sound generation, deployed as two separate HuggingFace Spaces:

| Space | URL | Access | Purpose |
|-------|-----|--------|---------|
| **Public** | [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) | All users | Generate + download packs |
| **Admin** | [ccbell-sound-generator-admin](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator-admin) (private) | Admin only | Generate + download + publish official packs |

Both spaces share the same codebase. The admin space has the GitHub token configured as a HuggingFace secret, enabling the `/api/publish` endpoint. The public space does not have this token, so `/api/publish` is unavailable.

**CI/CD Deployment:**

Both spaces are deployed from the same [ccbell-sound-generator](https://github.com/mpolatcan/ccbell-sound-generator) repository via a single GitHub Actions workflow using a matrix strategy:

```yaml
# .github/workflows/deploy.yml (simplified)
strategy:
  fail-fast: false
  matrix:
    include:
      - space: ccbell-sound-generator
      - space: ccbell-sound-generator-admin
```

| Trigger | Description |
|---------|-------------|
| Version tag push (`v*.*.*`) | Automatic deploy on release |
| `workflow_dispatch` | Manual deploy with optional version input |

| Secret | Purpose |
|--------|---------|
| `HF_TOKEN` | Write access to both HuggingFace Spaces |
| `HF_USERNAME` | HuggingFace username |

Deploy jobs run in parallel with `fail-fast: false` — if one space fails, the other still deploys.

| Component | Technology |
|-----------|------------|
| Backend | FastAPI (Python 3.11+), uvicorn |
| Frontend | React 19, TypeScript, Vite 6, Tailwind CSS, shadcn/ui |
| AI Models | Stable Audio Open (Small: 341M params, 1.0: 1.1B params) |
| Audio | torchaudio, PyTorch (CPU) |
| Publishing | PyGithub (admin space only, publish to ccbell-sound-packs releases) |
| Deployment | HuggingFace Spaces (Docker SDK, free CPU tier) |

**API Endpoints:**

| Method | Endpoint | Purpose | Public Space | Admin Space |
|--------|----------|---------|:---:|:---:|
| `GET` | `/api/themes` | List available theme presets | Yes | Yes |
| `GET` | `/api/hooks` | List supported hook types | Yes | Yes |
| `POST` | `/api/generate` | Start audio generation (returns job_id) | Yes | Yes |
| `GET` | `/api/audio/{job_id}` | Download generated WAV file | Yes | Yes |
| `WS` | `/api/ws/{job_id}` | Real-time generation progress | Yes | Yes |
| `GET` | `/api/download/{pack_id}` | Download pack as zip (pack.json + WAVs) | Yes | Yes |
| `POST` | `/api/publish` | Publish pack to GitHub release + update index.json | No | Yes |

**Publish Endpoint Availability:**

The `/api/publish` endpoint checks for a `GITHUB_TOKEN` environment variable at startup. If the token is not configured (public space), the endpoint returns `403 Forbidden` and the "Publish" button is hidden in the UI. This is the only difference between the two spaces.

**User Flow (public space):**

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
GET /api/download/{pack_id} → Returns zip file (pack.json + {event}.wav files)
          │
          ▼
Generator UI shows install command:
  /ccbell:packs install --url https://huggingface.co/.../api/download/{pack_id}
```

**Admin Flow (admin space → official packs):**

```
Admin generates sounds (same flow as above)
          │
          ▼
POST /api/publish → Creates GitHub Release on ccbell-sound-packs
                     with pack.json + {event}.wav assets
                   → Updates index.json in repo with new pack entry
```

### ccbell-sound-packs

Repository: [mpolatcan/ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs)

Stores a pack index in git and sound files as release assets:

```
Git Repository (index only)
├── index.json                    # Pack catalog - updated by generator on publish
└── README.md

GitHub Releases (binary assets)
├── minimal-v1.0.0               # pack.json + stop.wav + subagent.wav + ...
├── sci-fi-v1.0.0                # pack.json + stop.wav + subagent.wav + ...
└── ...
```

#### index.json Schema

The `index.json` file is the single source of truth for pack discovery. It is updated by the ccbell-sound-generator when a pack is published. The `/ccbell:packs browse` command fetches this file to list available packs.

```json
{
  "version": 1,
  "updated_at": "2026-03-01T12:00:00Z",
  "packs": [
    {
      "id": "minimal",
      "name": "Minimal",
      "description": "Clean, professional notification sounds",
      "author": "ccbell-sound-generator",
      "version": "1.0.0",
      "release_tag": "minimal-v1.0.0",
      "events": ["stop", "subagent", "permission_prompt", "idle_prompt"],
      "source": {
        "model": "stable-audio-open-small",
        "theme": "minimal"
      }
    },
    {
      "id": "sci-fi",
      "name": "Sci-Fi Ambient",
      "description": "Futuristic digital notification sounds",
      "author": "ccbell-sound-generator",
      "version": "1.0.0",
      "release_tag": "sci-fi-v1.0.0",
      "events": ["stop", "subagent", "permission_prompt", "idle_prompt"],
      "source": {
        "model": "stable-audio-open-small",
        "theme": "sci-fi"
      }
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | number | Index schema version (currently `1`) |
| `updated_at` | string | ISO 8601 timestamp of last update |
| `packs[].id` | string | Pack slug used in install commands |
| `packs[].name` | string | Human-readable display name |
| `packs[].description` | string | Short description |
| `packs[].author` | string | Pack creator |
| `packs[].version` | string | SemVer version |
| `packs[].release_tag` | string | GitHub release tag for downloading assets |
| `packs[].events` | array | List of event names included in the pack |
| `packs[].source` | object | Generation metadata (model, theme) |

| Aspect | Solution |
|--------|----------|
| Repo size | Stays small (single JSON index, no binaries) |
| Browse speed | Single fetch of `index.json` via raw URL |
| Install | Uses `release_tag` to download assets from GitHub Releases |
| Fast clone | Users don't download any sounds |
| Index updates | Generator appends/updates entries on publish |

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

Steps required in cc-plugins repository (for **both** production and nightly variants):

1. Update `plugin.json` version in both `production/` and `nightly/`
2. Update `ccbell.sh` if needed (nightly exports `CCBELL_PACKS_DIR`)
3. Add/update `packs.md` command documentation in both variants
4. Add `sound-packs` keyword to both `plugin.json` manifests
5. Add/update hooks configuration if new events are hooked

### ccbell

Steps required in ccbell repository:

1. Add `packs` and `activePack` fields to config structure
2. Create `internal/pack/packs.go`
3. Implement PackManager with List/Install/Use/Uninstall methods
4. Extend ResolveSoundPath() to handle `pack:` scheme
5. Add packs command with browse/preview/install/use options
6. Implement dual install modes:
   - **Catalog install**: Download pack.json + WAV assets from GitHub releases (official packs)
   - **URL install**: Download zip from any URL, extract to packs dir (user-generated packs)
7. Read packs directory from `CCBELL_PACKS_DIR` env var (default: `~/.claude/ccbell/packs/`)
8. Update version in main.go
9. Tag and release (stable for production, pre-release for nightly)
10. Sync version to cc-plugins for both variants

**Installed Pack Layout (production):**

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

**Installed Pack Layout (nightly):**

```
~/.claude/ccbell-nightly/packs/
├── minimal/
│   ├── pack.json
│   ├── stop.wav
│   └── ...
└── ...
```

## User-Generated Packs

Any user can create and install their own sound packs via the [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) web app.

### Generator-to-ccbell Flow

```
1. Visit ccbell-sound-generator
2. Select theme + events + duration + model
3. Generate sounds
4. Click "Download Pack"
5. Generator shows install command:

   /ccbell:packs install --url https://huggingface.co/.../api/download/{pack_id}

6. Run the command in Claude Code → pack installed
```

No GitHub account, no forking, no publishing. The generator serves the pack zip directly.

### Download Pack Format

The generator's `/api/download/{pack_id}` endpoint returns a zip file:

```
my-pack.zip
├── pack.json
├── stop.wav
├── subagent.wav
├── permission_prompt.wav
├── idle_prompt.wav
└── ...
```

ccbell extracts the zip to `~/.claude/ccbell/packs/{pack_id}/` (or `~/.claude/ccbell-nightly/packs/{pack_id}/` for nightly).

### Temporary Storage

Generated packs are stored temporarily on the generator server (`/tmp/ccbell-audio/`). Download URLs are ephemeral - users should install promptly after generation. If the URL expires, the user can regenerate the pack.

### Manual Local Packs

Users can also create packs manually without the generator:

1. Create a directory in `~/.claude/ccbell/packs/my-pack/` (or `~/.claude/ccbell-nightly/packs/my-pack/`)
2. Add `pack.json` and WAV sound files
3. Use with `/ccbell:packs use my-pack`

Minimum `pack.json` for local packs (only `id`, `name`, `version`, and `events` are required):

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
| GitHub API | Browse and install official packs from releases | For official packs (unauthenticated, 60 req/hr) |
| ccbell-sound-generator | Generate and download user packs | For user-generated packs |

### GitHub API Rate Limits

| Request Type | Rate Limit | Notes |
|--------------|------------|-------|
| Unauthenticated | 60 requests/hour | IP-based, sufficient for pack browsing/install |
| Authenticated (PAT) | 5,000 requests/hour | Personal Access Token |

> **Note:** User-generated packs installed via `--url` do not use the GitHub API. They download directly from the generator's HuggingFace Spaces endpoint.

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
