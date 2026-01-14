# Feature: Sound Event Governance

Policy enforcement for event handling.

## Summary

Enforce governance policies on event processing.

## Motivation

- Compliance requirements
- Policy enforcement
- Audit compliance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Policy Types

| Type | Description | Example |
|------|-------------|---------|
| Compliance | Required settings | Volume <= 0.5 |
| Security | Security policies | Sound path validation |
| Operational | Operational rules | Max cooldown |
| Audit | Audit requirements | Log all events |

### Configuration

```go
type GovernanceConfig struct {
    Enabled     bool              `json:"enabled"`
    Policies    map[string]*Policy `json:"policies"`
    StrictMode  bool              `json:"strict_mode"` // enforce strictly
    AutoFix     bool              `json:"auto_fix"` // auto-fix violations
}

type Policy struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Category    string   `json:"category"` // "compliance", "security", "operational", "audit"
    Rule        string   `json:"rule"` // policy rule
    Enforcement string   `json:"enforcement"` // "block", "warn", "fix"
    Severity    string   `json:"severity"` // "error", "warning", "info"
    Enabled     bool     `json:"enabled"`
}
```

### Commands

```bash
/ccbell:governance list             # List policies
/ccbell:governance add "Volume Cap" --category compliance --rule "volume <= 0.5"
/ccbell:governance add "Audit Trail" --category audit --rule "log all events"
/ccbell:governance check            # Check compliance
/ccbell:governance enforce          # Enforce policies
/ccbell:governance report           # Generate report
/ccbell:governance enable strict    # Enable strict mode
/ccbell:governance disable          # Disable governance
/ccbell:governance fix              # Auto-fix violations
```

### Output

```
$ ccbell:governance check

=== Sound Event Governance ===

Status: Enabled
Strict Mode: No
Auto Fix: No

Policies: 4

Compliance:
  [1] Volume Cap
      Rule: volume <= 0.5
      Status: COMPLIANT
      [Edit] [Disable]

  [2] Cooldown Required
      Rule: cooldown >= 2s for stop
      Status: VIOLATED
      Current: 0s
      [Fix] [Ignore]

Security:
  [3] Path Validation
      Rule: only absolute paths
      Status: COMPLIANT
      [Edit] [Disable]

Audit:
  [4] Audit Trail
      Rule: log all events
      Status: COMPLIANT
      [Edit] [Disable]

Compliance: 3/4 policies
[Fix All] [Report] [Configure]
```

---

## Audio Player Compatibility

Governance doesn't play sounds:
- Policy enforcement
- No player changes required

---

## Implementation

### Policy Enforcement

```go
type GovernanceManager struct {
    config  *GovernanceConfig
    player  *audio.Player
}

func (m *GovernanceManager) Check(eventType string, cfg *EventConfig) (*GovernanceResult, error) {
    result := &GovernanceResult{
        Compliant: true,
        Violations: []PolicyViolation{},
    }

    for _, policy := range m.config.Policies {
        if !policy.Enabled {
            continue
        }

        violation := m.checkPolicy(policy, eventType, cfg)
        if violation != nil {
            result.Compliant = false
            result.Violations = append(result.Violations, *violation)

            switch policy.Enforcement {
            case "block":
                return result, fmt.Errorf("policy violation: %s", policy.Name)
            case "fix":
                m.fixViolation(policy, cfg)
            case "warn":
                // Just log the warning
            }
        }
    }

    return result, nil
}

func (m *GovernanceManager) checkPolicy(policy *Policy, eventType string, cfg *EventConfig) *PolicyViolation {
    switch policy.Rule {
    case "volume <= 0.5":
        vol := derefFloat(cfg.Volume, 0.5)
        if vol > 0.5 {
            return &PolicyViolation{
                PolicyID: policy.ID,
                PolicyName: policy.Name,
                Message: fmt.Sprintf("volume %.2f exceeds 0.5", vol),
                CurrentValue: fmt.Sprintf("%.2f", vol),
                ExpectedValue: "0.5",
            }
        }
    case "cooldown >= 2s":
        cd := derefInt(cfg.Cooldown, 0)
        if cd < 2 && eventType == "stop" {
            return &PolicyViolation{
                PolicyID: policy.ID,
                PolicyName: policy.Name,
                Message: "stop event has no cooldown",
                CurrentValue: fmt.Sprintf("%ds", cd),
                ExpectedValue: "2s",
            }
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Policy application
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Policy checking point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
