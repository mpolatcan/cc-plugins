---
name: Minimal Mode
description: Simplified configuration mode with fewer options for users who want simplicity
---

# Feature: Minimal Mode

Simplified configuration mode with fewer options for users who want simplicity.

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

Simplified configuration mode with fewer options for users who want simplicity. Provides an interactive wizard for quick setup with opinionated defaults.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | New users get value immediately |
| :memo: Use Cases | Onboarding new team members, quick setup |
| :dart: Value Proposition | Reduced decision fatigue, opinionated defaults |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🟡 Medium | |
| :construction: Complexity | 🟢 Low | |
| :warning: Risk Level | 🟢 Low | |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `wizard` command for interactive setup |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash, AskUserQuestion tools |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay (macOS) | macOS native audio player | |
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:wizard` for interactive setup |
| :wrench: Configuration | Adds `mode` and `minimal` sections to config |
| :gear: Default Behavior | Simplified defaults for minimal mode |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `wizard.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `mode`, `minimal` sections |
| `audio/player.go` | :speaker: Audio playback logic (no change) |
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

1. Add mode and minimal sections to config structure
2. Implement GetMinimalConfig() function
3. Implement RunWizard() with interactive questions
4. Create internal/config/minimal.go
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ❌ |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New wizard command can be added.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Interactive CLI Design Patterns

#### Survey Library (Recommended)
- **URL**: https://github.com/AlecAivazis/survey
- **Features**:
  - Interactive prompts (confirm, select, input, multiline)
  - Validation support
  - Custom themes
  - ANSI output compatibility
- **Install**: `go get github.com/AlecAivazis/survey/v2`
- **Best For**: Rich interactive CLI experiences

#### Chewitt (Interactive Prompts)
- **URL**: https://github.com/AlecAivazis/chewitt
- **Features**:
  - Simple confirmation prompts
  - Select menus
  - Input validation
- **Best For**: Lightweight interactive prompts

#### urfave/cli (Modern CLI Framework)
- **URL**: https://cli.urfave.org/
- **Features**:
  - Declarative, simple, fast CLI building
  - Command hierarchies
  - Flag parsing
  - Auto-generated help
- **Install**: `go get github.com/urfave/cli/v3`
- **Best For**: Production CLI applications (2025+)

#### Cobra (Battle-Tested CLI)
- **URL**: https://cobra.dev/
- **Features**:
  - Most widely used Go CLI framework
  - Commands, flags, auto-help
  - Persistent flags
  - Bash/zsh completion
- **Install**: `go get github.com/spf13/cobra`
- **Best For**: Complex CLI applications with subcommands

#### Go Prompts Pattern
- Use `AskUserQuestion` for Claude Code integration
- Use standard input/output for terminal-based wizards
- Support non-interactive mode with default values

### Wizard Flow Design

1. **Welcome Screen**
   - Brief introduction to ccbell
   - Confirm starting wizard

2. **Sound Selection**
   - Select bundled sounds or custom path
   - Preview sounds before selection

3. **Event Configuration**
   - Enable/disable events (stop, permission, idle, subagent)
   - Assign sounds per event

4. **Volume Setup**
   - Test volume levels
   - Set default volume (suggested: 0.5)

5. **Quiet Hours (Optional)**
   - Configure time window
   - Set default: 22:00-07:00

6. **Summary & Apply**
   - Review configuration
   - Apply or go back to edit

### Minimal Mode Features

- Interactive wizard with guided questions
- Opinionated defaults (volume 0.5, quiet hours 22:00-07:00)
- Simplified event configuration
- Option to upgrade to full config later
- Non-interactive mode with preset configurations
- Skip option for advanced settings

## Research Sources

| Source | Description |
|--------|-------------|
| [Survey - Go Interactive Prompts](https://github.com/AlecAivazis/survey) | :books: Interactive CLI prompts library |
| [Chewitt - Simple Prompts](https://github.com/AlecAivazis/chewitt) | :books: Lightweight prompts |
| [urfave/cli](https://cli.urfave.org/) | :books: Modern CLI framework (2025) |
| [Cobra CLI Framework](https://cobra.dev/) | :books: Battle-tested CLI framework |
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) | :books: Config loading |
| [Default config](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L64-L77) | :books: Default config |
| [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) | :books: Quiet hours |
| [Interactive CLI Design](https://uxdesign.cc/interactive-cli-design-patterns-8f6a2fa7e86e) | :books: CLI UX design patterns |
