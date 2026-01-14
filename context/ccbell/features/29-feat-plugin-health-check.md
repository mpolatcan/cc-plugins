# Feature: Plugin Health Check

Diagnose ccbell installation and dependencies.

## Summary

Comprehensive diagnostic tool to verify ccbell is properly installed and all dependencies are working.

## Motivation

- Debug installation issues
- Verify audio player availability
- Check configuration validity
- Support troubleshooting

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Health Check Components

The current `hooks/hooks.json` and script already perform some checks.

**Key Finding**: A dedicated health check command can validate all components.

### Check List

| Check | Description | Failure Impact |
|-------|-------------|----------------|
| Binary exists | ccbell binary present | Critical |
| Binary executable | Has execute permissions | Critical |
| Audio player | At least one player available | Critical |
| Config valid | JSON parse and validate | Warning |
| Sound files | Bundled sounds exist | Warning |
| Cache writable | Can create temp files | Warning |

### Implementation

```go
type HealthCheck struct {
    Checks []CheckFunc
}

type CheckResult struct {
    Name    string
    Status  Status
    Message string
}

type Status string

const (
    StatusOK      Status = "ok"
    StatusWarning Status = "warning"
    StatusError   Status = "error"
)

func (h *HealthCheck) Run() []CheckResult {
    results := []CheckResult{}
    for _, check := range h.Checks {
        results = append(results, check())
    }
    return results
}

func checkBinary() CheckResult {
    _, err := exec.LookPath("ccbell")
    if err != nil {
        return CheckResult{"binary", StatusError, "ccbell not in PATH"}
    }
    return CheckResult{"binary", StatusOK, "ccbell found in PATH"}
}

func checkAudioPlayer() CheckResult {
    player := audio.NewPlayer("")
    if player.HasAudioPlayer() {
        return CheckResult{"audio_player", StatusOK, "Audio player available"}
    }
    return CheckResult{"audio_player", StatusError, "No audio player found"}
}
```

### Output Format

```
$ ccbell --health
=== ccbell Health Check ===

[OK]   Binary: ccbell found at /usr/local/bin/ccbell
[OK]   Version: 0.2.30
[OK]   Audio Player: mpv available
[OK]   Config: Valid JSON, 4 events configured
[OK]   Sound Files: All bundled sounds present
[OK]   Cache: Writable

=== Summary ===
Checks: 6
Passed: 6
Warnings: 0
Errors: 0

Status: HEALTHY
```

### Commands

```bash
/ccbell:validate        # Existing command
/ccbell:health          # New comprehensive check
/ccbell:health --json   # JSON output for scripts
/ccbell:health --verbose  # Detailed output
```

---

## Audio Player Compatibility

Health check validates audio player availability:
- Checks for afplay (macOS)
- Checks for mpv/paplay/aplay/ffplay (Linux)
- Does not play sounds

---

## Implementation

### Health Check Function

```go
func RunHealthCheck(pluginRoot, homeDir string) []CheckResult {
    checks := []CheckFunc{
        checkBinary,
        checkVersion,
        checkAudioPlayer,
        checkConfig,
        checkSoundFiles,
        checkCacheDir,
    }

    hc := &HealthCheck{Checks: checks}
    return hc.Run()
}
```

### Exit Codes

```go
// Exit codes for scripting
const (
    ExitHealthy   = 0
    ExitWarning   = 1
    ExitError     = 2
)
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Audio player detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L217-L235) - HasAudioPlayer method
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) - Validate method
- [Script validation](https://github.com/mpolatcan/ccbell/blob/main/scripts/ccbell.sh) - Installation checks

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Full checks |
| Linux | ✅ Supported | Full checks |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
