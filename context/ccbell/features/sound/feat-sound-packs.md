---
name: Sound Packs
description: Allow users to browse, preview, and install sound packs that bundle sounds for all notification events
category: sound
---

# Feature: Sound Packs

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs are distributed via GitHub releases.

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

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Distributed via GitHub releases with one-click installation.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Install complete sound themes with a single command |
| :memo: Use Cases | Community creativity, consistent experience |
| :dart: Value Proposition | One-click variety, easy discovery |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🔴 High | |
| :construction: Complexity | 🟡 Medium | |
| :warning: Risk Level | 🟡 Medium | |

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
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | Supports bundled sound formats |

### External Dependencies

Are external tools or libraries required?

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

1. Add packs section to config structure
2. Create internal/pack/packs.go
3. Implement PackManager with List/Install/Use/Uninstall methods
4. Extend ResolveSoundPath() to handle pack: scheme
5. Add packs command with browse/preview/install/use options
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | HTTP client | Download packs from GitHub | ❌ |

### API Rate Limits

Understanding rate limits is critical for sound pack and download features.

#### GitHub API (for Sound Pack Distribution)

| Request Type | Rate Limit | Notes |
|--------------|------------|-------|
| Unauthenticated | 60 requests/hour | IP-based, no token needed |
| Authenticated (PAT) | 5,000 requests/hour | Personal Access Token |
| GitHub Enterprise | 15,000 requests/hour | Enterprise Cloud orgs |

**Current Implementation Status**: Uses unauthenticated requests for GitHub releases (60 req/hr is sufficient for pack browsing).

#### Freesound API

| Operation | Rate Limit | Daily Limit | Authentication |
|-----------|------------|-------------|----------------|
| General API | 60 requests/minute | 2,000/day | API key required |
| Upload/Comment/Rate | 30 requests/minute | 500/day | API key + OAuth2 |
| OAuth2 for download | Requires full OAuth flow | - | Per-user authorization |

**API Key Registration**: https://freesound.org/apiv2/apply (free for non-commercial use)

**Implementation Notes**:
- All requests require `token` parameter or `Authorization: Token` header
- Download requires OAuth2 (more complex than Pixabay)
- 60 req/min is generous for typical usage

#### Pixabay API

| Authentication | Rate Limit | Notes |
|----------------|------------|-------|
| Without API key | 5 requests/second | Limited |
| With API key | 100 requests/60 seconds | Recommended |
| Caching required | 24 hours minimum | Must cache search results |

**API Key Registration**: https://pixabay.com/api/docs/ (free, instant)

**Implementation Notes**:
- API key is free and instant to obtain
- No API key needed for basic searches (limited rate)
- Results must be cached for 24 hours per terms of service
- Simpler integration than Freesound

#### Rate Limit Comparison Summary

| Provider | Sounds | Auth Required | Rate Limit | Daily Capacity |
|----------|--------|---------------|------------|----------------|
| GitHub Releases | Pack metadata | No | 60 req/hour | 1,440 requests |
| Pixabay | 110,000+ | Optional | 100 req/minute | ~144,000 searches |
| Freesound | 700,000+ | API Key required | 60 req/minute | ~86,400 searches |

### Custom User Packs Feasibility

Custom user packs would allow users to create and use their own sound packs without needing to create GitHub releases.

#### Implementation Options

##### Option 1: Local Pack Directory
```
~/.claude/ccbell/packs/
├── my-custom-pack/
│   ├── pack.json
│   ├── stop.wav
│   ├── permission.aiff
│   └── ...
```

**Pros**:
- No network required
- Full user control
- No authentication needed
- Fast iteration

**Cons**:
- No discovery/browsing
- Manual configuration

##### Option 2: Local + Git Repository
```
~/.claude/ccbell/packs/  # Clone of user repos
```

**Pros**:
- Version control
- Community sharing via git
- Pull updates easily

**Cons**:
- Requires git knowledge
- More complex setup

##### Option 3: GitHub Gist-Based Packs
```
# User creates Gist with pack.json + sounds
# ccbell installs from Gist URL
```

**Pros**:
- Easy sharing
- GitHub-native
- No dedicated repo needed

**Cons**:
- Requires GitHub account
- Larger files may be problematic

#### Recommendation

**For ccbell v0.3.x**: Focus on GitHub releases (current implementation)

**Future Enhancement**: Add local pack support for power users who want custom sounds without GitHub releases

```bash
/ccbell:packs create my-pack  # Scaffold a new pack
/ccbell:packs add stop.wav    # Add sounds to pack
/ccbell:packs local my-pack   # Use local pack
```

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New packs command can be added.

### Claude Code Hooks

No new hooks needed - sound packs integrated into config.

### Audio Playback

Pack sounds resolved via `pack:` scheme in sound configuration.

### Free Sound Pack Sources Research

#### 1. Freesound (Recommended - Community-Driven)
- **URL**: https://freesound.org/
- **Sounds**: 700,000+ Creative Commons licensed sounds
- **License**: Creative Commons (various: CC0, CC-BY, CC-BY-NC)
- **API**: Free API available for non-commercial use
- **Categories**: Field recordings, sound effects, musical samples
- **Best For**: High-quality, diverse sound effects with community curation
- **Note**: Celebrating 20 years in 2025, one of the largest collaborative sound databases

#### 2. Pixabay Audio (Recommended - Royalty-Free)
- **URL**: https://pixabay.com/sound-effects/
- **Sounds**: 110,000+ royalty-free sound effects
- **License**: Pixabay License (free for commercial use)
- **API**: Available via Pixabay API
- **Categories**: Notification, alarm, alert, modern sounds
- **Notification Sounds**: 1,455+ notification-specific sounds
- **Best For**: Production-ready sounds without attribution requirements

#### 3. Mixkit (Recommended - License Clarity)
- **URL**: https://mixkit.co/free-sound-effects/
- **Sounds**: 1,000+ free sound effects
- **License**: Mixkit License (free for commercial use)
- **Categories**: Notification, alerts, bell, tones
- **Notification Sounds**: 36 dedicated notification sounds
- **Best For**: Clean, modern notification sounds with clear licensing

#### 4. Notification Sounds (Notification-Focused)
- **URL**: https://notificationsounds.com/
- **Sounds**: Hundreds of original notification sounds
- **License**: Proprietary (free for personal use)
- **Categories**: Mobile ringtones, UI sounds, alerts
- **Best For**: Mobile-style notification tones

#### 5. Zedge (Mobile Notifications)
- **URL**: https://www.zedge.net/
- **Sounds**: 100+ notification ringtones for 2025
- **License**: Free for personal use
- **Platform**: Mobile-focused (Android, iOS apps available)
- **Best For**: Trendy mobile notification sounds

#### 6. SoundBible (Variety)
- **URL**: https://soundbible.com/
- **Sounds**: Thousands of free sound effects
- **License**: Creative Commons + Public Domain
- **Formats**: WAV, MP3
- **Categories**: Static, modern, customer sounds
- **Best For**: Quick downloads without sign-up required

#### 7. Free To Use Sounds
- **URL**: https://www.freetousesounds.com/
- **Sounds**: 15,000+ sound recordings
- **License**: Royalty-free for commercial use
- **Categories**: Field recordings, SFX, ambiences
- **Best For**: Professional-quality field recordings

#### 8. GitHub-Based Sound Packs

**akx/Notifications**
- **URL**: https://github.com/akx/Notifications
- **License**: Dual license (flexible)
- **Content**: Hand-crafted, subtle notification tones
- **Best For**: Minimalist, clean notification sounds

**EdgeTX Sound Packs**
- **URL**: https://github.com/EdgeTX/edgetx-sdcard-sounds
- **Releases**: Regular sound pack updates (v2.11.3, Aug 2025)
- **Best For**: Structured, organized sound packs

**Fris0uman/CDDA-Soundpacks**
- **URL**: https://github.com/Fris0uman/CDDA-Soundpacks
- **License**: CC0, CC-BY (properly licensed)
- **Best For**: CC0-licensed game sound packs

#### 9. Zapsplat (Professional Quality)
- **URL**: https://www.zapsplat.com/sound-effect-packs/notification-bells/
- **Sounds**: 62 free notification bell sound effects
- **License**: Free for commercial use (with attribution)
- **Categories**: UI alerts, bells, chimes
- **Best For**: Professional-quality notification bells

#### 10. Free Sounds Library
- **URL**: https://www.freesoundslibrary.com/
- **Sounds**: High-quality SFX library
- **License**: CC0 + CC-BY (check individual files)
- **Categories**: Notifications, chimes, alerts
- **Best For**: Attribution-flexible sound selection

#### 11. Uppbeat Sound Effects
- **URL**: https://uppbeat.io/blog/sound-effects/best-sound-effect-packs
- **Content**: Blog with curated free sound effect packs
- **License**: Various (check individual packs)
- **Categories**: Notification sounds, bells, UI sounds
- **Best For**: Discovery of curated, themed packs

#### 12. Artlist Notifications
- **URL**: https://artlist.io/collection/notifications/11517
- **Sounds**: Professional notification SFX collection
- **License**: Commercial license included
- **Categories**: Modern UI notifications, bells
- **Best For**: Production-ready, polished notification sounds

#### 13. SONNISS GameAudioGDC
- **URL**: https://sonniss.com/gameaudiogdc/
- **Content**: Professional game audio archives
- **License**: Royalty-free, commercially usable
- **Best For**: High-quality game notification sounds

### Sound Pack Distribution Strategy

#### Recommended Approach: GitHub Releases
- Host sound packs in dedicated repository (e.g., `ccbell/sound-packs`)
- Each pack as a release with:
  - `pack.json` metadata (name, description, author, version)
  - Individual sound files for each event type
  - Preview audio files
- Index file listing available packs from GitHub API

#### Alternative: Dedicated Pack Index
- Create `ccbell/packs-index` repository
- JSON index with pack metadata and download URLs
- Easier pack discovery and browsing

### Sound Pack Features

- Pack index from GitHub releases or dedicated index repository
- Browse available packs with metadata
- Preview pack sounds before installation
- Install/uninstall packs with dependency handling
- Use pack as active configuration
- Per-event overrides supported within packs
- Mix and match sounds from different packs

---

## Feature: Auto-Generated Sound Packs via CI Pipeline

Instead of integrating download functionality into ccbell binary, create a CI pipeline in `ccbell-sound-packs` repository that:
1. Queries sound providers (Freesound, Pixabay) periodically
2. Downloads and curates sounds
3. Creates sound packs
4. Publishes as GitHub releases

**Users install via:** `/ccbell:packs install minimal` (no API keys needed)

### Table of Contents

1. [Summary](#summary-1)
2. [Benefit](#benefit-1)
3. [Priority & Complexity](#priority--complexity-1)
4. [Architecture](#architecture)
5. [CI Pipeline Design](#ci-pipeline-design)
6. [Repository Impact](#repository-impact-1)
7. [Implementation Plan](#implementation-plan-1)
8. [Research Sources](#research-sources-1)

### Summary

Create a CI/CD pipeline in a separate `ccbell-sound-packs` repository that:
- Periodically queries free sound providers (Freesound, Pixabay)
- Downloads and curates high-quality notification sounds
- Packages them into sound packs
- Publishes automatically as GitHub releases

**User Experience:** Users install pre-built packs via `/ccbell:packs install` - no API keys, no complexity.

### Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Access curated sounds without API keys or OAuth |
| :memo: Use Cases | Automatic updates, community curation |
| :dart: Value Proposition | Zero-config sound variety |

### Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🔴 High |
| :construction: Complexity | 🟡 Medium |
| :warning: Risk Level | 🟢 Low |

### Architecture

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│  ccbell-sound-packs  │     │   CI Pipeline        │ │   GitHub Releases   │
│   Repository        │────▶│   (GitHub Actions)   │────▶│   (Pack Downloads)  │
│                     │     │                      │ │                     │
│ ├── packs/          │     │ ├── Query Providers  │ │   ├── minimal-v1    │
│ │   ├── minimal/    │     │ ├── Download Sounds  │ │   ├── classic-v1    │
│ │   │   └── pack.json│    │ ├── Convert Format   │ │   └── futuristic-v1 │
│ │   ├── classic/    │     │ └── Create Release   │ │                     │
│ │   └── ...         │     │                      │ └─────────────────────┘
│ └── .github/workflows/                              │
│       └── ci.yml                                    │
└─────────────────────┘                                    │
       │                                                  │
       │ /ccbell:packs install minimal                   │
       ▼                                                  │
┌─────────────────────┐                                   │
│   ccbell Plugin     │◀──────────────────────────────────┘
│                     │     Uses existing pack mechanism
│ └── packs command   │     No API keys needed!
└─────────────────────┘
```

### CI Pipeline Design

#### Workflow Triggers

| Trigger | Description |
|---------|-------------|
| Scheduled | Weekly/monthly curation updates |
| Manual | On-demand pack updates |
| Tag | Create new pack version |

#### Pipeline Steps

```yaml
# .github/workflows/curate.yml
name: Curation Pipeline

on:
  schedule:
    - cron: '0 0 1 * *'  # Monthly on 1st
  workflow_dispatch:
    inputs:
      provider:
        description: 'Provider to query (freesound, pixabay)'
        required: false
        default: 'pixabay'

jobs:
  curate:
    runs-on: ubuntu-latest
    steps:
      - name: Query Pixabay
        run: |
          # Query and download top-rated notification sounds
          curl "https://pixabay.com/api/?q=notification&category=sound-effects&key=$PIXABAY_API_KEY"

      - name: Convert to AIFF
        run: |
          # Convert MP3/WAV to AIFF for macOS compatibility
          for f in downloads/*.{mp3,wav}; do
            ffmpeg -i "$f" "${f%.*}.aiff"
          done

      - name: Create Pack
        run: |
          # Create pack.json with metadata
          # Package sounds into release

      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### Provider Integration

| Provider | Auth | Rate Limit | Daily Limit | Notes |
|----------|------|------------|-------------|-------|
| **Pixabay** | API Key (env) | 100 req/min | ~144,000 | Easiest, no OAuth |
| **Freesound** | API Key (env) | 60 req/min | 2,000 | OAuth required for download |

**CI Configuration:**
```bash
# Repository secrets
PIXABAY_API_KEY=your_free_api_key
FREESOUND_API_KEY=your_api_key
# OAuth only needed if Freesound sounds are curated
```

### Repository Impact

#### New Repository: ccbell-sound-packs

| File | Description |
|------|-------------|
| `packs/*/pack.json` | Pack metadata |
| `packs/*/*.aiff` | Curated sounds |
| `.github/workflows/ci.yml` | Curation pipeline |
| `scripts/curate.sh` | Download and package script |

#### ccbell (No Changes)

| File | Description |
|------|-------------|
| - | Uses existing pack mechanism |
| - | No new code needed |

#### cc-plugins (No Changes)

| File | Description |
|------|-------------|
| - | Uses existing pack command |

### Implementation Plan

#### Phase 1: CI Pipeline Setup

1. Set up `ccbell-sound-packs` repository (exists at `../ccbell-sound-packs`)
2. Add GitHub Actions workflow
3. Configure Pixabay API key (free)
4. Create initial `minimal` pack

#### Phase 2: Provider Integration

1. Add Pixabay query to pipeline
2. Add Freesound (optional, requires OAuth)
3. Add format conversion (MP3/WAV → AIFF)

#### Phase 3: Automation

1. Schedule weekly/monthly runs
2. Add quality filters (min duration, max size)
3. Add license verification

#### Phase 4: Community Contributions

1. Accept PRs for new packs
2. Document pack creation guide
3. Add contribution guidelines

### Research Sources

| Source | Description |
|--------|-------------|
| [GitHub REST API Rate Limits](https://docs.github.com/en/rest/overview/rate-limits-for-the-rest-api) | GitHub API rate limits (60 unauthenticated, 5,000 authenticated) |
| [Freesound API](https://freesound.org/docs/api/) | Freesound API v2 documentation (60 req/min, API key required) |
| [Pixabay API](https://pixabay.com/api/docs/) | Pixabay API documentation (100 req/60s with key) |
| [GitHub Actions](https://docs.github.com/en/actions) | CI/CD automation |

## Sound Source Research

| Source | Sounds | License | API | Best For |
|--------|--------|---------|-----|----------|
| [Freesound](https://freesound.org/) | 700K+ | CC (various) | Yes | Maximum variety |
| [Pixabay](https://pixabay.com/sound-effects/) | 110K+ | Pixabay License | Yes | Easiest integration |
| [Mixkit](https://mixkit.co/free-sound-effects/) | 1K+ | Mixkit License | No | Curated packs |
| [akx/Notifications](https://github.com/akx/Notifications) | Pack | Flexible | Yes | Ready-made packs |

### Internal Documentation

| Source | Description |
|--------|-------------|
| [Audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | Current audio playback implementation |
| [Sound path resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | Path resolution logic |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | Configuration schema |
