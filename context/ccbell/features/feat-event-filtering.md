---
name: Event Filtering
description: Only trigger notifications when specific conditions are met
---

# Feature: Event Filtering

Only trigger notifications when specific conditions are met (e.g., "only notify on long responses" or "notify on errors").

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

Only trigger notifications when specific conditions are met. Allows token count, pattern matching, and duration filters for context-aware notifications.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Reduced distraction - only important events trigger notifications |
| :memo: Use Cases | Personalized workflow, context-aware behavior |
| :dart: Value Proposition | Different rules for different work types |

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
| :keyboard: Commands | No new commands - config-based filtering |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Bash, Read tools for filter execution |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - playback skipped if filter fails |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

Uses Go's `regexp` package for pattern matching.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users configure filters in config file |
| :wrench: Configuration | Adds `filters` section to each event |
| :gear: Default Behavior | Filters checked before notification triggers |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `configure.md` with filter docs |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `filters` section to Event |
| `audio/player.go` | :speaker: Check filters before playback |
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

1. Add filters section to Event config structure
2. Create internal/filter/filter.go
3. Implement ShouldNotify() function with token_count, pattern, duration filters
4. Modify main flow to check filters before playing
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | regexp | Pattern matching | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports hooks. Filter check can be integrated into main flow.

### Claude Code Hooks

No new hooks needed - filter check before existing hooks.

### Audio Playback

Playback is skipped when filter conditions are not met.

### Filter Implementation Patterns

#### Go regexp Optimization
- Compile regex patterns once at startup
- Use `regexp.MustCompile()` for static patterns
- Cache compiled patterns for dynamic filters

```go
var patternCache = sync.Map{}

func GetCompiledPattern(pattern string) *regexp.Regexp {
    if cached, ok := patternCache.Load(pattern); ok {
        return cached.(*regexp.Regexp)
    }
    compiled := regexp.MustCompile(pattern)
    patternCache.Store(pattern, compiled)
    return compiled
}
```

#### Token Count Filter
```go
type TokenCountFilter struct {
    Min int `json:"min"`
    Max int `json:"max"`
}

func (f TokenCountFilter) ShouldNotify(event EventData) bool {
    count := event.TokenCount
    if f.Min > 0 && count < f.Min {
        return false
    }
    if f.Max > 0 && count > f.Max {
        return false
    }
    return true
}
```

#### Duration Filter
```go
type DurationFilter struct {
    Min string `json:"min"` // e.g., "5s"
    Max string `json:"max"` // e.g., "5m"
}

func (f DurationFilter) ShouldNotify(event EventData) bool {
    minDuration, _ := time.ParseDuration(f.Min)
    maxDuration, _ := time.ParseDuration(f.Max)

    if minDuration > 0 && event.Duration < minDuration {
        return false
    }
    if maxDuration > 0 && event.Duration > maxDuration {
        return false
    }
    return true
}
```

#### Custom Expression Filter (CEL)
- **URL**: https://github.com/google/cel-go
- **Purpose**: Safe expression evaluation
- **Use Case**: Complex multi-condition filters
- **Benefits**: Type-safe, sandboxed, extensible

### Filter Types Supported

- **token_count**: Min/max tokens in response
- **pattern**: Regex match on message content
- **duration**: Min/max response duration
- **keywords**: Contains/exclude keywords
- **event_type**: Match specific event subtypes
- **time_range**: Only notify during specific hours
- **custom**: CEL expression for complex logic

### Filter Combination Logic

- **AND**: All filters must pass
- **OR**: Any filter can pass
- **Priority**: Filters applied in order
- **Short-circuit**: Stop on first failure

## Research Sources

| Source | Description |
|--------|-------------|
| [Go regexp package](https://pkg.go.dev/regexp) | :books: Pattern matching |
| [CEL - Common Expression Language](https://github.com/google/cel-go) | :books: Safe expression evaluation |
| [Go time package](https://pkg.go.dev/time) | :books: Duration parsing |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main flow |
| [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) | :books: Event structure |
