# Feature: Audio Latency Adjustment

Adjust for audio playback delay.

## Summary

Configure audio latency to compensate for system-specific playback delays.

## Motivation

- Synchronize notifications with visual cues
- Account for Bluetooth audio delays
- Reduce perceived lag

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Latency Sources

| Source | Typical Delay |
|--------|---------------|
| Bluetooth audio | 100-300ms |
| HDMI audio | 50-150ms |
| USB audio | 20-50ms |
| Built-in speakers | 5-20ms |

### Configuration

```json
{
  "latency": {
    "enabled": true,
    "adjustment_ms": 150,
    "per_device": {
      "default": 0,
      "Bluetooth Headset": 200,
      "HDMI TV": 100
    }
  }
}
```

### Implementation

```go
type LatencyConfig struct {
    Enabled        bool              `json:"enabled"`
    AdjustmentMs   int               `json:"adjustment_ms"`
    PerDevice      map[string]int    `json:"per_device,omitempty"`
    DefaultDevice  string            `json:"default_device,omitempty"`
}

// Get effective latency for current device
func (c *CCBell) getLatency() time.Duration {
    if c.latencyConfig == nil || !c.latencyConfig.Enabled {
        return 0
    }

    device := c.currentDevice
    if device == "" {
        device = "default"
    }

    // Check per-device latency
    if latency, ok := c.latencyConfig.PerDevice[device]; ok {
        return time.Duration(latency) * time.Millisecond
    }

    // Fall back to default
    return time.Duration(c.latencyConfig.AdjustmentMs) * time.Millisecond
}
```

### Latency Compensation

```go
// Play with delay
func (p *Player) PlayWithLatency(soundPath string, volume float64, latency time.Duration) error {
    // Wait for latency compensation
    time.Sleep(latency)

    // Then play
    return p.Play(soundPath, volume)
}
```

### Commands

```bash
/ccbell:latency set 150            # Set 150ms latency
/ccbell:latency set --device "Bluetooth" 200
/ccbell:latency detect             # Try to detect latency
/ccbell:latency calibrate          # Interactive calibration
/ccbell:latency reset              # Reset to 0
/ccbell:latency status             # Show current latency
```

### Calibration

```
$ /ccbell:latency calibrate

Calibration: Play a sound and tap when you see the flash

[1] Playing... [tap now when sound plays]

Estimated latency: 180ms
Save as default? [y/n]:
```

---

## Audio Player Compatibility

Latency adjustment delays playback:
- Uses `time.Sleep()` before calling player
- Works with all audio players
- No player changes required

---

## Implementation

### Device Detection

```go
func detectAudioDevice() string {
    switch detectPlatform() {
    case PlatformMacOS:
        return detectMacOSDevice()
    case PlatformLinux:
        return detectLinuxDevice()
    }
    return "default"
}
```

### Latency Application

```go
// In main.go
latency := c.getLatency()
if latency > 0 {
    log.Debug("Applying latency: %dms", latency/time.Millisecond)
    time.Sleep(latency)
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For latency config
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback integration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time-based |
| Linux | ✅ Supported | Time-based |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
