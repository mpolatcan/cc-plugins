# Feature: CLI Color Output

Colored terminal output for better readability.

## Summary

Add color to command-line output for improved readability and visual feedback.

## Motivation

- Better visual distinction
- Easier to scan output
- Modern CLI experience

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Color Support

| Platform | Terminal Support | Library |
|----------|------------------|---------|
| macOS | Most terminals | ✅ |
| Linux | Most terminals | ✅ |
| TTY | Limited | ⚠️ Graceful fallback |

### Implementation

```go
import "github.com/fatih/color"

type OutputStyle struct {
    Success *color.Color
    Error   *color.Color
    Warning *color.Color
    Info    *color.Color
    Header  *color.Color
    Muted   *color.Color
}

var styles = OutputStyle{
    Success: color.New(color.FgGreen, color.Bold),
    Error:   color.New(color.FgRed, color.Bold),
    Warning: color.New(color.FgYellow, color.Bold),
    Info:    color.New(color.FgBlue),
    Header:  color.New(color.FgCyan, color.Bold),
    Muted:   color.New(color.FgWhite),
}
```

### Colored Output

```go
func printStatus(healthy bool) {
    if healthy {
        styles.Success.Println("✓ Status: HEALTHY")
    } else {
        styles.Error.Println("✗ Status: ISSUES FOUND")
    }
}

func printEventStatus(name string, enabled bool) {
    prefix := "✓"
    statusColor := styles.Success
    if !enabled {
        prefix = "✗"
        statusColor = styles.Error
    }
    statusColor.Printf("  %s %s\n", prefix, name)
}

func printHeader(text string) {
    styles.Header.Println("\n=== " + text + " ===")
}
```

### Configuration

```json
{
  "cli": {
    "colors": {
      "enabled": true,
      "force": false  // Force colors even without TTY
    }
  }
}
```

### Commands

```bash
/ccbell:status              # Colored status
/ccbell:validate            # Colored validation
/ccbell:test all            # Colored test results
/ccbell:status --no-color   # Disable colors
ccbell stop --dry-run       # Colored dry-run output
```

### Output Example

```
$ ccbell status

=== ccbell Status ===

✓ Binary: ccbell v0.2.30
✓ Audio Player: mpv available
✓ Config: Valid
✓ Sounds: 4/4 present

Status: HEALTHY

$ ccbell validate

=== Validation ===

✓ Audio player found (mpv)
✓ Config valid (4 events)
✓ All bundled sounds present

Passed: 3
Errors: 0
```

---

## Audio Player Compatibility

Color output doesn't interact with audio playback:
- Purely terminal output
- No player changes required
- Falls back to plain text

---

## Implementation

### Auto-detection

```go
func shouldUseColors() bool {
    // Check if colors disabled
    if os.Getenv("NO_COLOR") != "" {
        return false
    }

    // Check config
    if config.NoColor {
        return false
    }

    // Check if stdout is TTY
    file, err := os.Stdout.Stat()
    if err != nil {
        return false
    }

    return (file.Mode()&os.ModeCharDevice) != 0
}
```

### Color Functions

```go
func printSuccess(msg string) {
    if shouldUseColors() {
        styles.Success.Println(msg)
    } else {
        fmt.Println("✓ " + msg)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| fatih/color | Go library | Free | Optional, graceful fallback |

---

## References

### Research Sources

- [fatih/color](https://github.com/fatih/color)
- [NO_COLOR environment variable](https://no-color.org/)

### ccbell Implementation Research

- [Main.go output](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Output patterns
- [Logger](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go) - Existing logging

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Full color support |
| Linux | ✅ Supported | Full color support |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
