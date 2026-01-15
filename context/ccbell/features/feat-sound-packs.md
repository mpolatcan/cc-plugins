---
name: Sound Packs
description: Allow users to browse, preview, and install sound packs that bundle sounds for all notification events
---

# Sound Packs

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
7. [Implementation](#implementation)
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

## Implementation

### cc-plugins

Steps required in cc-plugins repository:

```bash
# 1. Update plugin.json version
# 2. Update ccbell.sh if needed
# 3. Add/update command documentation
# 4. Add/update hooks configuration
# 5. Add new sound files if applicable
```

### ccbell

Steps required in ccbell repository:

```bash
# 1. Add packs section to config structure
# 2. Create internal/pack/packs.go
# 3. Implement PackManager with List/Install/Use/Uninstall methods
# 4. Extend ResolveSoundPath() to handle pack: scheme
# 5. Add packs command with browse/preview/install/use options
# 6. Update version in main.go
# 7. Tag and release vX.X.X
# 8. Sync version to cc-plugins
```

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

### Other Findings

Sound pack features:
- Pack index from GitHub releases
- Browse available packs
- Preview pack sounds
- Install/uninstall packs
- Use pack as active configuration
- Per-event overrides supported

## Research Sources

| Source | Description |
|--------|-------------|
| [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
| [Sound path resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Path resolution |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config structure |
