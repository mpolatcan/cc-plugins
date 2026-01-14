# Feature: Dry Run Mode

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Run ccbell in dry run mode to validate configuration and logic without actually playing sounds. Useful for debugging and testing.

## Motivation

- Test if events are triggering correctly
- Debug quiet hours and cooldown logic
- Verify configuration is valid
- Integration testing without noise

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---


## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Technical Feasibility

### Current Architecture Analysis

The current `cmd/ccbell/main.go`:
1. Loads config
2. Checks conditions
3. Calls `player.Play()`

**Key Finding**: Adding a dry run mode is a simple early return before playback.

### Implementation

```go
func main() {
    dryRun := flag.Bool("dry-run", false, "Test without playing sounds")

    // ... existing logic ...

    if *dryRun {
        log.Info("DRY RUN: Would play %s at volume %.2f", soundPath, volume)
        log.Info("DRY RUN: Event %s enabled=%v, cooldown=%d", eventType, *eventCfg.Enabled, *eventCfg.Cooldown)
        return nil
    }

    return player.Play(soundPath, volume)
}
```

### Output Example

```
$ ccbell stop --dry-run
DRY RUN: Event 'stop' triggered
DRY RUN: Sound: ~/.claude/ccbell/sounds/stop.aiff
DRY RUN: Volume: 0.50
DRY RUN: Quiet hours: not in effect (22:00-07:00, now=14:30)
DRY RUN: Cooldown: 0s remaining
DRY RUN: Would play sound
```

### Commands

```bash
/ccbell:test stop --dry-run    # Test without playing
/ccbell:test all --dry-run     # Test all events
ccbell stop --dry-run          # Direct invocation
```

---

## Audio Player Compatibility

Dry run mode doesn't interact with audio players:
- Skips `player.Play()` call entirely
- No changes to player code required
- Purely logical operation

---

## Implementation

### Flag Addition

```go
var dryRun = flag.Bool("dry-run", false, "Validate config without playing sounds")
var dryRunShort = flag.Bool("d", false, "Short form for --dry-run")

// In main logic
if *dryRun || *dryRunShort {
    logDryRun(eventType, eventCfg, soundPath, volume, state)
    return nil
}
```

### Logging Function

```go
func logDryRun(eventType string, eventCfg *config.Event, soundPath string, volume float64, state *state.State) {
    log.Printf("=== ccbell DRY RUN ===")
    log.Printf("Event: %s", eventType)
    log.Printf("Enabled: %v", *eventCfg.Enabled)
    log.Printf("Sound: %s", soundPath)
    log.Printf("Volume: %.2f", volume)
    log.Printf("Quiet hours: %s", getQuietHoursStatus())
    log.Printf("Cooldown: %ds remaining", state.GetCooldownRemaining(eventType))
    log.Printf("Would play sound: %s", soundPath)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---


---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### ccbell Implementation Research

- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Main entry point
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - Config validation occurs
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Cooldown checking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Logic only, no audio |
| Linux | ✅ Supported | Logic only, no audio |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
