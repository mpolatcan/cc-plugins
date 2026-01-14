# Feature: Power State Awareness

React to power state changes (AC/battery, lid open/close).

## Summary

Adjust notification behavior based on power source and laptop state changes.

## Motivation

- Louder notifications on battery (to hear over fan)
- Quieter notifications when laptop is closed
- Prevent notifications when presenting

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Power State Detection

| Platform | Method | Native Support | Feasibility |
|----------|--------|----------------|-------------|
| macOS | `pmset` | Yes | ✅ Easy |
| Linux | `upower` | Yes | ✅ Easy |
| Linux | `acpi` | No | ⚠️ Requires install |

### macOS Implementation

```bash
# Check power source
pmset -g batt | grep -o "AC\|Battery"

# Check lid state (via ioreg)
ioreg -r -d 4 -c AppleClamshellState | grep AppleClamshellState

# Get display state
pmset -g | grep displaysleep
```

### Linux Implementation

```bash
# Check battery status
upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep state

# Check lid state
cat /proc/acpi/button/lid/LID/state
```

### Configuration

```json
{
  "power_awareness": {
    "enabled": true,
    "battery": {
      "volume_multiplier": 1.2,
      "enabled": true
    },
    "ac": {
      "volume_multiplier": 1.0,
      "enabled": true
    },
    "lid_closed": {
      "enabled": true,
      "action": "suppress"
    },
    "presentation_mode": {
      "volume_multiplier": 0.3
    }
  }
}
```

### Implementation

```go
type PowerState struct {
    Source       string  // "AC" or "Battery"
    LidClosed    bool
    OnBattery    bool
}

func (c *CCBell) getPowerState() (*PowerState, error) {
    switch detectPlatform() {
    case PlatformMacOS:
        return c.getMacOSPowerState()
    case PlatformLinux:
        return c.getLinuxPowerState()
    }
    return &PowerState{Source: "AC", LidClosed: false}, nil
}

func (c *CCBell) getMacOSPowerState() (*PowerState, error) {
    // Check power source
    cmd := exec.Command("pmset", "-g", "batt")
    output, _ := cmd.Output()

    state := &PowerState{}
    if strings.Contains(string(output), "Battery") {
        state.Source = "Battery"
        state.OnBattery = true
    } else {
        state.Source = "AC"
        state.OnBattery = false
    }

    return state, nil
}
```

### Volume Adjustment

```go
func (c *CCBell) adjustForPower(baseVolume float64) float64 {
    if c.powerConfig == nil || !c.powerConfig.Enabled {
        return baseVolume
    }

    state, _ := c.getPowerState()

    if state.OnBattery {
        return baseVolume * c.powerConfig.Battery.VolumeMultiplier
    }

    return baseVolume * c.powerConfig.AC.VolumeMultiplier
}
```

### Commands

```bash
/ccbell:power status            # Show power status
/ccbell:power set-battery 1.2   # Set battery volume multiplier
/ccbell:power set-ac 1.0        # Set AC volume multiplier
/ccbell:power test              # Test power detection
```

---

## Audio Player Compatibility

Power state awareness adjusts volume:
- Uses existing volume handling
- Same audio player
- No player changes required

---

## Implementation

### State Caching

```go
// Cache power state for check interval
type PowerMonitor struct {
    state       *PowerState
    lastCheck   time.Time
    checkPeriod time.Duration
}
```

### Lid Closed Handling

```go
// Check lid state before playing
if state.LidClosed && c.powerConfig.LidClosed.Enabled {
    log.Debug("Skipping notification - laptop lid closed")
    return nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pmset | Native (macOS) | Free | Built-in |
| upower | Native (Linux) | Free | Most distros |

---

## References

### Research Sources

- [macOS pmset](https:// Eastman.com/man/darwin/pmset.1.html)
- [UPower API](https:// Eastman.freedesktop.org/specs/UPower/)
- [Linux ACPI](https://.sourceforge.net/projects/acpica/)

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For power config
- [Volume handling](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L49) - Volume adjustment

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via pmset |
| Linux | ⚠️ Partial | upower/acpi supported |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
