# Feature: Sound Event Volume Profile

Adjust volume based on time of day or activity.

## Summary

Automatically adjust volume levels based on time of day, day of week, or system activity.

## Motivation

- Automatic quiet hours
- Activity-based volume
- Time-appropriate sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Volume Adjustments

| Trigger | Description | Example |
|---------|-------------|---------|
| Time of Day | Different volumes by hour | Quiet at night |
| Day of Week | Weekend vs weekday | Louder on weekends |
| System Load | CPU/memory based | Quieter when busy |
| Meeting | Calendar integration | Quiet during meetings |

### Configuration

```go
type VolumeProfileConfig struct {
    Enabled     bool                `json:"enabled"`
    Profiles    map[string]*VolumeProfile `json:"profiles"`
    DefaultBase float64             `json:"default_base_volume"` // 0.5
}

type VolumeProfile struct {
    ID          string          `json:"id"`
    Name        string          `json:"name"`
    Rules       []VolumeRule    `json:"rules"`
    Active      bool            `json:"active"`
}

type VolumeRule struct {
    ID          string  `json:"id"`
    Type        string  `json:"type"` // "time", "day", "load", "meeting"
    Multiplier  float64 `json:"multiplier"` // Applied to base volume
    StartTime   string  `json:"start_time,omitempty"` // HH:MM
    EndTime     string  `json:"end_time,omitempty"`
    Days        []string `json:"days,omitempty"`
    LoadThreshold float64 `json:"load_threshold,omitempty"` // CPU threshold
}
```

### Commands

```bash
/ccbell:volume list                 # List volume profiles
/ccbell:volume create "Night Mode" --multiplier 0.5 --start 22:00 --end 07:00
/ccbell:volume create "Weekend" --multiplier 1.2 --days sat,sun
/ccbell:volume create "Quiet Work" --multiplier 0.7 --days mon,tue,wed,thu,fri
/ccbell:volume active <id>          # Set active profile
/ccbell:volume base 0.6             # Set base volume
/ccbell:volume test                 # Test current volume
/ccbell:volume status               # Show current status
```

### Output

```
$ ccbell:volume status

=== Sound Event Volume Profile ===

Status: Enabled
Base Volume: 0.5
Active Profile: Night Mode

Current Rules:
  [Active] Night Mode (0.5x)
    22:00-07:00, all days
    Current: IN EFFECT

  [Inactive] Weekend (1.2x)
    Sat, Sun only

  [Inactive] Quiet Work (0.7x)
    Mon-Fri, 09:00-17:00

Effective Volume: 0.25 (0.5 base * 0.5 Night Mode)

[Configure] [Create] [Test]
```

---

## Audio Player Compatibility

Volume profiles work with all audio players:
- Volume applied before playback
- Compatible with afplay, mpv, paplay, aplay, ffplay

---

## Implementation

### Volume Profile Management

```go
type VolumeProfileManager struct {
    config   *VolumeProfileConfig
    activeProfile string
}

func (m *VolumeProfileManager) GetVolume(eventType string, baseVolume float64) float64 {
    multiplier := m.calculateMultiplier()

    // Apply profile-specific rules
    for _, profile := range m.config.Profiles {
        if !profile.Active {
            continue
        }

        for _, rule := range profile.Rules {
            if m.ruleApplies(rule) {
                multiplier *= rule.Multiplier
            }
        }
    }

    return baseVolume * multiplier
}

func (m *VolumeProfileManager) ruleApplies(rule *VolumeRule) bool {
    now := time.Now()

    switch rule.Type {
    case "time":
        return m.inTimeRange(rule.StartTime, rule.EndTime)
    case "day":
        return contains(rule.Days, now.Weekday().String()[:3])
    case "load":
        return m.getSystemLoad() > rule.LoadThreshold
    case "meeting":
        return m.isInMeeting()
    }

    return false
}

func (m *VolumeProfileManager) inTimeRange(start, end string) bool {
    now := time.Now()
    currentMins := now.Hour()*60 + now.Minute()

    startMins, _ := parseTimeToMinutes(start)
    endMins, _ := parseTimeToMinutes(end)

    if startMins > endMins {
        // Overnight (e.g., 22:00 - 07:00)
        return currentMins >= startMins || currentMins < endMins
    }

    return currentMins >= startMins && currentMins < endMins
}

func (m *VolumeProfileManager) getSystemLoad() float64 {
    // Read system load average
    var loadavg [3]float64
    if _, err := fmt.Sscanf(readFile("/proc/loadavg"), "%f %f %f",
        &loadavg[0], &loadavg[1], &loadavg[2]); err != nil {
        return 0
    }
    return loadavg[0]
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /proc/loadavg | Filesystem | Free | Linux load average |
| sysctl | System Tool | Free | macOS load average |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Volume handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Time-based logic

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses sysctl for load |
| Linux | ✅ Supported | Uses /proc/loadavg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
