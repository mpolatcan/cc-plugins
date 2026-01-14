# Feature: Sound Preset Suggestions

Suggest optimal sound presets.

## Summary

Analyze usage and suggest optimal preset configurations.

## Motivation

- Optimize notification experience
- Data-driven suggestions
- Personalization

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Suggestion Types

| Type | Description | Based On |
|------|-------------|----------|
| Volume | Suggest volume level | Usage patterns |
| Cooldown | Suggest cooldown | Event frequency |
| Preset | Suggest preset switch | Time/activity |
| Sound | Suggest sound change | Usage analytics |

### Implementation

```go
type SuggestionConfig struct {
    Enabled         bool    `json:"enabled"`
    AnalyzeVolume   bool    `json:"analyze_volume"`
    AnalyzeCooldown bool    `json:"analyze_cooldown"`
    AnalyzePreset   bool    `json:"analyze_preset"`
    Threshold       float64 `json:"threshold"` // confidence threshold
}

type Suggestion struct {
    ID          string    `json:"id"`
    Type        string    `json:"type"` // volume, cooldown, preset, sound
    EventType   string    `json:"event_type,omitempty"`
    Current     string    `json:"current"`
    Suggested   string    `json:"suggested"`
    Reason      string    `json:"reason"`
    Confidence  float64   `json:"confidence"` // 0-1
    BasedOn     string    `json:"based_on"`
    CreatedAt   time.Time `json:"created_at"`
}
```

### Commands

```bash
/ccbell:suggest                      # Get all suggestions
/ccbell:suggest volume               # Volume suggestions
/ccbell:suggest cooldown             # Cooldown suggestions
/ccbell:suggest preset               # Preset suggestions
/ccbell:suggest sound                # Sound suggestions
/ccbell:suggest apply <id>           # Apply suggestion
/ccbell:suggest apply all            # Apply all suggestions
/ccbell:suggest dismiss <id>         # Dismiss suggestion
/ccbell:suggest --json               # JSON output
```

### Output

```
$ ccbell:suggest

=== Sound Suggestions ===

Based on your usage patterns:

[1] Volume Adjustment
    Event: stop
    Current: 70%
    Suggested: 50%
    Reason: Your stop sounds often overlap with other sounds
    Confidence: 85%
    [Apply] [Dismiss]

[2] Cooldown Setting
    Event: subagent
    Current: 0s
    Suggested: 5s
    Reason: 12 rapid subagent completions in past week
    Confidence: 72%
    [Apply] [Dismiss]

[3] Preset Switch
    Current: Default
    Suggested: Work Mode
    Reason: Based on your work hours (9 AM - 5 PM)
    Confidence: 68%
    [Apply] [Dismiss]

[Apply All] [Configure]
```

---

## Audio Player Compatibility

Suggestions don't play sounds:
- Analysis feature
- No player changes required

---

## Implementation

### Usage Analysis

```go
func (s *SuggestionManager) analyzeVolume() []*Suggestion {
    suggestions := []*Suggestion{}

    for event, analytics := range s.analytics {
        // Check if volume often causes issues
        if analytics.OverlapRate > 0.3 {
            currentVol := s.config.GetEventVolume(event)
            suggestedVol := currentVol * 0.7 // Reduce by 30%

            suggestions = append(suggestions, &Suggestion{
                ID:         generateID(),
                Type:       "volume",
                EventType:  event,
                Current:    fmt.Sprintf("%.0f%%", currentVol*100),
                Suggested:  fmt.Sprintf("%.0f%%", suggestedVol*100),
                Reason:     "Your sounds often overlap with other audio",
                Confidence: analytics.OverlapRate,
                BasedOn:    "Overlap analysis",
                CreatedAt:  time.Now(),
            })
        }
    }

    return suggestions
}
```

### Cooldown Analysis

```go
func (s *SuggestionManager) analyzeCooldown() []*Suggestion {
    suggestions := []*Suggestion{}

    for event, analytics := range s.analytics {
        rapidPlays := s.countRapidPlays(event, 10*time.Second)

        if rapidPlays > 5 {
            currentCd := s.config.GetEventCooldown(event)
            suggestedCd := currentCd + 5 // Add 5 seconds

            suggestions = append(suggestions, &Suggestion{
                ID:         generateID(),
                Type:       "cooldown",
                EventType:  event,
                Current:    fmt.Sprintf("%ds", currentCd),
                Suggested:  fmt.Sprintf("%ds", suggestedCd),
                Reason:     fmt.Sprintf("%d rapid %s events in past week", rapidPlays, event),
                Confidence: float64(rapidPlays) / 20.0,
                BasedOn:    "Event frequency analysis",
                CreatedAt:  time.Now(),
            })
        }
    }

    return suggestions
}
```

### Suggestion Application

```go
func (s *SuggestionManager) ApplySuggestion(suggestionID string) error {
    suggestion := s.findSuggestion(suggestionID)
    if suggestion == nil {
        return fmt.Errorf("suggestion not found: %s", suggestionID)
    }

    switch suggestion.Type {
    case "volume":
        return s.applyVolumeSuggestion(suggestion)
    case "cooldown":
        return s.applyCooldownSuggestion(suggestion)
    case "preset":
        return s.applyPresetSuggestion(suggestion)
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

- [Analytics integration](features/78-feat-sound-usage-analytics.md) - Usage analysis
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Suggestion application

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
