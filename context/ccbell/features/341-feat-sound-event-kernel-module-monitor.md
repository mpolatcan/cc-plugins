# Feature: Sound Event Kernel Module Monitor

Play sounds for kernel module loading, unloading, and dependency events.

## Summary

Monitor kernel module loading, unloading, and module dependency changes, playing sounds for kernel module events.

## Motivation

- Driver awareness
- Security monitoring
- Kernel change detection
- Module dependency alerts
- Hardware driver detection

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
| Module Loaded | New kernel module | nvidia.ko loaded |
| Module Unloaded | Module removed | nvidia.ko unloaded |
| Module Failed | Module load failed | Failed to load driver |
| Dependency Added | New dependency | usbcore depends on... |
| Dependency Missing | Missing dependency | Module dep not found |

### Configuration

```go
type KernelModuleMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchModules       []string          `json:"watch_modules"` // "nvidia", "docker", "*"
    SoundOnLoad        bool              `json:"sound_on_load"`
    SoundOnUnload      bool              `json:"sound_on_unload"`
    SoundOnFail        bool              `json:"sound_on_fail"`
    SoundOnDependency  bool              `json:"sound_on_dependency"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}

type KernelModuleEvent struct {
    Module       string
    Dependencies []string
    UsedBy       []string
    State        string // "live", "loading", "unloading"
    EventType    string // "load", "unload", "fail", "dependency"
}
```

### Commands

```bash
/ccbell:kmod status                  # Show kernel module status
/ccbell:kmod add nvidia              # Add module to watch
/ccbell:kmod remove nvidia
/ccbell:kmod sound load <sound>
/ccbell:kmod sound unload <sound>
/ccbell:kmod test                    # Test kernel module sounds
```

### Output

```
$ ccbell:kmod status

=== Sound Event Kernel Module Monitor ===

Status: Enabled
Load Sounds: Yes
Unload Sounds: Yes
Fail Sounds: Yes

Watched Modules: 3

[1] nvidia
    State: LIVE
    Used by: [nvidia_drm, nvidia_modeset]
    Dependencies: [nvidia]
    Size: 50348 KB
    Sound: bundled:kmod-nvidia

[2] docker
    State: LIVE
    Used by: []
    Dependencies: [overlay, bridge, iptable_nat]
    Size: 2048 KB
    Sound: bundled:kmod-docker

[3] vboxdrv
    State: UNLOADED
    Used by: []
    Dependencies: []
    Sound: bundled:kmod-vbox

Recent Events:
  [1] nvidia: Module Loaded (5 min ago)
       nvidia.ko loaded successfully
  [2] docker: Module Unloaded (10 min ago)
       Module unloaded by user
  [3] vboxdrv: Module Failed (1 hour ago)
       Failed to load: No such device

Kernel Module Statistics:
  Total modules: 450
  Watched: 3
  Loaded today: 5
  Unloaded: 3

Sound Settings:
  Load: bundled:kmod-load
  Unload: bundled:kmod-unload
  Fail: bundled:kmod-fail

[Configure] [Add Module] [Test All]
```

---

## Audio Player Compatibility

Kernel module monitoring doesn't play sounds directly:
- Monitoring feature using lsmod/modprobe
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Kernel Module Monitor

```go
type KernelModuleMonitor struct {
    config          *KernelModuleMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    moduleState     map[string]*ModuleInfo
    lastEventTime   map[string]time.Time
}

type ModuleInfo struct {
    Name         string
    Size         int // KB
    UsedBy       []string
    Dependencies []string
    State        string
    LastEvent    string
}

func (m *KernelModuleMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.moduleState = make(map[string]*ModuleInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *KernelModuleMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotModuleState()

    for {
        select {
        case <-ticker.C:
            m.checkModuleState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *KernelModuleMonitor) snapshotModuleState() {
    cmd := exec.Command("lsmod")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLSModOutput(string(output))
}

func (m *KernelModuleMonitor) checkModuleState() {
    cmd := exec.Command("lsmod")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseLSModOutput(string(output))
}

func (m *KernelModuleMonitor) parseLSModOutput(output string) {
    lines := strings.Split(output, "\n")
    currentModules := make(map[string]*ModuleInfo)

    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Module") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        name := parts[0]
        if !m.shouldWatchModule(name) {
            continue
        }

        size, _ := strconv.Atoi(parts[1])
        usedBy := []string{}
        if len(parts) > 3 {
            usedBy = strings.Split(parts[3], ",")
        }

        info := &ModuleInfo{
            Name:    name,
            Size:    size,
            UsedBy:  usedBy,
            State:   "live",
        }

        // Get dependencies
        deps := m.getModuleDependencies(name)
        info.Dependencies = deps

        currentModules[name] = info

        lastInfo := m.moduleState[name]
        if lastInfo == nil {
            // New module loaded
            m.moduleState[name] = info
            m.onModuleLoaded(name, info)
            continue
        }

        // Check for changes
        info.LastEvent = lastInfo.LastEvent
        m.moduleState[name] = info
    }

    // Check for unloaded modules
    for name, lastInfo := range m.moduleState {
        if _, exists := currentModules[name]; !exists {
            delete(m.moduleState, name)
            m.onModuleUnloaded(name, lastInfo)
        }
    }
}

func (m *KernelModuleMonitor) getModuleDependencies(name string) []string {
    depPath := filepath.Join("/sys/module", name, "holders")
    entries, err := os.ReadDir(depPath)
    if err != nil {
        return nil
    }

    var deps []string
    for _, entry := range entries {
        deps = append(deps, entry.Name())
    }

    return deps
}

func (m *KernelModuleMonitor) shouldWatchModule(name string) bool {
    if len(m.config.WatchModules) == 0 {
        return false
    }

    for _, mod := range m.config.WatchModules {
        if mod == "*" || mod == name {
            return true
        }
    }

    return false
}

func (m *KernelModuleMonitor) onModuleLoaded(name string, info *ModuleInfo) {
    if !m.config.SoundOnLoad {
        return
    }

    key := fmt.Sprintf("load:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["load"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *KernelModuleMonitor) onModuleUnloaded(name string, info *ModuleInfo) {
    if !m.config.SoundOnUnload {
        return
    }

    key := fmt.Sprintf("unload:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["unload"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *KernelModuleMonitor) onModuleFailed(name string, err error) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *KernelModuleMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lsmod | System Tool | Free | Module listing |
| modprobe | System Tool | Free | Module management |
| /sys/module/*/holders | Filesystem | Free | Dependency info |

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
| macOS | Not Supported | No native kernel modules |
| Linux | Supported | Uses lsmod, sysfs |
