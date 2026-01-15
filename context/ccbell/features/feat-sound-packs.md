---
name: Sound Packs
description: Allow users to browse, preview, and install sound packs that bundle sounds for all notification events
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
| :rocket: Priority | `[High]` |
| :construction: Complexity | `[Medium]` |
| :warning: Risk Level | `[Medium]` |

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
| None | HTTP client | Download packs from GitHub | `[No]` |

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

## Research Sources

| Source | Description |
|--------|-------------|
| [Freesound](https://freesound.org/) | :books: 700,000+ Creative Commons licensed sounds database |
| [Pixabay Audio](https://pixabay.com/sound-effects/) | :books: 110,000+ royalty-free sound effects |
| [Mixkit Sounds](https://mixkit.co/free-sound-effects/) | :books: Free sound effects with Mixkit License |
| [Notification Sounds](https://notificationsounds.com/) | :books: Mobile notification sounds and ringtones |
| [Zedge](https://www.zedge.net/) | :books: Mobile ringtones and notification sounds |
| [SoundBible](https://soundbible.com/) | :books: Free sound clips in WAV and MP3 |
| [Free To Use Sounds](https://www.freetousesounds.com/) | :books: 15,000+ royalty-free sound recordings |
| [Zapsplat Notification Bells](https://www.zapsplat.com/sound-effect-packs/notification-bells/) | :books: 62 professional notification bell sounds |
| [Free Sounds Library](https://www.freesoundslibrary.com/) | :books: High-quality SFX with CC0 + CC-BY |
| [Uppbeat Sound Effects](https://uppbeat.io/blog/sound-effects/best-sound-effect-packs) | :books: Curated free sound effect packs |
| [Artlist Notifications](https://artlist.io/collection/notifications/11517) | :books: Professional notification SFX collection |
| [Freesound API](https://freesound.org/docs/api/) | :books: Freesound API documentation |
| [akx/Notifications - GitHub](https://github.com/akx/Notifications) | :books: Hand-crafted notification tones |
| [EdgeTX Sound Packs - GitHub](https://github.com/EdgeTX/edgetx-sdcard-sounds) | :books: Structured sound pack releases |
| [SONNISS GameAudioGDC](https://sonniss.com/gameaudiogdc/) | :books: Professional game audio archives |
| [Top 12 Free Sound Effects Sites - SFX Engine](https://sfxengine.com/blog/free-sound-effects-download) | :books: Guide to free sound effects resources |
| [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
| [Sound path resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Path resolution |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config structure |
