# Feature: Sound Event Environment Monitor

Play sounds for environment variable changes and configuration updates.

## Summary

Monitor environment variable changes, shell configuration updates, and system PATH modifications, playing sounds for environment events.

## Motivation

- PATH modification alerts
- Configuration change awareness
- Environment health checks
- Development workflow feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Environment Events

| Event | Description | Example |
|-------|-------------|---------|
| PATH Modified | Path changed | New directory added |
| Variable Set | Var defined | FOO=bar |
| Variable Unset | Var removed | FOO deleted |
| Config Updated | RC file changed | .bashrc updated |

### Configuration

```go
type EnvironmentMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchVariables   []string          `json:"watch_variables"` // Variables to watch
    WatchPatterns    []string          `json:"watch_patterns"` // PATH changes, etc.
    SoundOnChange    bool              `json:"sound_on_change"`
    SoundOnPATH      bool              `json:"sound_on_path_change"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type EnvironmentEvent struct {
    VariableName string
    OldValue     string
    NewValue     string
    ChangeType   string // "set", "unset", "modified"
    Source       string // shell config file
}
```

### Commands

```bash
/ccbell:environment status             # Show environment status
/ccbell:environment add "PATH"         # Add variable to watch
/ccbell:environment remove "PATH"
/ccbell:environment sound change <sound>
/ccbell:environment test               # Test environment sounds
```

### Output

```
$ ccbell:environment status

=== Sound Event Environment Monitor ===

Status: Enabled
Change Sounds: Yes
PATH Sounds: Yes

Watched Variables: 3

[1] PATH
    Current: /usr/local/bin:/usr/bin:/bin
    Changes Today: 2
    Last Change: 1 hour ago
    Sound: bundled:stop

[2] NODE_ENV
    Current: production
    Changes Today: 0
    Sound: bundled:stop

[3] PYTHONPATH
    Current: /project/src
    Changes Today: 1
    Last Change: 2 hours ago
    Sound: bundled:stop

Recent Events:
  [1] PATH: Modified (1 hour ago)
       Added: /project/bin
       Removed: /old/bin
  [2] PYTHONPATH: Set (2 hours ago)
       Was: ""
       Now: /project/src

Shell Config Files:
  ~/.bashrc: Last modified 1 day ago
  ~/.zshrc: Last modified 2 hours ago
  ~/.profile: Last modified 1 week ago

Sound Settings:
  Change: bundled:stop
  PATH Change: bundled:stop

[Configure] [Add Variable] [Test All]
```

---

## Audio Player Compatibility

Environment monitoring doesn't play sounds directly:
- Monitoring feature using environment reading
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Environment Monitor

```go
type EnvironmentMonitor struct {
    config           *EnvironmentMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    lastEnvState     map[string]string
    lastConfigMtime  map[string]time.Time
}

func (m *EnvironmentMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastEnvState = make(map[string]string)
    m.lastConfigMtime = make(map[string]time.Time)
    go m.monitor()
}

func (m *EnvironmentMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkEnvironment()
        case <-m.stopCh:
            return
        }
    }
}

func (m *EnvironmentMonitor) checkEnvironment() {
    m.checkEnvironmentVariables()
    m.checkShellConfigs()
}

func (m *EnvironmentMonitor) checkEnvironmentVariables() {
    // Get current environment
    for _, varName := range m.config.WatchVariables {
        currentValue := os.Getenv(varName)
        lastValue := m.lastEnvState[varName]

        if lastValue == "" && currentValue != "" {
            // Variable was set
            m.onVariableSet(varName, "", currentValue)
        } else if lastValue != "" && currentValue == "" {
            // Variable was unset
            m.onVariableUnset(varName, lastValue)
        } else if lastValue != currentValue {
            // Variable was modified
            m.onVariableModified(varName, lastValue, currentValue)
        }

        m.lastEnvState[varName] = currentValue
    }

    // Check PATH if needed
    if len(m.config.WatchPatterns) > 0 {
        for _, pattern := range m.config.WatchPatterns {
            if strings.ToLower(pattern) == "path" {
                m.checkPATH()
            }
        }
    }
}

func (m *EnvironmentMonitor) checkPATH() {
    pathValue := os.Getenv("PATH")
    lastPath := m.lastEnvState["PATH"]

    if lastPath == "" {
        m.lastEnvState["PATH"] = pathValue
        return
    }

    if pathValue != lastPath {
        // PATH changed
        oldPaths := strings.Split(lastPath, ":")
        newPaths := strings.Split(pathValue, ":")

        added := m.findAddedItems(oldPaths, newPaths)
        removed := m.findAddedItems(newPaths, oldPaths)

        m.onPATHChanged(pathValue, added, removed)
    }

    m.lastEnvState["PATH"] = pathValue
}

func (m *EnvironmentMonitor) findAddedItems(oldSlice, newSlice []string) []string {
    added := []string{}
    for _, item := range newSlice {
        found := false
        for _, old := range oldSlice {
            if item == old {
                found = true
                break
            }
        }
        if !found {
            added = append(added, item)
        }
    }
    return added
}

func (m *EnvironmentMonitor) checkShellConfigs() {
    configFiles := []string{
        filepath.Join(os.Getenv("HOME"), ".bashrc"),
        filepath.Join(os.Getenv("HOME"), ".zshrc"),
        filepath.Join(os.Getenv("HOME"), ".profile"),
        filepath.Join(os.Getenv("HOME"), ".bash_profile"),
    }

    for _, configFile := range configFiles {
        if _, err := os.Stat(configFile); os.IsNotExist(err) {
            continue
        }

        info, err := os.Stat(configFile)
        if err != nil {
            continue
        }

        lastMtime := m.lastConfigMtime[configFile]
        if lastMtime.IsZero() {
            m.lastConfigMtime[configFile] = info.ModTime()
            continue
        }

        if info.ModTime().After(lastMtime) {
            // Config file was modified
            m.onConfigUpdated(configFile)
        }

        m.lastConfigMtime[configFile] = info.ModTime()
    }
}

func (m *EnvironmentMonitor) onVariableSet(name string, oldValue string, newValue string) {
    if !m.config.SoundOnChange {
        return
    }

    event := &EnvironmentEvent{
        VariableName: name,
        OldValue:     oldValue,
        NewValue:     newValue,
        ChangeType:   "set",
    }

    m.playChangeSound(event)
}

func (m *EnvironmentMonitor) onVariableUnset(name string, oldValue string) {
    if !m.config.SoundOnChange {
        return
    }

    event := &EnvironmentEvent{
        VariableName: name,
        OldValue:     oldValue,
        NewValue:     "",
        ChangeType:   "unset",
    }

    m.playChangeSound(event)
}

func (m *EnvironmentMonitor) onVariableModified(name string, oldValue string, newValue string) {
    if !m.config.SoundOnChange {
        return
    }

    event := &EnvironmentEvent{
        VariableName: name,
        OldValue:     oldValue,
        NewValue:     newValue,
        ChangeType:   "modified",
    }

    m.playChangeSound(event)
}

func (m *EnvironmentMonitor) onPATHChanged(newPath string, added []string, removed []string) {
    if !m.config.SoundOnPATH {
        return
    }

    sound := m.config.Sounds["path_change"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *EnvironmentMonitor) onConfigUpdated(configFile string) {
    if !m.config.SoundOnChange {
        return
    }

    sound := m.config.Sounds["config_update"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *EnvironmentMonitor) playChangeSound(event *EnvironmentEvent) {
    sound := m.config.Sounds["change"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| os | Go Stdlib | Free | Environment access |
| filepath | Go Stdlib | Free | Path operations |
| os | Go Stdlib | Free | File info |

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
| macOS | Supported | Uses os.Getenv |
| Linux | Supported | Uses os.Getenv |
| Windows | Not Supported | ccbell only supports macOS/Linux |
