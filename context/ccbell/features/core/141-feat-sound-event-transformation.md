# Feature: Sound Event Transformation

Transform events before playback.

## Summary

Transform events (change sound, volume) based on rules.

## Motivation

- Dynamic event handling
- Conditional sound selection
- Event enrichment

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Transformation Types

| Type | Description | Example |
|------|-------------|---------|
| Sound replace | Change sound | stop -> custom:bell |
| Volume adjust | Adjust volume | 0.5 -> 0.7 |
| Cooldown modify | Change cooldown | 0 -> 5 |
| Add prefix | Prefix sound | custom: -> bundled: |

### Configuration

```go
type TransformConfig struct {
    Enabled      bool              `json:"enabled"`
    Rules        []TransformRule   `json:"rules"`
}

type TransformRule struct {
    ID          string   `json:"id"`
    MatchEvent  string   `json:"match_event"`  // event type to match
    MatchSound  string   `json:"match_sound"`  // sound to match
    Conditions  []Condition `json:"conditions"` // when to apply
    Transforms  []Transform  `json:"transforms"` // what to do
    Enabled     bool     `json:"enabled"`
}

type Condition struct {
    Type   string `json:"type"`   // "time", "day", "volume", "count"
    Operator string `json:"operator"` // "eq", "gt", "lt", "between"
    Value  string `json:"value"`
}

type Transform struct {
    Type  string `json:"type"` // "sound", "volume", "cooldown"
    Value string `json:"value"`
}
```

### Commands

```bash
/ccbell:transform enable            # Enable transformations
/ccbell:transform disable           # Disable transformations
/ccbell:transform add "stop:volume>0.8" -> "stop:volume=0.5"
/ccbell:transform list              # List transformations
/ccbell:transform test stop         # Test transformation
/ccbell:transform remove <id>       # Remove transformation
/ccbell:transform clear             # Clear all
/ccbell:transform export            # Export rules
```

### Output

```
$ ccbell:transform list

=== Sound Event Transformations ===

Status: Enabled
Rules: 3

[1] If stop volume > 80%
    Then set volume to 50%
    Enabled
    [Test] [Edit] [Remove]

[2] If idle_prompt during 22:00-07:00
    Then use bundled:silent
    Enabled
    [Test] [Edit] [Remove]

[3] If subagent count > 10 in 1h
    Then set cooldown to 10s
    Enabled
    [Test] [Edit] [Remove]

[Add] [Import] [Export]
```

---

## Audio Player Compatibility

Transformation works with existing audio player:
- Modifies config before playback
- Same format support
- No player changes required

---

## Implementation

### Rule Processing

```go
type Transformer struct {
    config  *TransformConfig
}

func (t *Transformer) Transform(eventType, soundID string, cfg *EventConfig) (*EventConfig, error) {
    result := *cfg

    for _, rule := range t.config.Rules {
        if !rule.Enabled {
            continue
        }

        // Check if rule matches
        if !t.matchesRule(eventType, soundID, cfg, rule) {
            continue
        }

        // Apply transforms
        for _, transform := range rule.Transforms {
            switch transform.Type {
            case "sound":
                result.Sound = transform.Value
            case "volume":
                vol, _ := strconv.ParseFloat(transform.Value, 64)
                result.Volume = &vol
            case "cooldown":
                cd, _ := strconv.Atoi(transform.Value)
                result.Cooldown = &cd
            }
        }
    }

    return &result, nil
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event transformation point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
