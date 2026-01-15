---
name: Visual Notifications
description: Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger
---

# Feature: Visual Notifications

Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger. Users who are deaf or hard of hearing, or work in noisy environments, benefit from visual alerts.

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

Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger. Supports accessibility and noise-restricted environments.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Supports users with hearing differences |
| :memo: Use Cases | Libraries, meetings, shared spaces |
| :dart: Value Proposition | Multi-modal feedback, screen periphery awareness |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🔴 High | |
| :construction: Complexity | 🟢 Low | |
| :warning: Risk Level | 🟢 Low | |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `visual` command with configure, test options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for notification execution |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay (macOS) | macOS native audio player |
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
| :computer: Platform Support | macOS (osascript/terminal-notifier), Linux (notify-send) |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

| Dependency | Platform | Purpose | Required |
|------------|----------|---------|----------|
| osascript/terminal-notifier | macOS | macOS Notification Center | ✅ |
| notify-send (libnotify) | Linux | Linux notifications | ✅ |
| beeep (Go library) | Cross-platform | Cross-platform notification library (macOS, Linux) | ➖ |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ⚠️  | External dependencies required (osascript, notify-send) |
| ✅ | Cross-platform compatible |

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:configure visual`, `/ccbell:test --visual stop` |
| :wrench: Configuration | Adds `visual` section with mode (audio-only/visual-only/both) |
| :gear: Default Behavior | Sends visual notification alongside audio |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `visual.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `visual` section |
| `audio/player.go` | :speaker: Visual notifier alongside audio |
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

1. Add visual section to config structure
2. Create internal/visual/visual.go
3. Implement VisualNotifier interface for each platform
4. Add Send() method with urgency support
5. Add visual command with configure/test options
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| osascript | macOS | Native AppleScript display notification | `✅` |
| terminal-notifier | macOS | Advanced macOS notifications with actions | ❌ |
| notify-send | Linux | Linux desktop notifications (libnotify) | `✅` |
| dunstify | Linux | Enhanced notifications for Dunst | ❌ |
| beeep | Go | Cross-platform Go notification library (macOS, Linux) | ❌ |
| gorush | 1.10.0+ | Push notification server (APNs, FCM) | ❌ |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New visual command can be added.

### Claude Code Hooks

No new hooks needed - visual notifications integrated into main flow.

### Audio Playback

Visual notifications work alongside or instead of audio.

### GoPush - Push Notification Server

**gorush** is a Go push notification server that supports multiple platforms:

- **URL**: https://github.com/appleboy/gorush
- **Install**: `go install github.com/appleboy/gorush@latest`
- **Features**:
  - Apple Push Notification service (APNs)
  - Firebase Cloud Messaging (FCM)
  - Simple HTTP API for sending notifications
  - YAML/JSON configuration
  - Metrics and logging
- **Use Case**: Send notifications to mobile devices when Claude Code events trigger

```go
// gorush API call example
func SendPushNotification(message, title string) error {
    payload := map[string]interface{}{
        "notifications": []map[string]interface{}{
            {
                "tokens":   []string{"device_token"},
                "platform": 1, // 1=iOS, 2=Android
                "message":  message,
                "title":    title,
            },
        },
    }
    // POST to gorush HTTP API
    return nil
}
```

### Visual Notification Tool Options Research

#### macOS Notification Options

**1. osascript (Native AppleScript)**
- **Command**: `osascript -e 'display notification "message" with title "ccbell"'`
- **Features**:
  - Native to macOS, no external dependencies
  - Supports title, subtitle, sound name
  - Works on macOS 10.10+
- **Limitations**: Basic styling, no action buttons

**2. terminal-notifier (Recommended for Advanced Features)**
- **URL**: https://github.com/julienXX/terminal-notifier
- **Install**: `brew install terminal-notifier`
- **Features**:
  - Rich notifications with custom icons
  - Sender application control
  - Message ID for replacement
  - Action buttons support
- **Command**: `terminal-notifier -message "Claude finished" -title "ccbell"`

#### Linux Notification Options

**1. notify-send (libnotify) - Standard**
- **Command**: `notify-send "title" "message"`
- **Features**:
  - Part of libnotify library
  - Urgency levels: low, normal, critical
  - Expire time control
  - Category hints
- **Urgency Levels**:
  - `low`: Subtle notifications
  - `normal`: Standard notifications
  - `critical`: Persistent until dismissed

**2. dunstify (Enhanced)**
- **URL**: https://github.com/dunst-project/dunst
- **Features**:
  - Drop-in replacement for notify-send
  - Supports all notify-send options
  - Custom icons and app name
  - Notification ID for updates
  - Used with Dunst notification daemon

**3. Notification Daemon Options**
| Daemon | Description | Best For |
|--------|-------------|----------|
| **Dunst** | Lightweight, highly configurable | Tiling WMs, minimal setups |
| **Mutter** | GNOME Shell default | GNOME users |
| **Plasma** | KDE default | KDE users |
| **xfce4-notifyd** | Xfce default | Xfce users |

#### Cross-Platform Go Libraries

**1. beeep (Recommended)**
- **URL**: https://github.com/gen2brain/beeep
- **Install**: `go get -u github.com/gen2brain/beeep`
- **Features**:
  - Cross-platform (macOS, Linux)
  - Simple API
  - Beep function included
  - No external dependencies on macOS/Linux
- **Example**:
```go
beeep.Notify("ccbell", "Claude finished", "icon.png")
```

**2. go-toast**
- **URL**: https://github.com/electricbubble/go-toast
- **Features**:
  - Cross-platform notifications (macOS, Linux)
  - App icon support

### Notification Styling Options

#### Message Customization

| Platform | Title | Message | Icon | Sound |
|----------|-------|---------|------|-------|
| macOS (osascript) | Yes | Yes | Yes (via terminal-notifier) | Yes |
| Linux (notify-send) | Yes | Yes | Yes | No |
| beeep | Yes | Yes | Yes | No |

#### Urgency Levels (Linux)

Per Desktop Notifications Specification:

| Level | Behavior | Use Case |
|-------|----------|----------|
| **Low** | Short display, subtle | Background events |
| **Normal** | Standard duration | Regular notifications |
| **Critical** | Persistent until dismissed | Important alerts |

#### Icons and Images

| Platform | Support | Format |
|----------|---------|--------|
| macOS | Yes (PNG, ICNS) | `.icns`, `.png` |
| Linux | Yes (PNG, SVG) | Via file path or theme icon |

#### Terminal Bell Alternative

For users in terminal-focused environments:

| Feature | Description |
|---------|-------------|
| **ANSI BEL Character** | ASCII 07, `\a` - triggers terminal bell |
| **Visual Bell** | Terminal setting to flash instead of beep |
| **X11 Bell** | `xset b` or `xbell` command |

ANSI escape codes for terminal:
```bash
# Bell character (Ctrl+G)
echo -e "\a"

# Visual bell (if supported)
echo -e "\033[?5h\033[?5l"
```

### Visual Notification Features Summary

- **Mode Selection**: audio-only, visual-only, or both
- **Per-Event Customization**: Different messages per event type
- **Urgency Control**: Adjust notification persistence based on event importance
- **Icon Support**: Custom icons for different event types
- **Platform Detection**: Auto-detect available notification system
- **Fallback**: Graceful degradation when notifications unavailable
- **Terminal Bell**: Alternative for terminal-only environments

## Research Sources

| Source | Description |
|--------|-------------|
| [terminal-notifier - GitHub](https://github.com/julienXX/terminal-notifier) | :books: macOS command-line notification tool |
| [notify-send man page](https://man7.org/linux/man-pages/man1/notify-send.1.html) | :books: Linux notify-send documentation |
| [Desktop Notifications Specification](https://specifications.freedesktop.org/notification/1.2/urgency-levels.html) | :books: Urgency levels specification |
| [Dunst - GitHub](https://github.com/dunst-project/dunst) | :books: Lightweight notification daemon |
| [Dunst - ArchWiki](https://wiki.archlinux.org/title/Dunst) | :books: Dunst configuration guide |
| [beeep - Go Packages](https://pkg.go.dev/github.com/gen2brain/beeep) | :books: Cross-platform Go notification library |
| [gorush - GitHub](https://github.com/appleboy/gorush) | :books: Push notification server (APNs, FCM) |
| [ANSI Escape Codes - GitHub Gist](https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797) | :books: ANSI escape codes reference |
| [Terminal Notifications from Scripts](https://swissmacuser.ch/native-macos-notifications-from-terminal-scripts/) | :books: macOS terminal notifications guide |
| [Linux Desktop Notifications](https://opensource.com/article/22/1/linux-desktop-notifications) | :books: Linux notifications tutorial |
| [A Comprehensive Guide to Notification Design](https://www.toptal.com/designers/ux/notification-design) | :books: Notification UX design guide |
| [Current ccbell audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
