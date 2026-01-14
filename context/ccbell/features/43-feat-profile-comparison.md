# Feature: Profile Comparison

Compare two profiles side by side.

## Summary

Display differences between two profiles to help users understand configuration variations.

## Motivation

- Understand profile differences
- Debug profile issues
- Create new profiles from existing ones

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Comparison Output

```
$ /ccbell:profile compare default work

=== Profile Comparison ===

Profile: default     Profile: work
────────────────────────────────────────────
enabled: true        enabled: true
volume:  0.50        volume:  0.60 [+0.10]
────────────────────────────────────────────
Events:
────────────────────────────────────────────
stop              stop
  enabled: true     enabled: true
  volume:  0.50     volume:  0.40 [-0.10]
  sound:   bundled  sound:   custom:/path

permission_prompt permission_prompt
  enabled: true     enabled: false
  sound:   bundled  (same)

idle_prompt       idle_prompt
  (same)           (same)

────────────────────────────────────────────
Differences: 4
```

### Implementation

```go
type ComparisonResult struct {
    ProfileA      string
    ProfileB      string
    Differences   []Difference
    SameFields    []string
}

type Difference struct {
    Field    string
    ValueA   string
    ValueB   string
}

func CompareProfiles(cfg *Config, nameA, nameB string) (*ComparisonResult, error) {
    result := &ComparisonResult{
        ProfileA:    nameA,
        ProfileB:    nameB,
        Differences: []Difference{},
        SameFields:  []string{},
    }

    profileA := cfg.Profiles[nameA]
    profileB := cfg.Profiles[nameB]

    if profileA == nil {
        return nil, fmt.Errorf("profile %s not found", nameA)
    }
    if profileB == nil {
        return nil, fmt.Errorf("profile %s not found", nameB)
    }

    // Compare events
    for eventName := range config.ValidEvents {
        eventA := profileA.Events[eventName]
        eventB := profileB.Events[eventName]

        diff := compareEvents(eventName, eventA, eventB)
        result.Differences = append(result.Differences, diff...)
    }

    return result, nil
}
```

### Commands

```bash
/ccbell:profile compare default work           # Compare two profiles
/ccbell:profile compare default                # Compare default to active
/ccbell:profile compare work silent --json     # JSON output
/ccbell:profile compare --all                  # Compare all profiles
```

### JSON Output

```json
{
  "profile_a": "default",
  "profile_b": "work",
  "differences": [
    {
      "field": "stop.volume",
      "value_a": "0.50",
      "value_b": "0.60",
      "change": "+0.10"
    },
    {
      "field": "stop.sound",
      "value_a": "bundled:stop",
      "value_b": "custom:/path/to/sound.aiff"
    }
  ],
  "same_count": 8,
  "diff_count": 4
}
```

---

## Audio Player Compatibility

Profile comparison doesn't interact with audio playback:
- Purely config analysis
- No player changes required
- Reads from config only

---

## Implementation

### Field Comparison

```go
func compareField(name, valA, valB string) *Difference {
    if valA == valB {
        return nil
    }
    return &Difference{
        Field:  name,
        ValueA: valA,
        ValueB: valB,
    }
}

func compareEvents(name string, eventA, eventB *config.Event) []Difference {
    diffs := []Difference{}

    if eventA == nil && eventB == nil {
        return diffs
    }
    if eventA == nil {
        eventA = &config.Event{Enabled: ptrBool(true)}
    }
    if eventB == nil {
        eventB = &config.Event{Enabled: ptrBool(true)}
    }

    if d := compareField("enabled",
        strconv.FormatBool(*eventA.Enabled),
        strconv.FormatBool(*eventB.Enabled)); d != nil {
        diffs = append(diffs, *d)
    }

    // Compare other fields...

    return diffs
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Profile structure
- [Profile handling](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L40-L43) - Profile struct
- [Event comparison](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L205-L220) - Merge pattern

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
