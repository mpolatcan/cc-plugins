# Feature: Sound Context Awareness

Context-aware sound playback.

## Summary

Play sounds based on system context (time, activity, etc.).

## Motivation

- Intelligent notifications
- Context-sensitive sounds
- Adaptive behavior

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Context Sources

| Source | Description | Example |
|--------|-------------|---------|
| Time | Current time | Evening, work hours |
| Battery | Battery level | Low battery mode |
| Network | Network status | Offline mode |
| Display | Display state | Screen locked |
| Audio | Audio output | Headphones connected |
| Location | Location-based | Home/Office |

### Configuration

```go
type ContextConfig struct {
    Enabled         bool              `json:"enabled"`
    Sources         []string          `json:"sources"`          // enabled sources
    TimeRules       []TimeRule        `json:"time_rules"`
    BatteryRules    []BatteryRule     `json:"battery_rules"`
    AudioRules      []AudioRule       `json:"audio_rules"`
    DisplayRules    []DisplayRule     `json:"display_rules"`
    FallbackSound   string            `json:"fallback_sound"`  // when no context
}

type TimeRule struct {
    Name        string   `json:"name"`
    StartTime   string   `json:"start_time"`  // HH:MM
    EndTime     string   `json:"end_time"`    // HH:MM
    DaysOfWeek  []int    `json:"days_of_week"` // 0-6
    VolumeMod   float64  `json:"volume_mod"`  // volume modifier
    SoundOverride string `json:"sound_override"`
    Enabled     bool     `json:"enabled"`
}

type AudioRule struct {
    OutputDevice string  `json:"output_device"` // "headphones", "speakers"
    VolumeMod    float64 `json:"volume_mod"`
    Mute         bool    `json:"mute"`
}
```

### Commands

```bash
/ccbell:context enable              # Enable context awareness
/ccbell:context disable             # Disable context awareness
/ccbell:context status              # Show current context
/ccbell:context rule add time "18:00" "09:00" --volume 0.5
/ccbell:context rule add battery low --mute
/ccbell:context rule add audio headphones --volume 1.2
/ccbell:context list                # List context rules
/ccbell:context test                # Test current context
/ccbell:context simulate evening    # Simulate context
```

### Output

```
$ ccbell:context status

=== Context Awareness ===

Status: Enabled
Current Context:

  Time: 10:30 AM (Work Hours)
  Battery: 85% (Not Low)
  Audio: Speakers (Default)
  Display: Active
  Network: Online

Applied Rules:
  [✓] Work Hours: Volume 100% (10:30 AM)
  [✓] Speakers: Volume 100% (Default)
  [✓] Screen Active: Normal playback

Effective Volume: 50%
Effective Sound: bundled:stop

[Rules] [Simulate] [Configure]
```

---

## Audio Player Compatibility

Context awareness works with existing audio player:
- Modifies volume/sound before playback
- Same format support
- No player changes required

---

## Implementation

### Context Collection

```go
type ContextCollector struct {
    config *ContextConfig
}

func (c *ContextCollector) GetCurrentContext() *SystemContext {
    return &SystemContext{
        Time:       c.getTimeContext(),
        Battery:    c.getBatteryContext(),
        Audio:      c.getAudioContext(),
        Display:    c.getDisplayContext(),
        Network:    c.getNetworkContext(),
        Location:   c.getLocationContext(),
    }
}

func (c *ContextCollector) getTimeContext() *TimeContext {
    now := time.Now()
    return &TimeContext{
        Hour:       now.Hour(),
        Minute:     now.Minute(),
        DayOfWeek:  int(now.Weekday()),
        IsWeekend:  now.Weekday() == time.Saturday || now.Weekday() == time.Sunday,
        WorkHours:  now.Hour() >= 9 && now.Hour() < 17,
    }
}
```

### Context Application

```go
func (c *ContextManager) ApplyContext(eventType string, cfg *EventConfig) (*EventConfig, error) {
    context := c.collector.GetCurrentContext()
    result := *cfg

    // Apply time rules
    if rule := c.findMatchingTimeRule(context.Time); rule != nil {
        if rule.VolumeMod != 0 {
            result.Volume = derefFloat(cfg.Volume, 0.5) * rule.VolumeMod
        }
        if rule.SoundOverride != "" {
            result.Sound = rule.SoundOverride
        }
    }

    // Apply audio rules
    if rule := c.findMatchingAudioRule(context.Audio); rule != nil {
        if rule.Mute {
            result.Enabled = false
        }
        if rule.VolumeMod != 0 {
            result.Volume = derefFloat(cfg.Volume, 0.5) * rule.VolumeMod
        }
    }

    return &result, nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pmset | System tool | Free | macOS battery info |
| upower | External tool | Free | Linux battery info |
| pactl | External tool | Free | Linux audio info |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Context-aware playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Rule configuration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via pmset/system calls |
| Linux | ✅ Supported | Via upower/pactl |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
