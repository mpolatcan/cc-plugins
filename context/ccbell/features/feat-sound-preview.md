# Feature: Sound Preview 👂

## Summary

Preview mode during configuration that lets users hear sounds before saving their selection.

## Benefit

- **Informed decisions**: Hear before you choose, no more config guessing
- **Easier comparison**: A/B test sounds side by side
- **No configuration commits**: Preview without saving to config
- **Faster setup**: Find the perfect sound faster with instant feedback

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Audio |

## Technical Feasibility

### Configuration

No config changes required - CLI flag based.

### Implementation

```go
type LoopMode int

const (
    NoLoop LoopMode = iota
    InfiniteLoop
)

func (p *Player) Play(sound string, volume float64, loopMode ...LoopMode) error {
    loop := NoLoop
    if len(loopMode) > 0 {
        loop = loopMode[0]
    }

    args := p.getBaseArgs(sound, volume)
    switch loop {
    case InfiniteLoop:
        switch p.playerType {
        case "ffplay":
            args = append([]string{"-loop", "-1"}, args...)
        case "mpv":
            args = append([]string{"--loop=inf"}, args...)
        }
    }

    cmd := exec.Command(p.command, args...)
    return cmd.Run()
}
```

### Commands

```bash
/ccbell:test stop --preview              # Preview sound once
/ccbell:test stop --preview --loop       # Loop preview for volume testing
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Commands** | Modify | Add `--preview` and `--loop` flags to `test` command |
| **Core Logic** | Modify | Add preview mode to `Player.Play()` with loop control |
| **Player** | Modify | Extend to support infinite loop for preview |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add preview capability |
| **commands/test.md** | Update | Add --preview flag documentation |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [ffplay loop option](https://ffmpeg.org/ffplay.html)

---

[Back to Feature Index](index.md)
