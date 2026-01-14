# Feature: Sound Event Build Monitor

Play sounds for build process events.

## Summary

Monitor build processes (Make, CMake, Gradle, npm), playing sounds when builds start, complete, or fail.

## Motivation

- Long build awareness
- CI/CD feedback
- Development workflow
- Build failure alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Build Events

| Event | Description | Example |
|-------|-------------|---------|
| Build Started | Build process began | `make` invoked |
| Build Success | Build completed | Exit code 0 |
| Build Failed | Build failed | Exit code > 0 |
| Build Warning | Compiler warnings | Non-zero warnings |
| Test Started | Tests began running | `go test` started |
| Test Success | All tests passed | 100% pass |
| Test Failed | Some tests failed | < 100% pass |

### Configuration

```go
type BuildMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchProjects []*BuildProject  `json:"watch_projects"`
    Sounds        map[string]string `json:"sounds"`
    DefaultSound  string            `json:"default_sound"`
}

type BuildProject struct {
    Name       string  `json:"name"`
    Path       string  `json:"path"`
    Command    string  `json:"command"` // "make", "npm run build", etc.
    Sound      string  `json:"sound"`
    WatchLogs  bool    `json:"watch_logs"`
}

type BuildEvent struct {
    Project   string
    Command   string
    Status    string // "started", "success", "failed", "warning"
    ExitCode  int
    Duration  time.Duration
    Output    string
}
```

### Commands

```bash
/ccbell:build status              # Show build status
/ccbell:build add /path --name "MyProject"
/ccbell:build remove "MyProject"
/ccbell:build sound success <sound>
/ccbell:build sound failed <sound>
/ccbell:build sound started <sound>
/ccbell:build test                # Test build sounds
```

### Output

```
$ ccbell:build status

=== Sound Event Build Monitor ===

Status: Enabled

Watched Projects: 3

[1] backend-api
    Path: /Users/dev/backend-api
    Command: make build
    Last Run: 5 min ago
    Status: SUCCESS
    Duration: 45s
    Sound: bundled:stop
    [Edit] [Remove]

[2] frontend-app
    Path: /Users/dev/frontend-app
    Command: npm run build
    Last Run: 1 hour ago
    Status: FAILED
    Duration: 30s
    Error: TypeScript compilation error
    Sound: bundled:stop
    [Edit] [Remove]

[3] mobile-app
    Path: /Users/dev/mobile-app
    Command: ./gradlew build
    Last Run: 2 hours ago
    Status: SUCCESS
    Duration: 180s
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] backend-api: Build SUCCESS (5 min ago)
  [2] frontend-app: Build FAILED (1 hour ago)
  [3] mobile-app: Build SUCCESS (2 hours ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Build monitoring doesn't play sounds directly:
- Monitoring feature using file watching and process execution
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Build Monitor

```go
type BuildMonitor struct {
    config      *BuildMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    watchDirs   map[string]*fsnotify.Watcher
    lastBuild   map[string]*BuildEvent
}

func (m *BuildMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastBuild = make(map[string]*BuildEvent)

    // Start directory watchers for each project
    for _, project := range m.config.WatchProjects {
        if project.WatchLogs {
            m.startLogWatcher(project)
        }
    }
}

func (m *BuildMonitor) Stop() {
    m.running = false
    for _, watcher := range m.watchDirs {
        watcher.Close()
    }
    close(m.stopCh)
}

func (m *BuildMonitor) runBuild(project *BuildProject) *BuildEvent {
    event := &BuildEvent{
        Project: project.Name,
        Command: project.Command,
        Status:  "started",
    }

    start := time.Now()

    // Run the build command
    cmd := exec.Command("bash", "-c", project.Command)
    cmd.Dir = project.Path

    output, err := cmd.CombinedOutput()
    event.Output = string(output)
    event.ExitCode = 0

    if err != nil {
        if exitErr, ok := err.(*exec.ExitError); ok {
            event.ExitCode = exitErr.ExitCode()
        }
    }

    event.Duration = time.Since(start)

    // Determine status
    if event.ExitCode == 0 {
        event.Status = "success"
    } else {
        event.Status = "failed"
    }

    // Check for warnings
    if strings.Contains(event.Output, "warning:") {
        event.Status = "warning"
    }

    m.lastBuild[project.Name] = event

    // Play sound based on status
    m.playSound(project, event.Status)

    return event
}

func (m *BuildMonitor) startLogWatcher(project *BuildProject) {
    watcher, err := fsnotify.NewWatcher()
    if err != nil {
        return
    }

    logPath := filepath.Join(project.Path, "build.log")
    watcher.Add(logPath)

    m.watchDirs[project.Name] = watcher

    go func() {
        for {
            select {
            case event, ok := <-watcher.Events:
                if !ok {
                    return
                }
                if event.Op&fsnotify.Write == fsnotify.Write {
                    m.checkBuildLog(project, event.Name)
                }
            case <-m.stopCh:
                return
            }
        }
    }()
}

func (m *BuildMonitor) checkBuildLog(project *BuildProject, logPath string) {
    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    content := string(data)

    // Check for build completion markers
    if strings.Contains(content, "BUILD SUCCESSFUL") {
        if last := m.lastBuild[project.Name]; last == nil || last.Status != "success" {
            m.lastBuild[project.Name] = &BuildEvent{
                Project: project.Name,
                Status:  "success",
            }
            m.playSound(project, "success")
        }
    }

    if strings.Contains(content, "BUILD FAILED") || strings.Contains(content, "error:") {
        if last := m.lastBuild[project.Name]; last == nil || last.Status != "failed" {
            m.lastBuild[project.Name] = &BuildEvent{
                Project: project.Name,
                Status:  "failed",
            }
            m.playSound(project, "failed")
        }
    }
}

func (m *BuildMonitor) playSound(project *BuildProject, event string) {
    sound := project.Sound
    if sound == "" {
        sound = m.config.Sounds[event]
    }
    if sound == "" {
        sound = m.config.DefaultSound
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
| fsnotify | Go Module | Free | File watching |
| exec | Go Stdlib | Free | Process execution |

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
| macOS | Supported | Uses fsnotify and exec |
| Linux | Supported | Uses fsnotify and exec |
| Windows | Not Supported | ccbell only supports macOS/Linux |
