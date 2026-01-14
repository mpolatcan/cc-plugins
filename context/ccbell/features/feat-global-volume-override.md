# Feature: Global Volume Override 🔊

## Summary

Temporarily adjust notification volume without modifying the config file, using command-line flags.

## Benefit

- **No permanent commitment**: Test volume without modifying config
- **Session-based control**: Different volumes per work session
- **Faster iteration**: Quickly find right volume through trial
- **Convenient one-liners**: Easy to use in scripts

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Audio |

## Technical Feasibility

### Usage

```bash
ccbell stop --volume 0.8
ccbell permission_prompt -v 0.3
/ccbell:test stop --volume 0.8
```

### Implementation

```go
func main() {
    volumeOverride := flag.Float64("volume", 0.0, "Override volume (0.0-1.0)")
    flag.Parse()

    cfg := config.Load(homeDir)
    eventType := os.Args[len(os.Args)-1]
    eventCfg := cfg.GetEventConfig(eventType)

    volume := *eventCfg.Volume
    if *volumeOverride > 0 {
        volume = *volumeOverride
    }

    player := audio.NewPlayer()
    player.Play(eventCfg.Sound, volume)
}
```

## Configuration

No config changes - CLI flag only.

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Main Flow** | Add | `-v/--volume` flag |
| **Player** | Modify | Accept volume override |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/test.md** | Update | Add volume flag docs |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [Config volume](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L36)
- [Player volume](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L49)

---

[Back to Feature Index](index.md)
