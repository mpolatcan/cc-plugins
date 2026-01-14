# Feature: Sound Recovery

Recover from failed sound playback.

## Summary

Automatic recovery mechanisms for sound playback failures.

## Motivation

- Handle playback errors gracefully
- Fallback to backup sounds
- Automatic retry logic

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Recovery Strategies

| Strategy | Description | Example |
|----------|-------------|---------|
| Retry | Try again N times | Retry 3 times |
| Fallback | Use backup sound | Use bundled fallback |
| Skip | Skip this notification | Silent failure |
| Queue | Queue for later | Retry after timeout |

### Configuration

```go
type RecoveryConfig struct {
    Enabled         bool    `json:"enabled"`
    MaxRetries      int     `json:"max_retries"`
    RetryDelayMs    int     `json:"retry_delay_ms"`
    FallbackSound   string  `json:"fallback_sound"` // bundled:stop
    FallbackChain   []string `json:"fallback_chain"` // backup sounds
    OnPermanentFail string  `json:"on_permanent_fail"` // action
    LogFailures     bool    `json:"log_failures"`
}

type RecoveryState struct {
    Attempts       int       `json:"attempts"`
    LastAttempt    time.Time `json:"last_attempt"`
    LastError      string    `json:"last_error"`
    Success        bool      `json:"success"`
}
```

### Commands

```bash
/ccbell:recovery enable              # Enable recovery
/ccbell:recovery disable             # Disable recovery
/ccbell:recovery set retries 3       # 3 retry attempts
/ccbell:recovery set delay 500       # 500ms delay
/ccbell:recovery set fallback bundled:stop
/ccbell:recovery set fallback-chain bundled:stop bundled:alt
/ccbell:recovery status              # Show recovery status
/ccbell:recovery test                # Test recovery
```

### Output

```
$ ccbell:recovery status

=== Sound Recovery ===

Status: Enabled
Max Retries: 3
Retry Delay: 500ms
Fallback: bundled:stop

Fallback Chain:
  [1] bundled:stop
  [2] bundled:alt
  [3] bundled:emergency

On Permanent Fail: log_only

Statistics:
  Total Failures: 12
  Recovered: 10 (83%)
  Permanent: 2

[Configure] [Test] [Disable]
```

---

## Audio Player Compatibility

Recovery works with existing audio player:
- Wraps `player.Play()` with retry logic
- Same format support
- No player changes required

---

## Implementation

### Recovery Logic

```go
func (r *RecoveryManager) PlayWithRecovery(soundPath string, volume float64) error {
    var lastErr error

    for attempt := 1; attempt <= r.config.MaxRetries; attempt++ {
        player := audio.NewPlayer(r.pluginRoot)

        if err := player.Play(soundPath, volume); err != nil {
            lastErr = err
            r.state.Attempts = attempt
            r.state.LastAttempt = time.Now()
            r.state.LastError = err.Error()

            if r.config.LogFailures {
                log.Debug("Playback attempt %d failed: %v", attempt, err)
            }

            // Try fallback chain on subsequent attempts
            if attempt > 1 {
                fallbackIdx := attempt - 2
                if fallbackIdx < len(r.config.FallbackChain) {
                    fallbackSound := r.config.FallbackChain[fallbackIdx]
                    if path, err := r.resolveSound(fallbackSound); err == nil {
                        soundPath = path
                        log.Debug("Using fallback sound: %s", fallbackSound)
                    }
                }
            }

            // Wait before retry
            if attempt < r.config.MaxRetries {
                time.Sleep(time.Duration(r.config.RetryDelayMs) * time.Millisecond)
            }

            continue
        }

        // Success
        r.state.Success = true
        r.resetState()
        return nil
    }

    // All retries failed
    r.handlePermanentFailure(soundPath, lastErr)
    return lastErr
}
```

### Fallback Resolution

```go
func (r *RecoveryManager) resolveSound(soundSpec string) (string, error) {
    player := audio.NewPlayer(r.pluginRoot)
    return player.ResolveSoundPath(soundSpec, "")
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Recovery wrapper
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Fallback resolution

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
