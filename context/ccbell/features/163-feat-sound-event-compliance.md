# Feature: Sound Event Compliance

Compliance checking for sound configurations.

## Summary

Check configurations against compliance requirements.

## Motivation

- Regulatory compliance
- Standards adherence
- Best practices

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Compliance Standards

| Standard | Description | Checks |
|----------|-------------|--------|
| Corporate | Corporate policies | Volume limits, quiet hours |
| Accessibility | Accessibility | Visual alternatives |
| Security | Security policies | Path validation |
| Performance | Performance guidelines | Cooldown settings |

### Configuration

```go
type ComplianceConfig struct {
    Enabled     bool              `json:"enabled"`
    Standards   map[string]*Standard `json:"standards"`
    StrictMode  bool              `json:"strict_mode"` // fail on any violation
}

type Standard struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Category    string   `json:"category"` // "corporate", "accessibility", "security", "performance"
    Rules       []ComplianceRule `json:"rules"`
    Required    bool     `json:"required"` // required standard
    Enabled     bool     `json:"enabled"`
}

type ComplianceRule struct {
    ID          string `json:"id"`
    Description string `json:"description"`
    Check       string `json:"check"` // check expression
    Severity    string `json:"severity"` // "error", "warning"
}
```

### Commands

```bash
/ccbell:compliance list             # List standards
/ccbell:compliance add Corporate --category corporate
/ccbell:compliance add Accessibility --category accessibility
/ccbell:compliance check            # Run compliance check
/ccbell:compliance report           # Generate report
/ccbell:compliance fix              # Auto-fix violations
/ccbell:compliance export           # Export compliance report
/ccbell:compliance status           # Show compliance status
/ccbell:compliance enable strict    # Strict mode
```

### Output

```
$ ccbell:compliance check

=== Sound Compliance Check ===

Standards: 3 enabled

[1] Corporate Policy
    Status: PASSED
    Checks: 5/5 passed

    ✓ Volume <= 70%
    ✓ Quiet hours: 22:00-07:00
    ✓ Cooldown: 2s minimum
    ✓ Logging: enabled
    ✓ Audit: enabled

[2] Accessibility
    Status: FAILED
    Checks: 3/5 passed

    ✗ Visual alerts: NOT CONFIGURED
    ✓ Caption display: enabled
    ✓ High contrast: disabled
    ✗ Alternative format: NOT CONFIGURED
    ✓ Screen reader: compatible

    Fixes Available: 2
    [Fix All] [Details]

[3] Security
    Status: PASSED
    Checks: 4/4 passed

    ✓ Path validation: enabled
    ✓ Sound sanitization: enabled
    ✓ Permission checks: enabled
    ✓ Audit logging: enabled

Overall: 12/14 passed (86%)
[Fix Violations] [Export Report] [Configure]
```

---

## Audio Player Compatibility

Compliance doesn't play sounds:
- Configuration checking
- No player changes required

---

## Implementation

### Compliance Checking

```go
type ComplianceManager struct {
    config  *ComplianceConfig
}

func (m *ComplianceManager) Check() (*ComplianceReport, error) {
    report := &ComplianceReport{
        Timestamp: time.Now(),
        Results:   make(map[string]*StandardResult),
    }

    passed := 0
    total := 0

    for _, standard := range m.config.Standards {
        if !standard.Enabled {
            continue
        }

        result := m.checkStandard(standard)
        report.Results[standard.ID] = result

        for _, check := range result.Checks {
            total++
            if check.Status == "pass" {
                passed++
            }
        }
    }

    report.TotalChecks = total
    report.PassedChecks = passed
    report.FailedChecks = total - passed
    report.PassRate = float64(passed) / float64(total) * 100

    return report, nil
}

func (m *ComplianceManager) checkStandard(standard *Standard) *StandardResult {
    result := &StandardResult{
        StandardID:   standard.ID,
        StandardName: standard.Name,
        Checks:       []CheckResult{},
    }

    for _, rule := range standard.Rules {
        checkResult := m.runCheck(rule)
        result.Checks = append(result.Checks, checkResult)
    }

    // Determine status
    failed := 0
    for _, check := range result.Checks {
        if check.Status == "fail" {
            failed++
        }
    }

    if failed == 0 {
        result.Status = "PASSED"
    } else if float64(failed)/float64(len(result.Checks)) < 0.5 {
        result.Status = "WARNINGS"
    } else {
        result.Status = "FAILED"
    }

    return result
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Compliance checking
- [Accessibility feature](features/122-feat-sound-accessibility.md) - Accessibility compliance

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
