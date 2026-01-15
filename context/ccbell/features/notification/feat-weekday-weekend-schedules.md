---
name: Weekday/Weekend Schedules
description: Override default quiet hours with weekend-specific schedules
category: notification
---

# Feature: Weekday/Weekend Schedules

Override default quiet hours with weekend-specific schedules. Respects different schedules for weekdays vs. weekends.

## Table of Contents

1. [Summary](#summary)
2. [Benefit](#benefit)
3. [Priority & Complexity](#priority--complexity)
4. [Feasibility](#feasibility)
   - [Claude Code](#claude-code)
   - [Audio Player](#audio-player)
   - [External Dependencies](#external-dependencies)
5. [Usage in ccbell Plugin](#usage-in-ccbell-plugin)
6. [Repository Impact](#repository-impact)
   - [cc-plugins](#cc-plugins)
   - [ccbell](#ccbell)
7. [Implementation Plan](#implementation-plan)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
8. [External Dependencies](#external-dependencies-1)
9. [Research Details](#research-details)
10. [Research Sources](#research-sources)

## Summary

Override default quiet hours with weekend-specific schedules. Automated adaptation to different schedules for weekdays vs. weekends.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Respects different schedules for work-life balance |
| :memo: Use Cases | Family-friendly, personalized rhythms |
| :dart: Value Proposition | Automated adaptation, no manual changes needed |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🟡 Medium | |
| :construction: Complexity | 🟢 Low | |
| :warning: Risk Level | 🟢 Low | |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | Enhanced `quiet hours` command with weekday/weekend options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for config manipulation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay (macOS) | macOS native audio player | |
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ❌ |

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:quiet hours --weekday 22:00-07:00`, `/ccbell:quiet hours --weekend 23:00-09:00` |
| :wrench: Configuration | Extends `QuietHours` with `weekday` and `weekend` TimeWindow |
| :gear: Default Behavior | Uses weekday schedule Mon-Fri, weekend Sat-Sun |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update configure.md with weekday/weekend options |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Extend QuietHours with weekday/weekend |
| `audio/player.go` | :speaker: Check quiet hours before playback |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add/update command documentation
4. Add/update hooks configuration
5. Add new sound files if applicable

### ccbell

Steps required in ccbell repository:

1. Extend QuietHoursConfig with weekday and weekend TimeWindow
2. Extend IsInQuietHours() with weekday/weekend logic
3. Add --weekday and --weekend flags to quiet hours command
4. Support timezone configuration
5. Add holiday schedule support with date list
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ❌ |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Schedule options can be added to configure command.

### Claude Code Hooks

No new hooks needed - quiet hours check integrated into main flow.

### Audio Playback

Playback is skipped during quiet hours based on day of week.

### Timezone-Aware Scheduling Implementation

#### Timezone Configuration
```go
type TimezoneConfig struct {
    Zone     string `json:"zone"`      // e.g., "America/New_York"
    Offset   int    `json:"offset"`    // e.g., -5 (hours from UTC)
    AutoDetect bool `json:"autoDetect"` // Use system timezone
}

func (t *TimezoneConfig) GetLocation() (*time.Location, error) {
    if t.AutoDetect || t.Zone == "" {
        return time.Local, nil
    }
    if t.Offset != 0 {
        return time.FixedZone(t.Zone, t.Offset*3600), nil
    }
    return time.LoadLocation(t.Zone)
}

func IsInQuietHoursWithTZ(config QuietHoursConfig, tz *time.Location, now time.Time) bool {
    if tz != nil {
        now = now.In(tz)
    }

    weekday := now.Weekday()
    isWeekend := weekday == time.Saturday || weekday == time.Sunday

    var window TimeWindow
    if isWeekend && config.Weekend != nil {
        window = *config.Weekend
    } else if !isWeekend && config.Weekday != nil {
        window = *config.Weekday
    } else if config.Default != nil {
        window = *config.Default
    } else {
        return false // No quiet hours configured
    }

    return now.Format("15:04") >= window.Start && now.Format("15:04") <= window.End
}
```

#### Holiday Scheduling
```go
type HolidayConfig struct {
    Dates    []string `json:"dates"`    // e.g., ["2026-01-01", "2026-12-25"]
    Names    map[string]string `json:"names"` // date -> holiday name
    UseWeekendRules bool `json:"useWeekendRules"` // Use weekend schedule on holidays
}

var nationalHolidays = map[string]bool{
    "2026-01-01": true,  // New Year's Day
    "2026-01-20": true,  // MLK Day
    "2026-02-17": true,  // Presidents Day
    "2026-05-26": true,  // Memorial Day
    "2026-07-04": true,  // Independence Day
    "2026-09-01": true,  // Labor Day
    "2026-11-27": true,  // Thanksgiving
    "2026-12-25": true,  // Christmas
}

func IsHoliday(date time.Time) bool {
    dateStr := date.Format("2006-01-02")
    return nationalHolidays[dateStr]
}

func IsInQuietHours(config QuietHoursConfig, now time.Time) bool {
    // Check if today is a holiday
    if IsHoliday(now) && config.Holidays != nil && config.Holidays.UseWeekendRules {
        if config.Weekend != nil {
            return isTimeInWindow(now, *config.Weekend)
        }
    }

    return isInQuietHoursWithTZ(config, nil, now)
}
```

#### Flexible Day Groups
```go
type DayGroup string

const (
    DayGroupWeekday DayGroup = "weekday"   // Mon-Fri
    DayGroupWeekend DayGroup = "weekend"   // Sat-Sun
    DayGroupMon     DayGroup = "monday"
    DayGroupTue     DayGroup = "tuesday"
    DayGroupWed     DayGroup = "wednesday"
    DayGroupThu     DayGroup = "thursday"
    DayGroupFri     DayGroup = "friday"
    DayGroupSat     DayGroup = "saturday"
    DayGroupSun     DayGroup = "sunday"
)

type ScheduleRule struct {
    Days    []DayGroup `json:"days"`
    Window  TimeWindow `json:"window"`
    Enabled bool       `json:"enabled"`
}

func (s *ScheduleRule) Matches(day time.Weekday) bool {
    dayName := DayGroup(strings.ToLower(day.String()))
    for _, d := range s.Days {
        if d == dayName || d == DayGroupWeekday && day >= time.Monday && day <= time.Friday || d == DayGroupWeekend && (day == time.Saturday || day == time.Sunday) {
            return true
        }
    }
    return false
}
```

#### Multi-Window Support
```go
type AdvancedTimeWindow struct {
    Start   string `json:"start"`
    End     string `json:"end"`
    Enabled bool   `json:"enabled"`
}

type AdvancedQuietHours struct {
    Default     []AdvancedTimeWindow `json:"default"`
    Weekday     []AdvancedTimeWindow `json:"weekday"`
    Weekend     []AdvancedTimeWindow `json:"weekend"`
    Timezone    TimezoneConfig       `json:"timezone"`
    Holidays    HolidayConfig        `json:"holidays"`
}

func IsInQuietHoursAdvanced(config AdvancedQuietHours, now time.Time) bool {
    loc, _ := config.Timezone.GetLocation()
    localNow := now.In(loc)

    day := localNow.Weekday()
    var windows []AdvancedTimeWindow

    if day == time.Saturday || day == time.Sunday {
        windows = config.Weekend
    } else {
        windows = config.Weekday
    }

    if len(windows) == 0 {
        windows = config.Default
    }

    currentTime := localNow.Format("15:04")
    for _, w := range windows {
        if w.Enabled && currentTime >= w.Start && currentTime <= w.End {
            return true
        }
    }
    return false
}
```

### Schedule Features

- **Default quiet hours** (fallback when no specific schedule)
- **Weekday-specific schedule** (Mon-Fri)
- **Weekend-specific schedule** (Sat-Sun)
- **Timezone support** (configurable per schedule)
- **Holiday scheduling** (use weekend rules on holidays)
- **Multiple time windows** (e.g., nap time + nighttime)
- **Flexible day groups** (custom day combinations)
- **Smart defaults** (sensible out-of-box experience)

### Config Examples

#### Basic Weekday/Weekend
```json
{
  "quietHours": {
    "weekday": { "start": "22:00", "end": "07:00" },
    "weekend": { "start": "23:00", "end": "09:00" }
  }
}
```

#### Advanced with Timezone and Holidays
```json
{
  "quietHours": {
    "weekday": [{ "start": "22:00", "end": "07:00" }],
    "weekend": [{ "start": "23:00", "end": "09:00" }],
    "timezone": { "zone": "America/New_York", "autoDetect": false },
    "holidays": {
      "dates": ["2026-01-01", "2026-12-25"],
      "useWeekendRules": true
    }
  }
}
```

#### Multi-Window Schedule
```json
{
  "quietHours": {
    "weekday": [
      { "start": "12:00", "end": "13:00", "enabled": true },
      { "start": "22:00", "end": "07:00", "enabled": true }
    ],
    "weekend": [
      { "start": "23:00", "end": "09:00", "enabled": true }
    ]
  }
}
```

## Research Sources

| Source | Description |
|--------|-------------|
| [Go time package](https://pkg.go.dev/time) | :books: Time handling and timezones |
| [IANA Timezone Database](https://www.iana.org/time-zones) | :books: Official timezone definitions |
| [Current quiet hours implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) | :books: Quiet hours |
| [Time parsing](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) | :books: Time parsing |
| [US Federal Holidays](https://www.opm.gov/policy-data-oversight/pay-leave/federal-holidays/) | :books: Federal holiday dates |
