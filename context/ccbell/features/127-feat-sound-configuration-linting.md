# Feature: Sound Configuration Linting

Validate and lint sound configurations.

## Summary

Check sound configurations for issues, best practices, and potential problems.

## Motivation

- Find configuration issues
- Enforce best practices
- Prevent common mistakes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Lint Rules

| Rule | Description | Severity |
|------|-------------|----------|
| volume_range | Volume in valid range | Error |
| cooldown_valid | Cooldown reasonable | Warning |
| sound_exists | Sound file exists | Error |
| sound_format | Format is supported | Error |
| duplicate_sounds | Same sound for multiple events | Info |
| low_volume | Volume below threshold | Warning |
| missing_default | Missing default sound | Info |

### Implementation

```go
type LintConfig struct {
    Rules     []LintRule `json:"rules"`
    Severity  string     `json:"severity"`  // all, errors, warnings
    FixMode   bool       `json:"fix_mode"`  // auto-fix issues
}

type LintRule struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    Description string `json:"description"`
    Enabled     bool   `json:"enabled"`
    Severity    string `json:"severity"` // error, warning, info
}

type LintResult struct {
    File       string      `json:"file"`
    Issues     []LintIssue `json:"issues"`
    Summary    LintSummary `json:"summary"`
}

type LintIssue struct {
    Rule     string `json:"rule"`
    Severity string `json:"severity"`
    Message  string `json:"message"`
    Location string `json:"location"`
    Fix      string `json:"fix,omitempty"`
}
```

### Commands

```bash
/ccbell:lint                     # Lint configuration
/ccbell:lint --fix               # Auto-fix issues
/ccbell:lint --severity error    # Errors only
/ccbell:lint --rules volume,cooldown
/ccbell:lint --output json       # JSON output
/ccbell:lint list-rules          # List available rules
/ccbell:lint config             # Lint config file
```

### Output

```
$ ccbell:lint

=== Sound Configuration Lint ===

File: ~/.config/ccbell/config.json
Rules: 12 (8 enabled)

[======] 100% complete

Issues found: 3

Errors:
  [1] volume_range
      Location: events.permission_prompt.volume
      Message: Volume 1.5 exceeds maximum of 1.0
      Fix: Set to 1.0

Warnings:
  [2] cooldown_low
      Location: events.stop.cooldown
      Message: Cooldown of 0 may cause spam
      Fix: Consider setting to 2s

  [3] low_volume
      Location: events.idle_prompt.volume
      Message: Volume 0.05 may be inaudible
      Fix: Consider increasing to 0.2

Summary:
  Errors: 1
  Warnings: 2
  Info: 0

[Fix All] [Fix 1] [Ignore] [Details]
```

---

## Audio Player Compatibility

Linting doesn't play sounds:
- Analysis feature
- No player changes required

---

## Implementation

### Lint Rules

```go
func (l *Linter) runRules() []LintIssue {
    issues := []LintIssue{}

    for _, rule := range l.enabledRules {
        switch rule.ID {
        case "volume_range":
            issues = append(issues, l.checkVolumeRange()...)
        case "cooldown_valid":
            issues = append(issues, l.checkCooldown()...)
        case "sound_exists":
            issues = append(issues, l.checkSoundExists()...)
        case "sound_format":
            issues = append(issues, l.checkSoundFormat()...)
        case "duplicate_sounds":
            issues = append(issues, l.checkDuplicates()...)
        }
    }

    return issues
}

func (l *Linter) checkVolumeRange() []LintIssue {
    issues := []LintIssue{}

    for event, cfg := range l.config.Events {
        vol := derefFloat(cfg.Volume, 0.5)
        if vol < 0 || vol > 1 {
            issues = append(issues, LintIssue{
                Rule:     "volume_range",
                Severity: "error",
                Message:  fmt.Sprintf("Volume %.2f for '%s' is outside valid range [0, 1]", vol, event),
                Location: fmt.Sprintf("events.%s.volume", event),
                Fix:      fmt.Sprintf("Set volume to %.2f", math.Max(0, math.Min(1, vol))),
            })
        }
    }

    return issues
}
```

### Auto-fix

```go
func (l *Linter) applyFix(issue LintIssue) error {
    switch issue.Rule {
    case "volume_range":
        return l.fixVolumeRange(issue)
    case "cooldown_low":
        return l.fixCooldown(issue)
    case "low_volume":
        return l.fixLowVolume(issue)
    }
    return nil
}

func (l *Linter) fixVolumeRange(issue LintIssue) error {
    // Parse location and apply fix
    // Update config with fixed value
    return l.config.Save()
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config validation
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Format validation

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
