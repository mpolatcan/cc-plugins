# Feature: Sound Preview

Hear sound before confirming selection in configure.

## Summary

Preview mode during configuration that lets users hear sounds before saving their selection.

## Technical Feasibility

### Preview Command

```bash
/ccbell:test stop --preview
# Plays sound once without triggering notification logic

/ccbell:test stop --preview --loop
# Loops sound for volume testing
```

### Configure Flow

```
Select sound for 'stop':
  [1] bundled:stop [test]
  [2] custom:/path/sound.wav [test] [remove]

Select [1-2] or [t] test: t
Playing bundled:stop...
[Plays sound]

  [1] bundled:stop [test] [* selected]
  [2] custom:/path/sound.wav [test] [remove]

Select [1-2] or [d] done: d
Saved: bundled:stop
```

## Implementation

```go
func (c *CCBell) previewSound(soundRef string, loop bool) error {
    path, err := c.resolveSoundPath(soundRef)
    if err != nil {
        return err
    }

    player := c.newPlayer()
    defer player.Close()

    if loop {
        return player.PlayLoop(path)
    }
    return player.Play(path)
}
```
