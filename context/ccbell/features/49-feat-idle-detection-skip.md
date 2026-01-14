# Feature: Idle Detection Skip

Skip notifications when system is idle.

## Summary

Detect system idle state (no user activity) and suppress notifications accordingly.

## Motivation

- Avoid notifications when user is away
- Respect user focus time
- Prevent audio when computer is idle

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Idle Detection Methods

| Platform | Method | Native Support | Feasibility |
|----------|--------|----------------|-------------|
| macOS | `ioreg` | Yes | ✅ Easy |
| macOS | `pmset` | Yes | ✅ Easy |
| Linux | `xprintidle` | No | ⚠️ Requires install |
| Linux | `xss-query` | No | ⚠️ Requires install |
| Both | `who -s` | Yes | ✅ Easy |

### macOS Implementation

```bash
# Check display sleep (seconds)
pmset -g displaysleep

# Check if system is asleep
ioreg -r -d 4 -c IOFramebuffer | grep -q "Power" && echo "asleep" || echo "awake"

# Check idle time
ioreg -c IOHIDSystem | grep "HIDIdleTime" | awk '{print $NF/1000000000}'
```

### Linux Implementation

```bash
# Check X idle time (requires xprintidle)
xprintidle

# Check via XSS
xss-query -s
```

### Implementation

```go
func isSystemIdle(timeout time.Duration) (bool, error) {
    switch detectPlatform() {
    case PlatformMacOS:
        return checkMacOSIdle(timeout)
    case PlatformLinux:
        return checkLinuxIdle(timeout)
    }
    return false, nil
}

func checkMacOSIdle(timeout time.Duration) (bool, error) {
    cmd := exec.Command("ioreg", "-c", "IOHIDSystem", "-r", "-d", "4")
    output, err := cmd.Output()
    if err != nil {
        return false, err
    }

    // Parse HIDIdleTime (nanoseconds)
    idleNs := parseIdleTime(output)
    idleDuration := time.Duration(idleNs) * time.Nanosecond

    return idleDuration > timeout, nil
}
```

### Configuration

```json
{
  "idle_skip": {
    "enabled": true,
    "idle_timeout_seconds": 300,
    "check_interval_seconds": 30,
    "resume_after_activity": true
  }
}
```

### Commands

```bash
/ccbell:idle status               # Show idle status
/ccbell:idle set 300              # Set 5 minute timeout
/ccbell:idle test                 # Test idle detection
/ccbell:idle disable              # Disable idle skip
```

---

## Audio Player Compatibility

Idle detection runs before audio playback:
- Decides whether to play sound
- No player changes required
- Same audio player when playing

---

## Implementation

### Idle Monitor

```go
type IdleMonitor struct {
    timeout      time.Duration
    checkInterval time.Duration
    lastActivity time.Time
    running      bool
}

func (m *IdleMonitor) Start() {
    m.running = true
    go m.checkLoop()
}

func (m *IdleMonitor) IsIdle() (bool, error) {
    return isSystemIdle(m.timeout)
}
```

### Integration

```go
// In main.go
if cfg.IdleSkip != nil && cfg.IdleSkip.Enabled {
    idle, err := idleMonitor.IsIdle()
    if err != nil {
        log.Warn("Idle detection failed: %v", err)
    } else if idle {
        log.Debug("Skipping notification - system is idle")
        return nil
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ioreg | Native (macOS) | Free | Built-in |
| xprintidle | Optional (Linux) | Free | Package install |

---

## References

### Research Sources

- [macOS IOHIDSystem](https://developer.apple.com/library/archive/technotes/tn2007/tn2083.html)
- [X11 idle time](https://unix.stackexchange.com/questions/139533/how-to-get-idle-time-in-linux)

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For idle config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ioreg |
| Linux | ⚠️ Partial | xprintidle or xss-query |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
