# Feature: Sound Event Kernel Module Monitor

Play sounds for kernel module loading and unloading events.

## Summary

Monitor kernel module (driver) operations, playing sounds when modules are loaded or unloaded.

## Motivation

- Driver change awareness
- Security monitoring
- Hardware detection
- System modification alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Kernel Module Events

| Event | Description | Example |
|-------|-------------|---------|
| Module Loaded | New driver loaded | nvidia.ko |
| Module Unloaded | Driver removed | Old driver |
| Module Failed | Load error | Unsigned module |

### Configuration

```go
type KernelModuleMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchModules      []string          `json:"watch_modules"` // Specific modules
    SoundOnLoad       bool              `json:"sound_on_load"]
    SoundOnUnload     bool              `json:"sound_on_unload"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type KernelModuleEvent struct {
    ModuleName  string
    State       string // "loaded", "unloaded", "failed"
    UsedBy      []string
    Size        int64
}
```

### Commands

```bash
/ccbell:module status                # Show module status
/ccbell:module add nvidia            # Add module to watch
/ccbell:module remove nvidia
/ccbell:module sound load <sound>
/ccbell:module sound unload <sound>
/ccbell:module test                  # Test module sounds
```

### Output

```
$ ccbell:module status

=== Sound Event Kernel Module Monitor ===

Status: Enabled
Load Sounds: Yes
Unload Sounds: Yes

Watched Modules: 3

[1] nvidia
    Status: LOADED
    Used By: Xorg, nvidia-pm
    Size: 25 MB
    Loaded: 2 days ago
    Sound: bundled:stop

[2] vboxdrv
    Status: LOADED
    Used By: vboxnetadp, vboxnetflt
    Size: 500 KB
    Loaded: 1 week ago
    Sound: bundled:stop

[3] brcmfmac
    Status: UNLOADED
    Last Loaded: 1 month ago
    Sound: bundled:stop

Recent Events:
  [1] nvidia: Loaded (2 days ago)
       Version: 525.147.05
  [2] brcmfmac: Unloaded (1 month ago)
  [3] vboxdrv: Loaded (1 week ago)

Sound Settings:
  Load: bundled:stop
  Unload: bundled:stop
  Failed: bundled:stop

[Configure] [Add Module] [Test All]
```

---

## Audio Player Compatibility

Kernel module monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Kernel Module Monitor

```go
type KernelModuleMonitor struct {
    config         *KernelModuleMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    moduleState    map[string]*ModuleStatus
}

type ModuleStatus struct {
    Name       string
    State      string // "loaded", "unloaded"
    UsedBy     []string
    Size       int64
    LoadedTime time.Time
}
```

```go
func (m *KernelModuleMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.moduleState = make(map[string]*ModuleStatus)
    go m.monitor()
}

func (m *KernelModuleMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkModules()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KernelModuleMonitor) checkModules() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinModules()
    } else {
        m.checkLinuxModules()
    }
}

func (m *KernelModuleMonitor) checkDarwinModules() {
    // Use kextstat to list kernel extensions
    cmd := exec.Command("kextstat")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseKextstatOutput(string(output))
}

func (m *KernelModuleMonitor) checkLinuxModules() {
    // Use lsmod and /proc/modules
    cmd := exec.Command("lsmod")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLsmodOutput(string(output))
}

func (m *KernelModuleMonitor) parseKextstatOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Index") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 7 {
            continue
        }

        // Extract module name from path
        path := parts[6]
        name := filepath.Base(path)

        // Check if we should watch this module
        if !m.shouldWatchModule(name) {
            continue
        }

        status := &ModuleStatus{
            Name:  name,
            State: "loaded",
        }

        m.evaluateModule(name, status)
    }
}

func (m *KernelModuleMonitor) parseLsmodOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Module") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        name := parts[0]
        size := parts[1]
        useCount := parts[2]
        usedBy := parts[3:]

        if !m.shouldWatchModule(name) {
            continue
        }

        sizeBytes, _ := strconv.ParseInt(size, 10, 64)

        status := &ModuleStatus{
            Name:   name,
            State:  "loaded",
            Size:   sizeBytes,
            UsedBy: usedBy,
        }

        m.evaluateModule(name, status)
    }
}

func (m *KernelModuleMonitor) shouldWatchModule(name string) bool {
    if len(m.config.WatchModules) == 0 {
        return true
    }

    for _, watch := range m.config.WatchModules {
        if strings.Contains(strings.ToLower(name), strings.ToLower(watch)) {
            return true
        }
    }

    return false
}

func (m *KernelModuleMonitor) evaluateModule(name string, status *ModuleStatus) {
    lastState := m.moduleState[name]

    if lastState == nil {
        m.moduleState[name] = status
        m.onModuleLoaded(name)
        return
    }

    // Check for state changes
    if lastState.State == "loaded" && status.State == "unloaded" {
        m.onModuleUnloaded(name)
    } else if lastState.State == "unloaded" && status.State == "loaded" {
        m.onModuleLoaded(name)
    }

    m.moduleState[name] = status
}

func (m *KernelModuleMonitor) onModuleLoaded(name string) {
    if !m.config.SoundOnLoad {
        return
    }

    sound := m.config.Sounds["load"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *KernelModuleMonitor) onModuleUnloaded(name string) {
    if !m.config.SoundOnUnload {
        return
    }

    sound := m.config.Sounds["unload"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| kextstat | System Tool | Free | macOS kernel extensions |
| lsmod | System Tool | Free | Linux module list |

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
| macOS | Supported | Uses kextstat |
| Linux | Supported | Uses lsmod |
| Windows | Not Supported | ccbell only supports macOS/Linux |
