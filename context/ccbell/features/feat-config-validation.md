---
name: Config Validation
description: Check config file for JSON syntax errors and schema issues before applying changes
---

# Feature: Config Validation

Check config file for JSON syntax errors and schema issues before applying changes.

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

Check config file for JSON syntax errors and schema issues before applying changes. Provides clear error messages to help users fix configuration issues quickly.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Clear error messages pinpoint exactly what's wrong |
| :memo: Use Cases | Debugging config issues, validating before applying |
| :dart: Value Proposition | Prevention over recovery - catches errors before notification failures |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[Medium]` |
| :construction: Complexity | `[Low]` |
| :warning: Risk Level | `[Low]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | Enhanced `validate` command with file argument and flags |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for config validation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected by this feature |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go's standard `encoding/json`.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:validate` or `/ccbell:validate config.json` |
| :wrench: Configuration | No config changes - enhances existing validation |
| :gear: Default Behavior | Validates on config save automatically |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `validate.md` with new options |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Enhance `Validate()` function |
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

1. Implement ValidateFile() function
2. Add syntax, schema, values, references validation levels
3. Add --json and --strict flags to validate command
4. Create internal/config/validator.go
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Validation command uses existing patterns.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Other Findings

Validation should support multiple levels:
- Syntax: Valid JSON checking
- Schema: Required fields validation
- Values: Valid ranges checking
- References: Profile existence checking

## Research Sources

| Source | Description |
|--------|-------------|
| [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) | :books: Current validation implementation |
| [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) | :books: Event validation |
| [Time format](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L54-L54) | :books: Time format validation |
