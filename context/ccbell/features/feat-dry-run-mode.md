---
name: Dry Run Mode
description: Run ccbell in dry run mode to validate configuration and logic without playing sounds
category: core
---

# Feature: Dry Run Mode

Run ccbell in dry run mode to validate configuration and logic without playing sounds. Useful for debugging and testing.

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

Run ccbell in dry run mode to validate configuration and logic without playing sounds. Useful for debugging, testing in quiet environments, and CI/CD pipelines.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Test in offices, libraries, or meetings without noise |
| :memo: Use Cases | Debugging config, CI/CD integration, safe experimentation |
| :dart: Value Proposition | Clear output shows what would happen without playing sounds |

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
| :keyboard: Commands | Enhanced `test` command with `--dry-run` flag |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Bash, Write, Read tools for output |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Skipped in dry-run mode, prints what would play |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:test stop --dry-run` |
| :wrench: Configuration | No config changes - CLI flag only |
| :gear: Default Behavior | Normal playback unless --dry-run specified |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `test.md` with --dry-run docs |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (add --dry-run flag, skip playback) |
| `config/config.go` | :wrench: Configuration handling (no change) |
| `audio/player.go` | :speaker: Audio playback logic (add dry-run support) |
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

1. Add --dry-run flag to main command
2. Skip player.Play() when dry-run is true
3. Print event, sound, volume, and skip reasons
4. Update version in main.go
5. Tag and release vX.X.X
6. Sync version to cc-plugins

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

Plugin manifest supports commands. Dry-run flag can be added to test command.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

In dry-run mode, playback is skipped and what would have happened is printed.

### Dry Run Output Patterns

#### Structured Output (Recommended)
```go
type DryRunResult struct {
    Event      string    `json:"event"`
    Sound      string    `json:"sound"`
    Volume     float64   `json:"volume"`
    Profile    string    `json:"profile,omitempty"`
    SkipReason string    `json:"skip_reason,omitempty"`
    Timestamp  time.Time `json:"timestamp"`
}

func PrintDryRun(result DryRunResult, format string) {
    switch format {
    case "json":
        printJSON(result)
    case "text":
        printText(result)
    case "verbose":
        printVerbose(result)
    }
}
```

#### Verbose Output
```
[DRY-RUN] Event: stop
[DRY-RUN] Sound: bundled:stop.aiff
[DRY-RUN] Volume: 0.75
[DRY-RUN] Profile: default
[DRY-RUN] Would play: afplay --volume 0.75 /path/to/sounds/stop.aiff
[DRY-RUN] Status: SKIPPED (cooldown active: 23s remaining)
```

#### CI/CD Integration
```bash
# Exit code 0 = success, 1 = error
ccbell test stop --dry-run --json > /tmp/dry-run.json
jq '.event, .sound, .skip_reason' /tmp/dry-run.json
```

#### GitHub Actions Integration
```yaml
- name: Test ccbell configuration
  run: |
    ccbell test stop --dry-run --json | tee dry-run.json
    # Validate expected sound is selected
    jq -e '.sound == "bundled:stop.aiff"' dry-run.json
```

#### Automated Config Testing
```bash
# Test all events in sequence
for event in stop permission idle; do
    echo "Testing $event..."
    ccbell test $event --dry-run --json | \
        jq "{event: .event, sound: .sound, status: .skip_reason}"
done
```

### Dry Run Use Cases

- **Office/Library Testing**: Validate without disturbing others
- **CI/CD Pipelines**: Automated config testing
- **Debugging**: Isolate config issues from audio issues
- **Documentation**: Generate example outputs

### Dry Run Features

- Event type and sound path display
- Volume level output
- Skip reasons (cooldown, quiet hours, DND)
- Structured output (JSON, text, verbose)
- Command that would be executed
- Exit code for automation

## Research Sources

| Source | Description |
|--------|-------------|
| [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main entry point |
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) | :books: Config loading |
| [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: State management |
| [Go flag package](https://pkg.go.dev/flag) | :books: CLI flag parsing |
