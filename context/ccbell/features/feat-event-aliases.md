---
name: Event Aliases
description: Define custom event names that map to existing events for flexibility
---

# Feature: Event Aliases

Define custom event names that map to existing events for flexibility.

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

Define custom event names that map to existing events for flexibility. Allows users to use personalized terminology matching their mental model.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Use terminology matching your mental model |
| :memo: Use Cases | Personalized workflow, team standardization |
| :dart: Value Proposition | Shorter aliases reduce typing, easier onboarding |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `🟢` |
| :construction: Complexity | `🟢` |
| :warning: Risk Level | `🟢` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `alias` command with list/add/remove options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for config manipulation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected by this feature |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:alias` commands to manage aliases |
| :wrench: Configuration | Adds `aliases` section to config |
| :gear: Default Behavior | Aliases resolved before event matching |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `alias.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `aliases` section |
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

1. Add aliases section to config structure
2. Implement ResolveAlias() function
3. Create alias command with list/add/remove options
4. Update version in main.go
5. Tag and release vX.X.X
6. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `➖` |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New alias command can be added.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Alias Implementation Patterns

#### Alias Resolution with Priority
```go
type Alias struct {
    Target   string  `json:"target"`   // Original event name
    Sound    string  `json:"sound,omitempty"`  // Optional sound override
    Enabled  bool    `json:"enabled"`
    Priority int     `json:"priority"`  // Higher = more specific
}

var aliases = map[string]Alias{
    "done":      {Target: "stop", Priority: 1},
    "finished":  {Target: "stop", Priority: 1},
    "complete":  {Target: "stop", Priority: 1},
    "ask":       {Target: "permission", Priority: 1},
    "waiting":   {Target: "idle", Priority: 1},
    "agent":     {Target: "subagent", Priority: 1},
}

func ResolveEvent(input string) (string, Alias) {
    if alias, ok := aliases[input]; ok {
        return alias.Target, alias
    }
    return input, Alias{Enabled: true}
}
```

#### Alias Expansion in Config
```go
func ExpandConfig(config Config) Config {
    expanded := config

    for i, event := range expanded.Events {
        if alias, ok := aliases[event.Name]; ok {
            expanded.Events[i].Name = alias.Target
            if alias.Sound != "" && event.Sound == "" {
                expanded.Events[i].Sound = alias.Sound
            }
        }
    }

    return expanded
}
```

#### Alias Validation
```go
func ValidateAlias(name, target string) error {
    // Check alias doesn't conflict with real events
    if IsValidEvent(target) && !IsAlias(name) {
        return fmt.Errorf("'%s' is a real event, cannot be an alias", target)
    }

    // Check target exists
    if !IsValidEvent(target) && !IsAlias(target) {
        return fmt.Errorf("target '%s' does not exist", target)
    }

    return nil
}
```

### Alias Configuration Examples

```json
{
  "aliases": {
    "done": {
      "target": "stop",
      "enabled": true,
      "priority": 1
    },
    "finished": {
      "target": "stop",
      "enabled": true,
      "priority": 1
    },
    "ask": {
      "target": "permission",
      "enabled": true,
      "priority": 1
    }
  }
}
```

### Alias Features

- **Target event mapping** (alias → real event)
- **Enabled/disabled state** per alias
- **Optional sound override** per alias
- **Priority system** for conflicting aliases
- **Validation** to prevent conflicts
- **Expansion** in config loading

## Research Sources

| Source | Description |
|--------|-------------|
| [Go map](https://pkg.go.dev/map) | :books: Map data structure |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Current config structure |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main flow |
