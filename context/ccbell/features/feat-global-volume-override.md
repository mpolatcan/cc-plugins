# Feature: Global Volume Override

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

Allow users to temporarily adjust notification volume without modifying the config file, using command-line flags.

## Motivation

- Quick volume adjustment for the current session
- Test different volume levels before committing to config
- Useful for users who want different volume per invocation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current Main Analysis

The current `cmd/ccbell/main.go` parses event type from args and reads config.

**Key Finding**: Adding CLI flags for volume override is straightforward.

### Flag Implementation

```bash
ccbell stop --volume 0.8
ccbell permission_prompt -v 0.3
ccbell subagent --vol 1.0
```

### Implementation

```go
// In main.go flag parsing
var volumeFlag *float64 = flag.Float64("volume", -1, "Override configured volume (0.0-1.0)")
var volumeShort = flag.Float64("v", -1, "Short form for --volume")

// Usage
effectiveVolume := *eventCfg.Volume
if *volumeFlag >= 0 {
    effectiveVolume = *volumeFlag
} else if *volumeShort >= 0 {
    effectiveVolume = *volumeShort
}
```

### Commands

```bash
/ccbell:test stop --volume 0.8    # Test with specific volume
/ccbell:test all -v 0.5           # Test all events at 0.5
ccbell stop --volume 1.0          # Full volume notification
```

---

## Audio Player Compatibility

Volume override uses existing volume handling:
- `afplay -v <volume>` on macOS
- `--volume=<percent>` on mpv/ffplay
- `paplay` ignores volume (system-controlled)

No changes to audio player required.

---

## Implementation

### Flag Parsing

```go
func parseVolumeFlags() *float64 {
    flagVolume := flag.Float64("volume", -1, "Override volume (0.0-1.0)")
    flagV := flag.Float64("v", -1, "Short for --volume")
    flag.Parse()

    if *flagV >= 0 && *flagV <= 1 {
        return flagV
    }
    if *flagVolume >= 0 && *flagVolume <= 1 {
        return flagVolume
    }
    return nil
}
```

### Volume Resolution

```go
func resolveVolume(configVolume, cliVolume *float64) float64 {
    if cliVolume != nil && *cliVolume >= 0 {
        return *cliVolume
    }
    if configVolume != nil {
        return *configVolume
    }
    return 0.5 // Default
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Standard Go flag parsing |

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

- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Flag parsing location
- [Config volume](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L36) - Volume in config (0.0-1.0)
- [Player volume](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L49) - Volume handling in player

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via afplay -v flag |
| Linux | ✅ Supported | Via mpv/ffplay volume args |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
