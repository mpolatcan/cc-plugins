# Feature: Sound Event Hook

Custom hook integration.

## Summary

Execute custom scripts or commands on sound events.

## Motivation

- Automation
- Integration with other tools
- Custom workflows

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

| Type | Description | Example |
|-------|-------------|---------|
| Pre-play | Before sound plays | Log to system |
| Post-play | After sound plays | Trigger another action |
| On-error | When error occurs | Send notification |
| On-skip | When event is skipped | Log reason |

### Configuration

```go
type HookConfig struct {
    Enabled       bool              `json:"enabled"`
    Hooks         map[string]*Hook  `json:"hooks"`
    TimeoutSec    int               `json:"timeout_sec"` // 30 default
}

type Hook struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    EventType   string   `json:"event_type"` // "*" for all
    Trigger     string   `json:"trigger"` // "pre", "post", "error", "skip"
    Command     string   `json:"command"` // Shell command
    Args        []string `json:"args"`
    Environment map[string]string `json:"env,omitempty"`
    Enabled     bool     `json:"enabled"`
    ContinueOnFail bool  `json:"continue_on_fail"` // Continue even if hook fails
}

type HookContext struct {
    EventType   string
    Sound       string
    Volume      float64
    Platform    string
    Timestamp   time.Time
    Error       string `json:"error,omitempty"`
    Skipped     bool   `json:"skipped,omitempty"`
    SkipReason  string `json:"skip_reason,omitempty"`
}
```

### Commands

```bash
/ccbell:hook list                  # List hooks
/ccbell:hook create "Log Play" --event stop --trigger post --command echo
/ccbell:hook create "Notify" --event permission_prompt --command /path/to/notify.sh
/ccbell:hook enable <id>           # Enable hook
/ccbell:hook disable <id>          # Disable hook
/ccbell:hook delete <id>           # Remove hook
/ccbell:hook test <id>             # Test hook
/ccbell:hook test-all              # Test all hooks
```

### Output

```
$ ccbell:hook list

=== Sound Event Hooks ===

Status: Enabled
Timeout: 30s

Hooks: 3

[1] Log Play
    Event: stop
    Trigger: post
    Command: echo "Played: ${SOUND}"
    Status: Active
    [Edit] [Disable] [Delete]

[2] Notify Desktop
    Event: permission_prompt
    Trigger: post
    Command: osascript -e 'display notification "Done"'
    Status: Active
    [Edit] [Disable] [Delete]

[3] Error Alert
    Event: *
    Trigger: error
    Command: /path/to/alert.sh
    Status: Active
    [Edit] [Disable] [Delete]

Environment Variables:
  CCBELL_EVENT_TYPE
  CCBELL_SOUND
  CCBELL_VOLUME
  CCBELL_PLATFORM
  CCBELL_TIMESTAMP

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Hooks work with all audio players:
- External commands
- No player changes required

---

## Implementation

### Hook Manager

```go
type HookManager struct {
    config   *HookConfig
}

func (m *HookManager) Execute(trigger, eventType string, ctx *HookContext) error {
    for _, hook := range m.config.Hooks {
        if !hook.Enabled {
            continue
        }

        if !m.matchesEvent(hook, eventType) {
            continue
        }

        if hook.Trigger != trigger {
            continue
        }

        if err := m.runHook(hook, ctx); err != nil {
            if !hook.ContinueOnFail {
                return fmt.Errorf("hook %s failed: %w", hook.Name, err)
            }
        }
    }

    return nil
}

func (m *HookManager) runHook(hook *Hook, ctx *HookContext) error {
    cmd, args := m.buildCommand(hook, ctx)

    command := exec.Command(cmd, args...)
    command.Env = m.buildEnvironment(hook, ctx)
    command.Stdout = os.Stdout
    command.Stderr = os.Stderr

    // Set timeout
    done := make(chan error, 1)
    go func() {
        done <- command.Run()
    }()

    select {
    case err := <-done:
        return err
    case <-time.After(time.Duration(m.config.TimeoutSec) * time.Second):
        command.Process.Kill()
        return fmt.Errorf("hook timed out after %ds", m.config.TimeoutSec)
    }
}

func (m *HookManager) buildCommand(hook *Hook, ctx *HookContext) (string, []string) {
    // Expand variables in command
    expanded := os.Expand(hook.Command, func(key string) string {
        switch key {
        case "EVENT_TYPE": return ctx.EventType
        case "SOUND": return ctx.Sound
        case "VOLUME": return fmt.Sprintf("%.2f", ctx.Volume)
        case "PLATFORM": return ctx.Platform
        case "TIMESTAMP": return ctx.Timestamp.Format(time.RFC3339)
        case "ERROR": return ctx.Error
        default: return ""
        }
    })

    parts := strings.Fields(expanded)
    if len(parts) == 0 {
        return "", nil
    }

    return parts[0], parts[1:]
}

func (m *HookManager) buildEnvironment(hook *Hook, ctx *HookContext) []string {
    env := os.Environ()

    // Add hook-specific env
    env = append(env,
        fmt.Sprintf("CCBELL_EVENT_TYPE=%s", ctx.EventType),
        fmt.Sprintf("CCBELL_SOUND=%s", ctx.Sound),
        fmt.Sprintf("CCBELL_VOLUME=%.2f", ctx.Volume),
        fmt.Sprintf("CCBELL_PLATFORM=%s", ctx.Platform),
        fmt.Sprintf("CCBELL_TIMESTAMP=%s", ctx.Timestamp.Format(time.RFC3339)),
    )

    // Add custom env
    for k, v := range hook.Environment {
        env = append(env, fmt.Sprintf("%s=%s", k, v))
    }

    return env
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| exec | Go Stdlib | Free | Process execution |

---

## References

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Playback hooks
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event state

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
