# Feature: Sound Event Test Results Monitor

Play sounds for test execution events.

## Summary

Monitor test execution (unit tests, integration tests), playing sounds when tests pass, fail, or have coverage changes.

## Motivation

- Test feedback without watching
- Coverage threshold alerts
- CI/CD integration
- Development workflow

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Test Events

| Event | Description | Example |
|-------|-------------|---------|
| Tests Started | Test suite began | `go test` started |
| All Tests Passed | 100% pass rate | 0 failures |
| Some Failed | Partial pass rate | 2 of 100 failed |
| All Failed | Complete failure | 100% failure |
| Coverage Up | Coverage improved | +5% coverage |
| Coverage Down | Coverage dropped | -5% coverage |
| Coverage Low | Below threshold | < 80% coverage |

### Configuration

```go
type TestMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchProjects  []*TestProject    `json:"watch_projects"`
    CoverageThreshold float64        `json:"coverage_threshold"` // 80 default
    Sounds         map[string]string `json:"sounds"`
}

type TestProject struct {
    Name       string  `json:"name"`
    Path       string  `json:"path"`
    Command    string  `json:"command"` // "go test ./...", "npm test"
    Sound      string  `json:"sound"`
}

type TestResult struct {
    Project    string
    Total      int
    Passed     int
    Failed     int
    Skipped    int
    Coverage   float64
    Duration   time.Duration
    Status     string // "passed", "failed", "partial"
}
```

### Commands

```bash
/ccbell:test-monitor status         # Show test status
/ccbell:test-monitor add /path --name "MyProject"
/ccbell:test-monitor remove "MyProject"
/ccbell:test-monitor coverage <percent>
/ccbell:test-monitor sound passed <sound>
/ccbell:test-monitor sound failed <sound>
/ccbell:test-monitor test          # Test sounds
```

### Output

```
$ ccbell:test-monitor status

=== Sound Event Test Results Monitor ===

Status: Enabled
Coverage Threshold: 80%

Watched Projects: 3

[1] backend-api
    Path: /Users/dev/backend-api
    Command: go test ./... -v
    Last Run: 5 min ago
    Status: ALL PASSED
    Tests: 150 passed, 0 failed, 0 skipped
    Coverage: 85%
    Duration: 12s
    Sound: bundled:stop
    [Edit] [Remove]

[2] frontend-app
    Path: /Users/dev/frontend-app
    Command: npm test
    Last Run: 1 hour ago
    Status: SOME FAILED
    Tests: 45 passed, 3 failed, 2 skipped
    Coverage: 72%
    Duration: 45s
    Sound: bundled:stop
    [Edit] [Remove]

[3] mobile-app
    Path: /Users/dev/mobile-app
    Command: ./gradlew test
    Last Run: 2 hours ago
    Status: ALL PASSED
    Tests: 200 passed, 0 failed
    Coverage: 91%
    Duration: 180s
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] backend-api: ALL PASSED (5 min ago)
  [2] frontend-app: SOME FAILED (1 hour ago)
  [3] mobile-app: ALL PASSED (2 hours ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Test monitoring doesn't play sounds directly:
- Monitoring feature using process execution
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Test Monitor

```go
type TestMonitor struct {
    config       *TestMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastCoverage map[string]float64
    lastResult   map[string]*TestResult
}

func (m *TestMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastCoverage = make(map[string]float64)
    m.lastResult = make(map[string]*TestResult)
}

func (m *TestMonitor) Stop() {
    m.running = false
    close(m.stopCh)
}

func (m *TestMonitor) runTests(project *TestProject) *TestResult {
    result := &TestResult{
        Project: project.Name,
        Status:  "started",
    }

    start := time.Now()

    // Run tests with coverage
    cmd := exec.Command("bash", "-c", project.Command)
    cmd.Dir = project.Path

    output, err := cmd.CombinedOutput()
    resultStr := string(output)

    // Parse output based on test framework
    result = m.parseTestOutput(project.Name, resultStr)
    result.Duration = time.Since(start)

    m.lastResult[project.Name] = result

    // Check coverage changes
    if result.Coverage > 0 {
        lastCoverage := m.lastCoverage[project.Name]
        m.lastCoverage[project.Name] = result.Coverage

        if lastCoverage > 0 {
            if result.Coverage >= lastCoverage+5 {
                m.playSound(project, "coverage_up")
            } else if result.Coverage <= lastCoverage-5 {
                m.playSound(project, "coverage_down")
            }
        }

        // Check coverage threshold
        if result.Coverage < m.config.CoverageThreshold {
            if lastCoverage >= m.config.CoverageThreshold {
                m.playSound(project, "coverage_low")
            }
        }
    }

    // Play sound based on test result
    m.playSound(project, result.Status)

    return result
}

func (m *TestMonitor) parseTestOutput(name, output string) *TestResult {
    result := &TestResult{Project: name}

    // Try to detect test framework and parse output

    // Go test format: "ok    package  1.234s" or "FAIL package"
    if strings.Contains(output, "ok  ") || strings.Contains(output, "FAIL") {
        return m.parseGoTest(output, result)
    }

    // Jest/Mocha format: "Tests: 5 passed, 1 failed"
    if strings.Contains(output, "Tests:") || strings.Contains(output, "Test Suites:") {
        return m.parseJestTest(output, result)
    }

    // pytest format: "3 passed, 1 failed in 0.12s"
    if strings.Contains(output, "passed") || strings.Contains(output, "failed") {
        return m.parsePyTest(output, result)
    }

    // JUnit XML format
    if strings.Contains(output, "<testsuites") {
        return m.parseJUnitXML(output, result)
    }

    result.Status = "unknown"
    return result
}

func (m *TestMonitor) parseGoTest(output string, result *TestResult) *TestResult {
    // Parse: "ok    github.com/user/repo  1.234s"
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "ok  ") {
            result.Status = "passed"
            result.Passed = 1 // Go doesn't show counts in summary
            result.Total = 1
        } else if strings.HasPrefix(line, "FAIL") {
            result.Status = "failed"
            result.Failed = 1
        }
    }
    return result
}

func (m *TestMonitor) parseJestTest(output string, result *TestResult) *TestResult {
    // Parse: "Tests: 5 passed, 1 failed, 2 skipped (5s)"
    testsMatch := regexp.MustCompile(`Tests?:\s*(\d+)\s+passed.*?(\d+)\s+failed`).FindStringSubmatch(output)
    if testsMatch != nil {
        passed, _ := strconv.Atoi(testsMatch[1])
        failed, _ := strconv.Atoi(testsMatch[2])
        result.Passed = passed
        result.Failed = failed
        result.Total = passed + failed

        if failed > 0 {
            result.Status = "partial"
        } else {
            result.Status = "passed"
        }
    }

    // Parse coverage
    covMatch := regexp.MustCompile(`Coverage:\s*([\d.]+)%`).FindStringSubmatch(output)
    if covMatch != nil {
        coverage, _ := strconv.ParseFloat(covMatch[1], 64)
        result.Coverage = coverage
    }

    return result
}

func (m *TestMonitor) parsePyTest(output string, result *TestResult) *TestResult {
    // Parse: "3 passed, 1 failed in 0.12s"
    match := regexp.MustCompile(`(\d+)\s+passed.*?(\d+)\s+failed`).FindStringSubmatch(output)
    if match != nil {
        passed, _ := strconv.Atoi(match[1])
        failed, _ := strconv.Atoi(match[2])
        result.Passed = passed
        result.Failed = failed
        result.Total = passed + failed

        if failed > 0 {
            result.Status = "partial"
        } else {
            result.Status = "passed"
        }
    }

    // Parse coverage
    covMatch := regexp.MustCompile(`Coverage:\s*([\d.]+)%`).FindStringSubmatch(output)
    if covMatch != nil {
        coverage, _ := strconv.ParseFloat(covMatch[1], 64)
        result.Coverage = coverage
    }

    return result
}

func (m *TestMonitor) parseJUnitXML(output string, result *TestResult) *TestResult {
    // Simple JUnit XML parsing
    passedMatch := regexp.MustCompile(`tests="(\d+)"`).FindStringSubmatch(output)
    failuresMatch := regexp.MustCompile(`failures="(\d+)"`).FindStringSubmatch(output)

    if passedMatch != nil {
        total, _ := strconv.Atoi(passedMatch[1])
        result.Total = total
    }

    if failuresMatch != nil {
        failed, _ := strconv.Atoi(failuresMatch[1])
        result.Failed = failed
        result.Passed = result.Total - failed

        if failed > 0 {
            result.Status = "partial"
        } else {
            result.Status = "passed"
        }
    }

    return result
}

func (m *TestMonitor) playSound(project *TestProject, event string) {
    sound := project.Sound
    if sound == "" {
        sound = m.config.Sounds[event]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| exec | Go Stdlib | Free | Process execution |
| regexp | Go Stdlib | Free | Output parsing |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses exec and parsing |
| Linux | Supported | Uses exec and parsing |
| Windows | Not Supported | ccbell only supports macOS/Linux |
