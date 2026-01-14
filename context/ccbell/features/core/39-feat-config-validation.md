# Feature: Config Syntax Validation

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Check config file for JSON syntax errors and schema issues before applying changes.

## Motivation

- Prevent bad configs from breaking ccbell
- Provide clear error messages
- Validate before saving

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---


## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

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
    Line    int      // Line number (if available)
    Field   string   // Config path
}

func ValidateConfigFile(path string) ([]ValidationResult, error) {
    results := []ValidationResult{}

    // 1. Read file
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("cannot read file: %w", err)
    }

    // 2. Syntax validation (JSON)
    var cfg map[string]interface{}
    if err := json.Unmarshal(data, &cfg); err != nil {
        return []ValidationResult{{
            Level:   "error",
            Message: fmt.Sprintf("Invalid JSON: %v", err),
        }}, nil
    }

    // 3. Schema validation
    results = append(results, validateSchema(cfg)...)

    // 4. Value validation
    results = append(results, validateValues(cfg)...)

    // 5. Reference validation
    results = append(results, validateReferences(cfg)...)

    return results, nil
}
```

### Output Formats

**Human:**
```
$ ccbell:validate config.json

Validating: config.json

[ERROR]   Field: events.stop.volume
           Value: 1.5 is greater than maximum 1.0

[WARNING] Field: profiles.missing.events
           Profile 'missing' referenced but not defined

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

### Commands

```bash
/ccbell:validate config.json              # Validate file
/ccbell:validate                          # Validate active config
/ccbell:validate config.json --json       # JSON output
/ccbell:validate --strict                 # Strict mode (warnings as errors)
```

---

## Audio Player Compatibility

Config validation doesn't interact with audio playback:
- Purely config analysis
- No player changes required
- Prevents errors before playback

---

## Implementation

### Schema Validation

```go
func validateSchema(cfg map[string]interface{}) []ValidationResult {
    results := []ValidationResult{}

    // Check required fields
    if _, ok := cfg["enabled"]; !ok {
        results = append(results, ValidationResult{
            Level:   "warning",
            Message: "Missing 'enabled' field, defaulting to true",
            Field:   "enabled",
        })
    }

    // Check events structure
    if events, ok := cfg["events"].(map[string]interface{}); ok {
        for eventName := range events {
            if !config.ValidEvents[eventName] {
                results = append(results, ValidationResult{
                    Level:   "error",
                    Message: fmt.Sprintf("Unknown event type: %s", eventName),
                    Field:   "events." + eventName,
                })
            }
        }
    }

    return results
}
```

### Value Ranges

```go
func validateValues(cfg map[string]interface{}) []ValidationResult {
    results := []ValidationResult{}

    // Volume range: 0.0 - 1.0
    // Cooldown: >= 0
    // Time format: HH:MM
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---


---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### ccbell Implementation Research

- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) - Existing validation pattern
- [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) - Event validation
- [Time format](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L54-L54) - Time validation regex

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
