# Feature: Wake Lock / Prevent Sleep

Keep the system awake during notification playback.

## Summary

Prevent the system from going to sleep during sound playback to ensure notifications are heard.

## Motivation

- Notifications may be missed if system sleeps
- Useful for long-running Claude sessions
- Ensure audio playback completes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Platform Methods

| Platform | Method | Native Support | Feasibility |
|----------|--------|----------------|-------------|
| macOS | `caffeinate` | Yes | ✅ Easy |
| Linux (X11) | `xset s off` | Yes | ✅ Easy |
| Linux (Wayland) | `busctl` | Yes | ⚠️ Moderate |
| DBUS | `org.freedesktop.ScreenSaver` | Yes | ⚠️ Moderate |

### macOS Implementation

```bash
# Prevent sleep during command
caffeinate -i ccbell stop

# Or with timeout (30 minutes)
caffeinate -t 1800 ccbell stop
```

### Linux Implementation

```bash
# X11: Disable screensaver temporarily
xset s off && xset -dpms && sleep 5 && xset s on && xset +dpms

# Or via DBUS
dbus-send --session --type=method_call --dest=org.freedesktop.ScreenSaver \
    /ScreenSaver org.freedesktop.ScreenSaver.Inhibit \
    string:ccbell string:Playing notification
```

### Implementation

```go
type WakeLocker struct {
    acquired   bool
    inhibitor  *os.Process
}

func (w *WakeLocker) Acquire() error {
    switch detectPlatform() {
    case PlatformMacOS:
        return w.acquireMacOS()
    case PlatformLinux:
        return w.acquireLinux()
    }
    return nil
}

func (w *WakeLocker) acquireMacOS() error {
    // Start caffeinate as subprocess
    cmd := exec.Command("caffeinate", "-i")
    if err := cmd.Start(); err != nil {
        return err
    }
    w.inhibitor = cmd.Process
    w.acquired = true
    return nil
}

func (w *WakeLocker) Release() {
    if w.inhibitor != nil {
        w.inhibitor.Kill()
        w.inhibitor = nil
    }
    w.acquired = false
}
```

### Configuration

```json
{
  "wakelock": {
    "enabled": true,
    "duration_seconds": 10,
    "method": "auto"  // "caffeinate", "dbus", "auto"
  }
}
```

---

## Audio Player Compatibility

Wake lock operates alongside audio playback:
- Doesn't modify audio player
- Ensures system stays awake for playback
- Works with afplay, mpv, ffplay

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `caffeinate` | Native (macOS) | Free | Built-in |
| `xset` | Native (Linux/X11) | Free | Built-in |
| `dbus-send` | Native (Linux) | Free | Built-in |

---

## References

### Research Sources

- [macOS caffeinate](https://www.unix.com/man-page/darwin/1/caffeinate/)
- [X11 screensaver](https://www.x.org/releases/X11R7.7/doc/libX11/libX11/libX11.html)
- [DBus ScreenSaver](https://specifications.freedesktop.org/idle-inhibition-spec/)

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91) - Platform detection

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via caffeinate |
| Linux | ⚠️ Partial | X11/DBus supported |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
