# Feature: Sound Event Sound Test

Test and validate sound configurations.

## Summary

Comprehensive testing for sound configurations and audio playback.

## Motivation

- Configuration validation
- Audio troubleshooting
- Quality assurance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Test Types

| Test | Description | Example |
|------|-------------|---------|
| Config | Validate config file | JSON valid |
| Sounds | Check sound files | Files exist |
| Audio | Test audio playback | Play test sound |
| Player | Verify player works | afplay works |
| Full | Run all tests | Complete check |

### Configuration

```go
type SoundTestConfig struct {
    Enabled       bool              `json:"enabled"`
    TestSound     string            `json:"test_sound"` // bundled:stop or custom
    AutoTest      bool              `json:"auto_test"` // Test on startup
    StrictMode    bool              `json:"strict_mode"` // Fail on warnings
    ReportFormat  string            `json:"report_format"` // "text", "json"
}

type TestResult struct {
    TestName   string
    Status     string // "pass", "fail", "warning", "skip"
    Message    string
    Details    map[string]interface{}
}

type TestReport struct {
    Timestamp   time.Time
    Duration    time.Duration
    TotalTests  int
    Passed      int
    Failed      int
    Warnings    int
    Skipped     int
    Results     []*TestResult
}
```

### Commands

```bash
/ccbell:test                      # Run all tests
/ccbell:test config               # Test configuration
/ccbell:test sounds               # Test sound files
/ccbell:test audio                # Test audio playback
/ccbell:test player               # Test audio player
/ccbell:test event stop           # Test specific event
/ccbell:test all --json           # Full test with JSON output
/ccbell:test --strict             # Strict mode
/ccbell:test report               # Show last test report
```

### Output

```
$ ccbell:test

=== Sound Event Test ===

Running comprehensive tests...

[1/5] Configuration Test
  Status: PASSED
  Details: Config file valid
  Duration: 12ms

[2/5] Sound Files Test
  Status: PASSED
  Details:
    - bundled:stop ✓
    - bundled:permission_prompt ✓
    - bundled:idle_prompt ✓
    - bundled:subagent ✓
  Duration: 45ms

[3/5] Audio Player Test
  Status: PASSED
  Details:
    - Player: afplay
    - Version: macOS built-in
    - Latency: 23ms
  Duration: 150ms

[4/5] Playback Test
  Status: PASSED
  Details:
    - Sound: bundled:stop
    - Duration: ~2s
    - Volume: 0.5
  Duration: 2100ms

[5/5] Event Configuration Test
  Status: PASSED
  Details: All 4 events configured

========================================
SUMMARY: 5/5 PASSED (2.3s)
Status: HEALTHY

[Run Again] [Report] [Fix Issues]
```

---

## Audio Player Compatibility

Sound test uses all audio players:
- Tests actual playback
- No player changes required

---

## Implementation

### Sound Test Manager

```go
type SoundTestManager struct {
    config   *SoundTestConfig
    player   *audio.Player
}

func (m *SoundTestManager) RunAll() (*TestReport, error) {
    report := &TestReport{
        Timestamp: time.Now(),
        Results:   []*TestResult{},
    }

    start := time.Now()

    // Run tests
    report.Results = append(report.Results, m.testConfig())
    report.Results = append(report.Results, m.testSounds())
    report.Results = append(report.Results, m.testPlayer())
    report.Results = append(report.Results, m.testPlayback())
    report.Results = append(report.Results, m.testEvents())

    report.Duration = time.Since(start)

    // Count results
    for _, result := range report.Results {
        report.TotalTests++
        switch result.Status {
        case "pass":
            report.Passed++
        case "fail":
            report.Failed++
        case "warning":
            report.Warnings++
        case "skip":
            report.Skipped++
        }
    }

    return report, nil
}

func (m *SoundTestManager) testConfig() *TestResult {
    result := &TestResult{
        TestName: "Configuration Test",
        Status:   "pass",
        Details:  make(map[string]interface{}),
    }

    homeDir, err := os.UserHomeDir()
    if err != nil {
        result.Status = "fail"
        result.Message = "Cannot find home directory"
        return result
    }

    configPath := filepath.Join(homeDir, ".claude", "ccbell.config.json")

    // Check if config exists
    if _, err := os.Stat(configPath); os.IsNotExist(err) {
        result.Status = "warning"
        result.Message = "Config file not found, using defaults"
        result.Details["config_path"] = configPath
        return result
    }

    // Validate JSON
    data, err := os.ReadFile(configPath)
    if err != nil {
        result.Status = "fail"
        result.Message = fmt.Sprintf("Cannot read config: %v", err)
        return result
    }

    var cfg config.Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        result.Status = "fail"
        result.Message = fmt.Sprintf("Invalid JSON: %v", err)
        return result
    }

    // Validate config
    if err := cfg.Validate(); err != nil {
        result.Status = "fail"
        result.Message = fmt.Sprintf("Validation error: %v", err)
        return result
    }

    result.Message = "Config file valid"
    result.Details["config_path"] = configPath

    return result
}

func (m *SoundTestManager) testSounds() *TestResult {
    result := &TestResult{
        TestName: "Sound Files Test",
        Status:   "pass",
        Details:  make(map[string]interface{}),
    }

    soundsDir := filepath.Join(m.player.PluginRoot(), "sounds")
    sounds := []string{"stop", "permission_prompt", "idle_prompt", "subagent"}

    var found, missing int
    soundStatus := make(map[string]string)

    for _, sound := range sounds {
        path := filepath.Join(soundsDir, sound+".aiff")
        if _, err := os.Stat(path); err == nil {
            found++
            soundStatus[sound] = "✓"
        } else {
            missing++
            soundStatus[sound] = "✗"
        }
    }

    result.Details["sounds"] = soundStatus

    if missing > 0 {
        result.Status = "fail"
        result.Message = fmt.Sprintf("%d sound(s) missing", missing)
    } else {
        result.Message = fmt.Sprintf("All %d sounds found", found)
    }

    return result
}

func (m *SoundTestManager) testPlayer() *TestResult {
    result := &TestResult{
        TestName: "Audio Player Test",
        Status:   "pass",
        Details:  make(map[string]interface{}),
    }

    platform := m.player.Platform()
    result.Details["platform"] = string(platform)

    switch platform {
    case "darwin":
        if _, err := exec.LookPath("afplay"); err != nil {
            result.Status = "fail"
            result.Message = "afplay not found"
            return result
        }
        result.Details["player"] = "afplay"

    case "linux":
        found := false
        for _, player := range []string{"mpv", "paplay", "aplay", "ffplay"} {
            if _, err := exec.LookPath(player); err == nil {
                result.Details["player"] = player
                found = true
                break
            }
        }
        if !found {
            result.Status = "fail"
            result.Message = "No audio player found"
            return result
        }

    default:
        result.Status = "fail"
        result.Message = fmt.Sprintf("Unsupported platform: %s", platform)
        return result
    }

    result.Message = fmt.Sprintf("Using %s on %s", result.Details["player"], platform)

    return result
}

func (m *SoundTestManager) testPlayback() *TestResult {
    result := &TestResult{
        TestName: "Playback Test",
        Status:   "pass",
        Details:  make(map[string]interface{}),
    }

    soundPath := m.player.GetFallbackPath("stop")
    if soundPath == "" {
        result.Status = "fail"
        result.Message = "No test sound available"
        return result
    }

    // Play sound and measure latency
    start := time.Now()
    err := m.player.Play(soundPath, 0.5)
    latency := time.Since(start)

    if err != nil {
        result.Status = "fail"
        result.Message = fmt.Sprintf("Playback failed: %v", err)
        return result
    }

    result.Details["sound"] = soundPath
    result.Details["latency_ms"] = latency.Milliseconds()
    result.Message = "Test sound played successfully"

    return result
}

func (m *SoundTestManager) testEvents() *TestResult {
    result := &TestResult{
        TestName: "Event Configuration Test",
        Status:   "pass",
        Details:  make(map[string]interface{}),
    }

    expected := []string{"stop", "permission_prompt", "idle_prompt", "subagent"}

    for _, event := range expected {
        if _, ok := config.ValidEvents[event]; !ok {
            result.Status = "fail"
            result.Message = fmt.Sprintf("Missing event: %s", event)
            return result
        }
    }

    result.Details["events"] = expected
    result.Message = "All events configured"

    return result
}

func (m *SoundTestManager) formatReport(report *TestReport) string {
    var b strings.Builder

    fmt.Fprintf(&b, "=== Sound Event Test ===\n\n")
    fmt.Fprintf(&b, "Timestamp: %s\n", report.Timestamp.Format(time.RFC3339))
    fmt.Fprintf(&b, "Duration: %v\n\n", report.Duration)

    for i, result := range report.Results {
        icon := "✓"
        if result.Status == "fail" {
            icon = "✗"
        } else if result.Status == "warning" {
            icon = "!"
        }

        fmt.Fprintf(&b, "[%d/%d] %s %s\n", i+1, report.TotalTests, icon, result.TestName)
        fmt.Fprintf(&b, "  Status: %s\n", strings.ToUpper(result.Status))
        fmt.Fprintf(&b, "  %s\n\n", result.Message)
    }

    fmt.Fprintf(&b, "========================================\n")
    fmt.Fprintf(&b, "SUMMARY: %d/%d PASSED (%v)\n", report.Passed, report.TotalTests, report.Duration)

    if report.Failed > 0 {
        fmt.Fprintf(&b, "Status: ISSUES FOUND (%d failed)\n", report.Failed)
    } else {
        fmt.Fprintf(&b, "Status: HEALTHY\n")
    }

    return b.String()
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

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Playback testing
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config validation
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Tests afplay |
| Linux | ✅ Supported | Tests mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
