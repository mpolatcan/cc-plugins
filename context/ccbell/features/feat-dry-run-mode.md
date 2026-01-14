# Feature: Dry Run Mode 🧪

## Summary

Run ccbell in dry run mode to validate configuration and logic without playing sounds. Useful for debugging and testing.

## Benefit

- **Noise-free testing**: Test in offices, libraries, or meetings
- **Faster debugging**: Clear output shows what would happen
- **Safer experimentation**: Try configs without disruptive sounds
- **CI/CD integration**: Automated tests in build pipelines

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Category** | Testing |

## Technical Feasibility

### Output Example

```
$ ccbell stop --dry-run
=== Dry Run Mode ===
Event: stop
Sound: ~/.claude/ccbell/sounds/stop.aiff
Volume: 0.50
Would skip: In cooldown
Would skip: Quiet hours active
Dry run complete - no sound played
```

### Implementation

```go
func main() {
    dryRun := flag.Bool("dry-run", false, "Test without playing sounds")

    cfg := config.Load(homeDir)
    state := state.Load(homeDir)

    if *dryRun {
        fmt.Println("=== Dry Run Mode ===")
        fmt.Printf("Event: %s\n", eventType)
        fmt.Printf("Sound: %s\n", cfg.Events[eventType].Sound)
        fmt.Printf("Volume: %.2f\n", *cfg.Events[eventType].Volume)
        return
    }
    player.Play(sound, volume)
}
```

### Commands

```bash
/ccbell:test stop --dry-run    # Test without playing
/ccbell:test all --dry-run     # Test all events
```

## Configuration

No config changes - CLI flag only.

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Main Flow** | Add | `--dry-run` flag, skip playback |
| **Commands** | Modify | Enhance `test` command |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/test.md** | Update | Add --dry-run docs |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102)
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)

---

[Back to Feature Index](index.md)
