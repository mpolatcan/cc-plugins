# Feature: Config Validation ✅

## Summary

Check config file for JSON syntax errors and schema issues before applying changes.

## Benefit

- **Faster debugging**: Clear error messages pinpoint exactly what's wrong
- **Prevention over recovery**: Catches errors before notification failures
- **Better onboarding**: Immediate feedback on configuration mistakes
- **Reduced support burden**: Self-documenting validation reduces questions

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Config Management |

## Technical Feasibility

### Validation Levels

| Level | Checks | Example Errors |
|-------|--------|----------------|
| Syntax | Valid JSON | Trailing commas, unclosed braces |
| Schema | Required fields | Missing enabled field |
| Values | Valid ranges | Volume > 1.0, negative cooldown |
| References | Profile exists | Non-existent profile referenced |

### Implementation

```go
type ValidationResult struct {
    Level   string   // "error", "warning", "info"
    Message string
    Line    int
    Field   string
}

func ValidateFile(path string) ([]ValidationResult, error) {
    data, err := os.ReadFile(path)
    if err != nil { return nil, fmt.Errorf("read error: %w", err) }

    // Syntax validation (JSON)
    var cfg map[string]interface{}
    if err := json.Unmarshal(data, &cfg); err != nil {
        return []ValidationResult{{
            Level:   "error",
            Message: fmt.Sprintf("Invalid JSON: %v", err),
        }}, nil
    }

    // Schema + Value + Reference validation
    results := validateSchema(cfg)
    results = append(results, validateValues(cfg)...)
    results = append(results, validateReferences(cfg)...)

    return results, nil
}
```

### Commands

```bash
/ccbell:validate config.json              # Validate file
/ccbell:validate                          # Validate active config
/ccbell:validate --json                   # JSON output
/ccbell:validate --strict                 # Warnings as errors
```

### Output Examples

**Human:**
```
$ ccbell:validate

[ERROR]   Field: events.stop.volume
           Value: 1.5 exceeds maximum 1.0

✓ Found 1 error, 1 warning
```

**JSON:**
```json
{
  "valid": false,
  "errors": 1,
  "warnings": 1,
  "results": [...]
}
```

## Configuration

No config changes - enhances existing validation.

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Enhance `Validate()` function |
| **Core Logic** | Add | `ValidateFile()` public function |
| **Commands** | Modify | Add `--json`, `--strict` flags |
| **New File** | Add | `internal/config/validator.go` |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/validate.md** | Update | Add syntax/schema examples |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175)
- [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51)
- [Time format](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L54-L54)

---

[Back to Feature Index](index.md)
