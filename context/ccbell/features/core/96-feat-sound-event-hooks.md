# Feature: Sound Event Hooks

Execute custom actions on sound events.

## Summary

Run custom commands or scripts when sounds play, complete, or fail.

## Motivation

- Trigger external actions
- Integration with other tools
- Advanced automation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Hook Types

| Hook | Trigger | Example |
|------|---------|---------|
| on_play | Sound starts | Log to file |
| on_complete | Sound finishes | Update status |
| on_fail | Sound fails | Send notification |
| on_volume | Volume change | Adjust system volume |

### Configuration

```go
type SoundHook struct {
    ID          string   `json:"id"`
    Event       string   `json:"event"`       // on_play, on_complete, etc.
    Sound       string   `json:"sound"`       // specific sound or "*" for all
    Command     string   `json:"command"`     // command to execute
    Args        []string `json:"args"`        // command arguments
    Async       bool     `json:"async"`       // run async
    Env         []string `json:"env"`         // environment variables
    Enabled     bool     `json:"enabled"`
}

type HookConfig struct {
    Hooks       []*SoundHook `json:"hooks"`
    MaxParallel int          `json:"max_parallel"` // max concurrent hooks
    TimeoutSec  int          `json:"timeout_sec"`  // hook timeout
}
```

### Commands

```bash
/ccbell:hook list                 # List hooks
/ccbell:hook add on-play-log      # Add hook
/ccbell:hook add on-complete-notify --command notify-send
/ccbell:hook enable <id>          # Enable hook
/ccbell:hook disable <id>         # Disable hook
/ccbell:hook test <id>            # Test hook
/ccbell:hook delete <id>          # Remove hook
```

### Output

```
$ ccbell:hook list

=== Sound Event Hooks ===

[1] on_play -> log_to_file
    Event: on_play
    Sound: *
    Command: /usr/local/bin/log-sound
    Async: Yes
    Enabled: Yes
    Runs: 234 times

[2] on_complete -> notify_desktop
    Event: on_complete
    Sound: bundled:stop
    Command: notify-send "Sound played"
    Async: Yes
    Enabled: Yes
    Runs: 156 times

[3] on_fail -> alert_admin
    Event: on_fail
    Sound: *
    Command: /usr/bin/mail -s "Sound failed" admin
    Async: No
    Enabled: No
    Runs: 3 times

[Add] [Edit] [Test] [Delete]
```

---

## Audio Player Compatibility

Event hooks don't play sounds:
- Execute commands alongside playback
- No player changes required
- Async execution supported

---

## Implementation

### Hook Execution

```go
func (h *HookManager) onPlay(soundPath string) {
    hooks := h.getHooksForEvent("on_play", soundPath)

    for _, hook := range hooks {
        if hook.Async {
            go h.executeHook(hook, soundPath)
        } else {
            h.executeHook(hook, soundPath)
        }
    }
}

func (h *HookManager) executeHook(hook *SoundHook, soundPath string) error {
    if !hook.Enabled {
        return nil
    }

    ctx, cancel := context.WithTimeout(context.Background(), time.Duration(h.config.TimeoutSec)*time.Second)
    defer cancel()

    cmd := exec.CommandContext(ctx, hook.Command, hook.Args...)
    cmd.Env = append(os.Environ(), hook.Env...)

    // Add sound info to environment
    cmd.Env = append(cmd.Env,
        fmt.Sprintf("CCBELL_SOUND_PATH=%s", soundPath),
        fmt.Sprintf("CCBELL_SOUND_NAME=%s", filepath.Base(soundPath)),
        fmt.Sprintf("CCBELL_EVENT_TYPE=%s", hook.Event),
    )

    return cmd.Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Go standard library (os/exec) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback hook points
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
