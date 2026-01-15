---
name: Export/Import Config
description: Export current ccbell configuration to a portable JSON file and import from files or URLs
---

# Feature: Export/Import Config

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs.

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

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs. Enables team collaboration and easy backup.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Team collaboration, easy backup protection |
| :memo: Use Cases | Standardizing notification setups across team members |
| :dart: Value Proposition | New members get productive instantly |

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
| :keyboard: Commands | New `config` command with export/import options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for file operations |

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
| :hand: User Interaction | Users run `/ccbell:config export` or `/ccbell:config import` |
| :wrench: Configuration | No schema change - pure JSON serialization |
| :gear: Default Behavior | Supports merge or replace on import |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `config.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add Export(), Import(), Merge() methods |
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

1. Implement Export() method for config
2. Implement Import() method with merge option
3. Create internal/config/export.go
4. Add config command with export/import options
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

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

Plugin manifest supports commands. Config export/import command can be added.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Export/Import Implementation

#### Export with Redaction
```go
func ExportConfig(config Config, redactSecrets bool) ([]byte, error) {
    export := ConfigExport{
        Version:   config.Version,
        Events:    config.Events,
        Profiles:  config.Profiles,
        QuietHours: config.QuietHours,
        Created:   time.Now().UTC(),
    }

    if redactSecrets && config.Webhooks != nil {
        export.Webhooks = redactWebhooks(config.Webhooks)
    }

    return json.MarshalIndent(export, "", "  ")
}

func redactWebhooks(webhooks []Webhook) []Webhook {
    redacted := make([]Webhook, len(webhooks))
    for i, wh := range webhooks {
        redacted[i] = wh
        redacted[i].Headers = nil // Remove auth headers
        if strings.Contains(redacted[i].URL, "token=") {
            redacted[i].URL = strings.ReplaceAll(redacted[i].URL, "token=xxx", "token=[REDACTED]")
        }
    }
    return redacted
}
```

#### Import with Merge Strategy
```go
type MergeStrategy string

const (
    MergeStrategyReplace MergeStrategy = "replace"
    MergeStrategyMerge   MergeStrategy = "merge"
    MergeStrategySkip    MergeStrategy = "skip"
)

func ImportConfig(path string, strategy MergeStrategy, validate bool) (Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return Config{}, err
    }

    var imported Config
    if err := json.Unmarshal(data, &imported); err != nil {
        return Config{}, fmt.Errorf("invalid JSON: %w", err)
    }

    if validate {
        if err := ValidateConfig(imported); err != nil {
            return Config{}, fmt.Errorf("validation failed: %w", err)
        }
    }

    current, err := LoadConfig(GetDefaultPath())
    if err != nil && !os.IsNotExist(err) {
        return Config{}, err
    }

    switch strategy {
    case MergeStrategyReplace:
        return imported, nil
    case MergeStrategyMerge:
        return MergeConfigs(current, imported), nil
    case MergeStrategySkip:
        return current, nil
    }

    return current, nil
}
```

#### Import from URL
```go
func ImportFromURL(url string, strategy MergeStrategy) (Config, error) {
    resp, err := http.Get(url)
    if err != nil {
        return Config{}, err
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return Config{}, fmt.Errorf("HTTP %d", resp.StatusCode)
    }

    var imported Config
    decoder := json.NewDecoder(resp.Body)
    if err := decoder.Decode(&imported); err != nil {
        return Config{}, err
    }

    // Process same as file import
    return ImportConfigParsed(imported, strategy)
}
```

### Export/Import Features

- **Export to file** with optional secrets exclusion
- **Import from file or URL** (HTTP/HTTPS/GitHub raw)
- **Merge or replace** on import
- **Validation before import** (optional)
- **Version tracking** in exported files
- **Dry-run import** to preview changes

## Research Sources

| Source | Description |
|--------|-------------|
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config loading |
| [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Validation |
| [JSON marshaling](https://pkg.go.dev/encoding/json) | :books: JSON handling |
| [Go HTTP client](https://pkg.go.dev/net/http) | :books: HTTP fetching |
