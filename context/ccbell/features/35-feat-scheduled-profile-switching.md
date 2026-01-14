# Feature: Scheduled Profile Switching

Automatically switch profiles based on time schedules.

## Summary

Define time-based rules to automatically activate different profiles without manual intervention.

## Motivation

- Automatically switch to "work" profile during work hours
- "Quiet" profile on weekends
- Seamless profile transitions throughout the day

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Schedule Configuration

```json
{
  "profile_schedule": {
    "enabled": true,
    "rules": [
      {
        "name": "work-hours",
        "start": "09:00",
        "end": "18:00",
        "days": ["mon", "tue", "wed", "thu", "fri"],
        "profile": "work"
      },
      {
        "name": "weekend",
        "start": "00:00",
        "end": "23:59",
        "days": ["sat", "sun"],
        "profile": "quiet"
      },
      {
        "name": "night",
        "start": "22:00",
        "end": "07:00",
        "profile": "silent"
      }
    ],
    "default_profile": "default"
  }
}
```

### Days Format

```go
var validDays = map[string]time.Weekday{
    "sun": time.Sunday,
    "mon": time.Monday,
    "tue": time.Tuesday,
    "wed": time.Wednesday,
    "thu": time.Thursday,
    "fri": time.Friday,
    "sat": time.Saturday,
    "weekday": -1,  // Special: Mon-Fri
    "weekend": -2,  // Special: Sat-Sun
}
```

### Implementation

```go
type ProfileSchedule struct {
    Enabled        bool             `json:"enabled"`
    Rules          []*ScheduleRule  `json:"rules"`
    DefaultProfile string           `json:"default_profile"`
}

type ScheduleRule struct {
    Name    string   `json:"name"`
    Start   string   `json:"start"`   // HH:MM
    End     string   `json:"end"`     // HH:MM
    Days    []string `json:"days"`    // ["mon", "tue", ...]
    Profile string   `json:"profile"`
}

func (c *CCBell) getScheduledProfile() string {
    if c.scheduleConfig == nil || !c.scheduleConfig.Enabled {
        return c.config.ActiveProfile
    }

    now := time.Now()
    currentDay := now.Weekday()
    currentTime := now.Format("15:04")

    for _, rule := range c.scheduleConfig.Rules {
        if !rule.matchesDay(currentDay) {
            continue
        }

        if isTimeInRange(currentTime, rule.Start, rule.End) {
            log.Debug("Profile schedule matched: %s -> %s", rule.Name, rule.Profile)
            return rule.Profile
        }
    }

    return c.scheduleConfig.DefaultProfile
}

func (r *ScheduleRule) matchesDay(day time.Weekday) bool {
    for _, d := range r.Days {
        if targetDay, ok := validDays[d]; ok {
            if targetDay < 0 {
                // Special cases
                if targetDay == -1 && day >= time.Monday && day <= time.Friday {
                    return true
                }
                if targetDay == -2 && (day == time.Saturday || day == time.Sunday) {
                    return true
                }
            } else if targetDay == day {
                return true
            }
        }
    }
    return false
}
```

### Check Timing

```go
// Check on each notification trigger
func (c *CCBell) checkProfileSchedule() {
    scheduled := c.getScheduledProfile()
    if scheduled != c.config.ActiveProfile {
        oldProfile := c.config.ActiveProfile
        c.config.ActiveProfile = scheduled
        log.Info("Profile auto-switch: %s -> %s", oldProfile, scheduled)
    }
}
```

### Commands

```bash
/ccbell:schedule list          # Show current schedule
/ccbell:schedule add work-days --profile work --time 09:00-18:00 --days mon-fri
/ccbell:schedule remove work-days
/ccbell:schedule test          # Test schedule matching
/ccbell:schedule validate      # Validate schedule config
```

---

## Audio Player Compatibility

Profile scheduling doesn't interact with audio playback:
- Only affects config selection
- Same audio player regardless of profile
- No player changes required

---

## Implementation

### Config Integration

```go
type Config struct {
    // ... existing fields ...
    ProfileSchedule *ProfileSchedule `json:"profileSchedule,omitempty"`
}
```

### Validation

```go
func (s *ProfileSchedule) Validate() error {
    for _, rule := range s.Rules {
        if !isValidTime(rule.Start) || !isValidTime(rule.End) {
            return fmt.Errorf("invalid time in rule %s", rule.Name)
        }
        for _, day := range rule.Days {
            if _, ok := validDays[day]; !ok {
                return fmt.Errorf("invalid day %s in rule %s", day, rule.Name)
            }
        }
        if _, ok := s.Profiles[rule.Profile]; !ok && rule.Profile != "default" {
            return fmt.Errorf("profile %s not found in rule %s", rule.Profile, rule.Name)
        }
    }
    return nil
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Profile handling
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Time-based logic pattern
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time-based only |
| Linux | ✅ Supported | Time-based only |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
