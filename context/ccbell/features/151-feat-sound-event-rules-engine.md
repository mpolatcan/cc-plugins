# Feature: Sound Event Rules Engine

Rules engine for complex event handling.

## Summary

Rule-based event processing with expressions.

## Motivation

- Complex logic
- Flexible rules
- Expression support

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Rule Components

| Component | Description | Example |
|-----------|-------------|---------|
| When | Trigger condition | event == "stop" |
| If | Additional checks | volume > 0.5 |
| Then | Actions to take | play sound |
| Else | Alternative actions | use fallback |

### Configuration

```go
type RulesConfig struct {
    Enabled     bool    `json:"enabled"`
    Engine      string  `json:"engine"` // "simple", "expression"
    Rules       []*Rule `json:"rules"`
}

type Rule struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    When        string   `json:"when"`   // trigger expression
    If          string   `json:"if,omitempty"` // condition expression
    Then        []string `json:"then"`   // actions
    Else        []string `json:"else,omitempty"` // alternative
    Priority    int      `json:"priority"` // evaluation order
    Enabled     bool     `json:"enabled"`
}

type EvaluationContext struct {
    EventType   string
    SoundID     string
    Volume      float64
    Cooldown    int
    Hour        int
    DayOfWeek   int
    Platform    string
    TimeSinceLastEvent time.Duration
}
```

### Commands

```bash
/ccbell:rules list                  # List rules
/ccbell:rules create "High volume stop"
/ccbell:rules set when "event == 'stop'"
/ccbell:rules set if "volume > 0.7"
/ccbell:rules set then "play bundled:soft; volume=0.5"
/ccbell:rules set else "play bundled:stop"
/ccbell:rules enable <id>           # Enable rule
/ccbell:rules disable <id>          # Disable rule
/ccbell:rules test stop volume=0.8  # Test rule
/ccbell:rules delete <id>           # Remove rule
```

### Output

```
$ ccbell:rules list

=== Sound Event Rules Engine ===

Engine: Simple
Rules: 4

[1] High Volume Stop
    When: event == 'stop'
    If: volume > 0.7
    Then: [play bundled:soft; volume=0.5]
    Priority: 1
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[2] Night Mode
    When: hour >= 22 || hour < 7
    Then: [volume=0.3]
    Priority: 2
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[3] Quick Subagent
    When: event == 'subagent'
    If: time_since_last < 30s
    Then: [cooldown=10]
    Priority: 3
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[Create] [Import] [Export]
```

---

## Audio Player Compatibility

Rules engine works with existing audio player:
- Modifies event handling
- Same format support
- No player changes required

---

## Implementation

### Rule Evaluation

```go
type RulesEngine struct {
    config  *RulesConfig
    player  *audio.Player
}

func (e *RulesEngine) Evaluate(ctx *EvaluationContext, cfg *EventConfig) (*EventConfig, error) {
    result := *cfg

    for _, rule := range e.getSortedRules() {
        if !rule.Enabled {
            continue
        }

        // Check When
        if !e.evaluateExpression(rule.When, ctx) {
            continue
        }

        // Check If
        if rule.If != "" && !e.evaluateExpression(rule.If, ctx) {
            continue
        }

        // Execute Then
        for _, action := range rule.Then {
            result = e.applyAction(result, action)
        }

        return &result, nil
    }

    return cfg, nil
}

func (e *RulesEngine) evaluateExpression(expr string, ctx *EvaluationContext) bool {
    // Simple expression evaluation
    // Replace variables and evaluate

    expr = strings.ReplaceAll(expr, "event", ctx.EventType)
    expr = strings.ReplaceAll(expr, "volume", fmt.Sprintf("%f", ctx.Volume))
    expr = strings.ReplaceAll(expr, "hour", fmt.Sprintf("%d", ctx.Hour))
    expr = strings.ReplaceAll(expr, "time_since_last", ctx.TimeSinceLastEvent.String())

    // Parse and evaluate
    return e.parseAndEvaluate(expr)
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Rule configuration
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event evaluation

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
