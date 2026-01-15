---
name: Sound Randomization
description: Allow users to define multiple sounds that are randomly selected when an event triggers
---

# Feature: Sound Randomization

Instead of a single sound per event, allow users to define multiple sounds that are randomly selected when an event triggers. This adds variety and helps users recognize different events.

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

Instead of a single sound per event, allow users to define multiple sounds that are randomly selected when an event triggers. Adds variety and helps users recognize different events.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Fresh sounds keep notifications feeling new |
| :memo: Use Cases | Customizable variety, better recognition |
| :dart: Value Proposition | More engaging experience, less repetitive |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[Low]` |
| :construction: Complexity | `[Low]` |
| :warning: Risk Level | `[Low]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | Enhanced `configure` command with randomization options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for sound selection |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Randomly selected sound passed to afplay |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users configure sounds array in config, run `/ccbell:test stop --random` |
| :wrench: Configuration | Changes `Sound` (string) to `Sounds` ([]string), adds `Weights` ([]float64) |
| :gear: Default Behavior | Random selection from configured sounds with optional weights |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `configure.md` with randomization |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Change Sound to Sounds, add Weights |
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

1. Change Sound (string) to Sounds ([]string) in Event struct
2. Add Weights ([]float64) for weighted random selection
3. Implement SelectRandomSound() function
4. Handle backward compatibility with single sound
5. Add --random flag to test command
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Randomization can be integrated into configure command.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Random sound selected before passing to audio player.

### Random Selection Algorithms

#### Weighted Random Selection

Go's `math/rand` package provides standard random number generation:

```go
import "math/rand"

// Simple random selection
func SelectRandom(sounds []string) string {
    return sounds[rand.Intn(len(sounds))]
}

// Weighted random selection
type WeightedSound struct {
    Sound  string
    Weight float64
}

func SelectWeighted(sounds []WeightedSound) string {
    total := 0.0
    for _, s := range sounds {
        total += s.Weight
    }
    r := rand.Float64() * total
    for _, s := range sounds {
        if r < s.Weight {
            return s.Sound
        }
        r -= s.Weight
    }
    return sounds[len(sounds)-1].Sound
}
```

#### Cryptographically Secure Random (Optional)

For security-sensitive applications:

```go
import "crypto/rand"

// Cryptographically secure random selection
func SelectSecure(sounds []string) string {
    randBytes := make([]byte, 1)
    crypto rand.Read(randBytes)
    idx := int(randBytes[0]) % len(sounds)
    return sounds[idx]
}
```

### Randomization Features

- Multiple sounds per event with equal probability
- Optional weights for controlled probability distribution
- Seed support for reproducible testing
- Cryptographically secure option (if needed)
- Backward compatibility with single sound configuration
- --random flag for testing random selection

### Best Practices

- Provide UI preview of weighted distribution
- Support "recently played" exclusion to prevent repetition
- Allow seed configuration for consistent testing
- Cache random selection for burst notifications

## Research Sources

| Source | Description |
|--------|-------------|
| [Go math/rand](https://pkg.go.dev/math/rand) | :books: Standard random number generation |
| [Go crypto/rand](https://pkg.go.dev/crypto/rand) | :books: Cryptographically secure random |
| [Current config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config structure |
| [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config loading |
