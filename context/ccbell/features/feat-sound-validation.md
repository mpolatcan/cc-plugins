# Feature: Sound Validation 🔎

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Check sound files and configuration for issues before use.

## Motivation

- Detect broken sound files
- Find missing sounds
- Verify configuration validity

---

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

---

## Technical Feasibility

### Validation Checks

| Check | Description | Severity |
|-------|-------------|----------|
| Sound exists | File path is valid | Error |
| Sound playable | File can be decoded | Error |
| Format valid | Supported format | Warning |
| Volume valid | Volume in range | Error |
| Event mapped | Event has sound | Warning |
| Duplicate sounds | Same sound for events | Info |
| Orphaned sounds | Unused custom sounds | Info |

### Implementation

```go
type ValidationResult struct {
    Valid   bool           `json:"valid"`
    Checks  []CheckResult  `json:"checks"`
    Summary *Summary       `json:"summary"`
}

type CheckResult struct {
    Check     string `json:"check"`
    Status    string `json:"status"` // pass, warn, fail
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

### Output

```
$ ccbell:validate

=== Sound Validation ===

Checking 4 events...
Checking 24 sound files...

[==============] 100% complete

Results:

Errors:
  [✗] bundled:missing.aiff - File not found
  [✗] custom:/broken.wav - Cannot be decoded

Warnings:
  [!] permission_prompt - No sound configured
  [!] custom:quiet.aiff - Volume too low (<0.1)

Info:
  [i] custom:unused.aiff - Sound not used by any event
  [i] bundled:stop - Duplicate of bundled:stop-2

Summary:
  Total: 28
  Passed: 24
  Warnings: 2
  Errors: 2

Status: FAILED
Fix 2 issues? [Yes] [No] [Details]
```

---

## Audio Player Compatibility

Validation doesn't play sounds:
- Uses ffprobe for format checking
- No player changes required

---

## Implementation

### Sound Validation

```go
func (v *Validator) ValidateSound(soundPath string) *CheckResult {
    // Check if file exists
    if _, err := os.Stat(soundPath); os.IsNotExist(err) {
        return &CheckResult{
            Check:   "sound_exists",
            Status:  "fail",
            Message: "Sound file not found",
            Sound:   soundPath,
        }
    }

    // Check if playable using ffprobe
    cmd := exec.Command("ffprobe", "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_name",
        "-of", "csv=p=0",
        soundPath)

    if err := cmd.Run(); err != nil {
        return &CheckResult{
            Check:   "sound_playable",
            Status:  "fail",
            Message: "Sound cannot be decoded",
            Sound:   soundPath,
        }
    }

    return &CheckResult{
        Check:   "sound_valid",
        Status:  "pass",
        Message: "Sound is valid",
        Sound:   soundPath,
    }
}
```

### Auto-Fix

```go
func (v *Validator) AutoFix(results []CheckResult) ([]FixResult, error) {
    fixes := []FixResult{}

    for _, result := range results {
        switch result.Check {
        case "sound_missing":
            // Set to bundled default
            fixes = append(fixes, FixResult{
                Fix:     "Use bundled default",
                Sound:   result.Sound,
                Success: true,
            })
        case "event_no_sound":
            // Enable default sound
            fixes = append(fixes, FixResult{
                Fix:     "Enable default sound",
                Event:   result.Event,
                Success: true,
            })
        }
    }

    return fixes, v.applyFixes(fixes)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffprobe | External tool | Free | Part of ffmpeg |

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Core Logic** | Add | Add `ValidateSound(path string) (bool, error)` function |
| **New File** | Add | `internal/audio/validator.go` for sound validation |
| **Commands** | Modify | Enhance `validate` command with `--sounds` flag |
| **Config** | No change | Uses existing config |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/validate.md** | Update | Add sound validation section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/audio/validator.go:**
```go
type SoundValidator struct{}

func (v *SoundValidator) Validate(path string) (ValidationResult, error) {
    // Check file exists
    if _, err := os.Stat(path); os.IsNotExist(err) {
        return ValidationResult{
            Valid:   false,
            Error:   "file not found",
            Path:    path,
        }, nil
    }

    // Use ffprobe to validate format
    cmd := exec.Command("ffprobe", "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,duration",
        "-of", "json", path)

    output, err := cmd.Output()
    if err != nil {
        return ValidationResult{
            Valid:  false,
            Error:  fmt.Sprintf("ffprobe failed: %v", err),
            Path:   path,
        }, nil
    }

    var result ffprobeResult
    json.Unmarshal(output, &result)

    if len(result.Streams) == 0 {
        return ValidationResult{
            Valid:  false,
            Error:  "no audio stream found",
            Path:   path,
        }, nil
    }

    return ValidationResult{
        Valid:     true,
        Codec:     result.Streams[0].CodecName,
        Duration:  result.Streams[0].Duration,
        Path:      path,
    }, nil
}

func (v *SoundValidator) ValidateAll(cfg *Config) []ValidationResult {
    var results []ValidationResult

    for event, eventCfg := range cfg.Events {
        for _, sound := range eventCfg.GetSounds() {
            result, _ := v.Validate(sound)
            result.Event = event
            results = append(results, result)
        }
    }

    return results
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    validateCmd := flag.NewFlagSet("validate", flag.ExitOnError)
    soundsOnly := validateCmd.Bool("sounds", false, "Validate sound files only")

    validateCmd.Parse(os.Args[2:])

    if *soundsOnly {
        cfg := config.Load(homeDir)
        validator := audio.NewValidator()
        results := validator.ValidateAll(cfg)

        for _, r := range results {
            if r.Valid {
                fmt.Printf("[OK] %s (%s, %s)\n", r.Event, r.Codec, r.Duration)
            } else {
                fmt.Printf("[FAIL] %s: %s - %s\n", r.Event, r.Path, r.Error)
            }
        }
    }
}
```

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffprobe available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event configuration

### Research Sources

- [ffprobe error detection](https://ffmpeg.org/ffprobe.html)

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/validate.md` with sound validation |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.2.31+
- **Config Schema Change**: No schema change, enhances validate command
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/validate.md` (add sound validation section)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag
- **External Dependency**: Uses `ffprobe` (part of ffmpeg) for format validation

### Implementation Checklist

- [ ] Update `commands/validate.md` with sound validation commands
- [ ] Document ffprobe requirement
- [ ] When ccbell v0.2.31+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe |
| Linux | ✅ Supported | Via ffprobe |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
