---
name: Do Not Disturb Integration
description: Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled
---

# Feature: Do Not Disturb Integration

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled.

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

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled. Integrates with macOS and Linux DND settings.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | No manual toggling when entering DND mode |
| :memo: Use Cases | Focus time, meetings, presentations |
| :dart: Value Proposition | System-level DND controls everything |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[High]` |
| :construction: Complexity | `[Low]` |
| :warning: Risk Level | `[Low]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | No new commands - automatic detection |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Bash for executing platform DND commands |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - playback skipped when DND active |
| :computer: Platform Support | macOS `defaults read`, Linux `gsettings`/`qdbus` |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

Uses system commands (`defaults`, `gsettings`, `qdbus`) which are platform-specific.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Automatic - no user action needed |
| :wrench: Configuration | Optional `dnd` section with `enabled` and `behavior` |
| :gear: Default Behavior | Checks system DND before every notification |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `configure.md` with DND section |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add DND section to config |
| `audio/player.go` | :speaker: Check DND before playback |
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

1. Create internal/dnd/dnd.go for DND detection
2. Implement isMacOSDND() using defaults read
3. Implement isLinuxDND() using gsettings/qdbus
4. Add DND section to config structure
5. Modify main flow to check DND before playing
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| `defaults` | macOS | Read DND status | `[Yes]` |
| `dnd` | Homebrew | CLI tool for DND control (sindresorhus) | `[No]` |
| `gsettings` | Linux/GNOME | Read DND status | `[Yes]` |
| `qdbus` | Linux/KDE | Read DND status | `[Yes]` |
| `hyprctl` | Linux/Hyprland | Wayland compositor DND status | `[No]` |
| `swaymsg` | Linux/Sway | i3-compatible DND status | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports hooks. DND check can be integrated into main flow.

### Claude Code Hooks

No new hooks needed - check DND before existing hooks fire.

### Audio Playback

Playback is skipped when DND is active, but no audio changes needed.

### Platform DND Detection Methods

#### macOS
- **Command**: `defaults read com.apple.notificationcenterui doNotDisturb`
- **Returns**: `1` (enabled) or `0` (disabled)
- **Note**: Works on macOS 10.10+

#### macOS CLI Tool (sindresorhus/do-not-disturb)
- **GitHub**: https://github.com/sindresorhus/do-not-disturb
- **Install**: `brew install --cask dnd`
- **Features**:
  - Toggle DND from command line
  - Query DND status
  - Schedule DND sessions
  - Works with macOS Focus mode
- **Example**:
```bash
# Check if DND is active
dnd status

# Enable DND
dnd on

# Disable DND
dnd off

# Toggle DND
dnd toggle
```
- **Best For**: Scriptable DND control, automation

#### GNOME Linux (X11/Wayland)
- **Command**: `gsettings get org.gnome.desktop.notifications show-banners`
- **Returns**: `true` (notifications enabled) or `false` (DND active)
- **Note**: Requires GNOME Shell or compatible desktop

#### KDE Plasma Linux (X11/Wayland)
- **Command**: `qdbus org.kde.kded /modules/kded readConfig global "doNotDisturb"`
- **Alternative**: Check `org.freedesktop.portal.Desktop` via D-Bus
- **Note**: Works on KDE Plasma 5.20+

#### Hyprland (Wayland Compositor)
- **Command**: `hyprctl keyword decoration:no_border_for_lockscreen_only true`
- **Detection**: Check for lockscreen state via `hyprctl monitors`
- **Alternative**: Use `org.freedesktop.portal.Desktop` on systems with XDG Desktop Portal
- **Install**: Part of Hyprland package
- **Best For**: Modern Wayland setups with Hyprland compositor

#### Sway (i3-compatible Wayland Compositor)
- **Command**: `swaymsg -t get_outputs`
- **Detection**: Check output states for "power saving mode" or similar
- **Alternative**: Use `swayidle` for idle/DND state detection
- **Install**: `swaymsg` comes with Sway installation
- **Best For**: i3 users who migrated to Wayland

#### Universal Wayland (XDG Desktop Portal)
- **Interface**: `org.freedesktop.portal.Desktop`
- **Method**: D-Bus call to check notification policy
- **Install**: `xdg-desktop-portal` package
- **Best For**: Cross-desktop compatibility on Wayland

### Other Findings

Platform DND detection methods:
- macOS: `defaults read com.apple.notificationcenterui doNotDisturb`
- GNOME Linux: `gsettings get org.gnome.desktop.notifications show-banners`
- KDE Linux: `qdbus org.kde.kded /modules/kded readConfig global`
- Hyprland: `hyprctl` active window/lockscreen state
- Sway: `swaymsg` for output and workspace state
- Universal: D-Bus via `org.freedesktop.portal.Desktop`

## Research Sources

| Source | Description |
|--------|-------------|
| [sindresorhus/do-not-disturb](https://github.com/sindresorhus/do-not-disturb) | :books: macOS DND CLI tool |
| [macOS DND via defaults](https://developer.apple.com/documentation/foundation/preferences) | :books: Apple preferences documentation |
| [GNOME notifications](https://developer.gnome.org/notification-spec/) | :books: GNOME notification spec |
| [Hyprland Wiki](https://wiki.hyprland.org/) | :books: Hyprland compositor documentation |
| [Sway Wiki](https://wiki.swaywm.org/) | :books: Sway compositor documentation |
| [Hyprland GitHub](https://github.com/hyprwm/Hyprland) | :books: Hyprland repository |
| [Sway GitHub](https://github.com/swaywm/sway) | :books: Sway repository |
| [XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/portal-docs.html) | :books: Cross-desktop API |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: ccbell main flow |
| [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91) | :books: Platform detection patterns |
