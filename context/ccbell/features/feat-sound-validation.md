# Feature: Sound Validation 🔎

## Summary

Check sound files and configuration for issues before use.

## Benefit

- **Proactive issue detection**: Find problems before they affect workflow
- **Reduced debugging time**: Clear error messages point to exact issues
- **Prevents silent failures**: Users know when sounds won't play
- **Peace of mind**: Validation runs before notifications fire

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Audio |

## Technical Feasibility

### Configuration

No config changes required - CLI command based.

### Implementation

```go
type ValidationResult struct {
    Valid   bool           `json:"valid"`
    Checks  []CheckResult  `json:"checks"`
    Summary *Summary       `json:"summary"`
}

type CheckResult struct {
    Check     string `json:"check"`
    Status    string `json:"status"`
    Message   string `json:"message"`
    Sound     string `json:"sound,omitempty"`
    Event     string `json:"event,omitempty"`
}

type Summary struct {
    TotalChecks int `json:"total_checks"`
    Passed      int `json:"passed"`
    Warnings    int `json:"warnings"`
    Errors      int `json:"errors"`
}

func (v *Validator) Validate(path string) (ValidationResult, error) {
    if _, err := os.Stat(path); os.IsNotExist(err) {
        return ValidationResult{Valid: false, Error: "file not found", Path: path}, nil
    }

    cmd := exec.Command("ffprobe", "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,duration",
        "-of", "json", path)

    output, err := cmd.Output()
    if err != nil {
        return ValidationResult{Valid: false, Error: "cannot decode", Path: path}, nil
    }

    return ValidationResult{Valid: true, Path: path}, nil
}
```

### Commands

```bash
/ccbell:validate                 # Full validation
/ccbell:validate sounds          # Validate sound files
/ccbell:validate config          # Validate configuration
/ccbell:validate bundled:stop    # Validate specific sound
/ccbell:validate --json          # JSON output
/ccbell:validate --fix           # Auto-fix issues
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Core Logic** | Add | Add `ValidateSound(path string) (bool, error)` function |
| **New File** | Add | `internal/audio/validator.go` for sound validation |
| **Commands** | Modify | Enhance `validate` command with `--sounds` flag |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/validate.md** | Update | Add sound validation section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)

---

[Back to Feature Index](index.md)
