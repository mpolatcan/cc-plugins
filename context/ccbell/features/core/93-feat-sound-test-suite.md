# Feature: Sound Test Suite

Automated tests for sound configurations.

## Summary

Run automated tests to verify sound configurations work correctly.

## Motivation

- Validate configurations
- Detect regressions
- Ensure cross-platform compatibility

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Test Types

| Test | Description | Expected Result |
|------|-------------|-----------------|
| Playback | Test sound plays | Sound plays successfully |
| Volume | Test volume levels | Volume changes applied |
| Format | Test format support | All formats playable |
| Cooldown | Test cooldown behavior | Notifications suppressed |
| Quiet hours | Test quiet hours | Notifications suppressed |
| Event routing | Test event mapping | Correct sound played |

### Implementation

```go
type TestConfig struct {
    Events      []string `json:"events"`       // events to test
    VolumeTest  bool     `json:"volume_test"`  // test volume levels
    FormatTest  bool     `json:"format_test"`  // test all formats
    TimeoutSec  int      `json:"timeout_sec"`  // test timeout
    SilentMode  bool     `json:"silent_mode"`  // don't play sounds
}

type TestResult struct {
    TestName   string        `json:"test_name"`
    Status     string        `json:"status"` // pass, fail, skip
    Duration   time.Duration `json:"duration"`
    Message    string        `json:"message"`
    Details    []string      `json:"details,omitempty"`
}

type TestSuiteResult struct {
    TotalTests  int             `json:"total_tests"`
    Passed      int             `json:"passed"`
    Failed      int             `json:"failed"`
    Skipped     int             `json:"skipped"`
    Results     []*TestResult   `json:"results"`
    Platform    string          `json:"platform"`
    Timestamp   time.Time       `json:"timestamp"`
}
```

### Commands

```bash
/ccbell:test                  # Run all tests
/ccbell:test playback         # Test playback
/ccbell:test volume           # Test volume levels
/ccbell:test format           # Test format support
/ccbell:test stop             # Test specific event
/ccbell:test --silent         # Don't play sounds
/ccbell:test --json           # JSON output
/ccbell:test --report         # Generate report
/ccbell:test setup            # Test setup validity
```

### Output

```
$ ccbell:test

=== Sound Test Suite ===

Platform: macOS (afplay)
Tests: 8

[==============] 100% complete

Results:

[✓] Config Valid
    Duration: 12ms
    Configuration is valid

[✓] Sound Paths
    Duration: 45ms
    All 24 sound paths resolve correctly

[✓] bundled:stop Playback
    Duration: 1.234s
    Sound plays successfully

[✓] bundled:permission_prompt Playback
    Duration: 0.567s
    Sound plays successfully

[✓] Volume Range
    Duration: 890ms
    Volume 0.1, 0.5, 1.0 all work

[✓] Cooldown Behavior
    Duration: 100ms
    Cooldown suppresses repeat notifications

[✓] Quiet Hours
    Duration: 50ms
    Quiet hours correctly suppresses

[✓] Format Support
    Duration: 2.1s
    AIFF, WAV, MP3, FLAC all playable

Summary:
  Total: 8
  Passed: 8
  Failed: 0
  Skipped: 0

Status: ALL TESTS PASSED
```

---

## Audio Player Compatibility

Test suite uses existing audio player:
- Tests `player.Play()` functionality
- Same format support
- Can use silent mode for non-audio tests

---

## Implementation

### Playback Test

```go
func (s *TestSuite) testPlayback(soundPath string, timeout time.Duration) *TestResult {
    start := time.Now()

    player := audio.NewPlayer(s.pluginRoot)

    done := make(chan error, 1)
    go func() {
        err := player.Play(soundPath, 0.5)
        done <- err
    }()

    select {
    case err := <-done:
        return &TestResult{
            TestName: fmt.Sprintf("Playback: %s", filepath.Base(soundPath)),
            Status:   "pass",
            Duration: time.Since(start),
            Message:  "Sound plays successfully",
        }
    case <-time.After(timeout):
        return &TestResult{
            TestName: fmt.Sprintf("Playback: %s", filepath.Base(soundPath)),
            Status:   "fail",
            Duration: time.Since(start),
            Message:  "Playback timed out",
        }
    }
}
```

### Silent Mode

```go
func (s *TestSuite) runSilentTests() []*TestResult {
    results := []*TestResult{}

    // Test config validity
    results = append(results, s.testConfigValidity())

    // Test sound paths exist
    results = append(results, s.testSoundPaths())

    // Test event configuration
    results = append(results, s.testEventConfig())

    return results
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config validation
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event validation

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go + afplay |
| Linux | ✅ Supported | Pure Go + mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
