# Feature: Sound Event Kernel Module Monitor

Play sounds for kernel module loading, unloading, and parameter changes.

## Summary

Monitor kernel modules for load/unload events, parameter changes, and dependencies, playing sounds for module events.

## Motivation

- Kernel change awareness
- Driver loading alerts
- Security monitoring
- Performance module tracking
- System configuration changes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Kernel Module Events

| Event | Description | Example |
|-------|-------------|---------|
| Module Loaded | New module inserted | nouveau |
| Module Unloaded | Module removed | kvm_intel |
| Module Failed | Load failed | error |
| Parameter Changed | Module param changed | param=value |
| Dependency Added | New dependency | needed |
| Module Hotplug | Hotplug event | USB driver |

### Configuration

```go
type KernelModuleMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchModules      []string          `json:"watch_modules"` // "kvm", "nvidia", "*"
    WatchTypes        []string          `json:"watch_types"` // "driver", "fs", "net"
    SoundOnLoad       bool              `json:"sound_on_load"`
    SoundOnUnload     bool              `json:"sound_on_unload"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:kmod status                   # Show module status
/ccbell:kmod add kvm                  # Add module to watch
/ccbell:kmod remove kvm
/ccbell:kmod sound load <sound>
/ccbell:kmod sound unload <sound>
/ccbell:kmod test                     # Test module sounds
```

### Output

```
$ ccbell:kmod status

=== Sound Event Kernel Module Monitor ===

Status: Enabled
Load Sounds: Yes
Unload Sounds: Yes
Fail Sounds: Yes

Watched Modules: 4
Watched Types: 2

Loaded Kernel Modules:

[1] kvm_intel (2 hours ago)
    Status: Loaded
    Size: 245 KB
    Used by: 1
    Type: virt
    Parameters: nested=1, ept=1
    Sound: bundled:kmod-kvm

[2] nvidia (1 day ago)
    Status: Loaded
    Size: 15 MB
    Used by: 3
    Type: driver
    Parameters: NVreg_UsePageAttributeTable=1
    Sound: bundled:kmod-nvidia

[3] br_netfilter (1 week ago)
    Status: Loaded
    Size: 32 KB
    Used by: 2
    Type: net
    Parameters: -
    Sound: bundled:kmod-bridge

[4] vboxdrv (2 days ago)
    Status: Loaded
    Size: 1.2 MB
    Used by: 0
    Type: driver
    Parameters: -
    Sound: bundled:kmod-vbox

Recent Events:
  [1] kvm_intel: Module Loaded (2 hours ago)
       Nested virtualization enabled
  [2] br_netfilter: Parameter Changed (1 day ago)
       bridge-nf-call-iptables=1
  [3] vboxdrv: Module Unloaded (3 days ago)
       Manual unload

Module Statistics:
  Loaded Today: 1
  Unloaded Today: 0
  Total Loaded: 145

Sound Settings:
  Load: bundled:kmod-load
  Unload: bundled:kmod-unload
  Fail: bundled:kmod-fail

[Configure] [Add Module] [Test All]
```

---

## Audio Player Compatibility

Module monitoring doesn't play sounds directly:
- Monitoring feature using lsmod/modinfo
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
    Name        string
    Size        int64
    UsedBy      int
    Status      string // "loaded", "unloaded"
    Type        string
    Parameters  map[string]string
    LoadedAt    time.Time
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
    m.checkModuleState()
}

func (m *KernelModuleMonitor) checkModuleState() {
    modules := m.listModules()
    currentModules := make(map[string]*ModuleInfo)

    for _, mod := range modules {
        currentModules[mod.Name] = mod
    }

    // Check for new modules
    for name, mod := range currentModules {
        if _, exists := m.moduleState[name]; !exists {
            m.moduleState[name] = mod
            if m.shouldWatchModule(name) {
                m.onModuleLoaded(mod)
            }
        }
    }

    // Check for removed modules
    for name, lastMod := range m.moduleState {
        if _, exists := currentModules[name]; !exists {
            delete(m.moduleState, name)
            if m.shouldWatchModule(name) {
                m.onModuleUnloaded(lastMod)
            }
        }
    }
}

func (m *KernelModuleMonitor) listModules() []*ModuleInfo {
    var modules []*ModuleInfo

    cmd := exec.Command("lsmod")
    output, err := cmd.Output()
    if err != nil {
        return modules
    }

    lines := strings.Split(string(output), "\n")
    // Skip header
    if len(lines) > 1 {
        for i := 1; i < len(lines); i++ {
            line := strings.TrimSpace(lines[i])
            if line == "" {
                continue
            }

            parts := strings.Fields(line)
            if len(parts) >= 3 {
                name := parts[0]
                size, _ := strconv.ParseInt(parts[1], 10, 64)

                // Parse "used by" field
                usedBy := 0
                if len(parts) >= 4 {
                    usedBy = len(strings.Fields(parts[3]))
                } else if len(parts) >= 3 && parts[2] != "-" {
                    usedBy = len(strings.Fields(parts[2]))
                }

                mod := &ModuleInfo{
                    Name:     name,
                    Size:     size,
                    UsedBy:   usedBy,
                    Status:   "loaded",
                    LoadedAt: time.Now(),
                }

                // Get module info
                info := m.getModuleInfo(name)
                if info != nil {
                    mod.Type = info.Type
                    mod.Parameters = info.Parameters
                }

                modules = append(modules, mod)
            }
        }
    }

    return modules
}

func (m *KernelModuleMonitor) getModuleInfo(name string) *ModuleInfo {
    info := &ModuleInfo{
        Name:       name,
        Parameters: make(map[string]string),
    }

    // Get module description/type
    cmd := exec.Command("modinfo", name)
    output, err := cmd.Output()
    if err != nil {
        return info
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, ":", 2)
        if len(parts) == 2 {
            key := strings.TrimSpace(parts[0])
            value := strings.TrimSpace(parts[1])

            switch key {
            case "description", "author", "license":
                // Skip descriptive fields
            case "depends":
                // Parse dependencies
            case "parm":
                // Parse parameters
                parmParts := strings.SplitN(value, ":", 2)
                if len(parmParts) == 2 {
                    info.Parameters[parmParts[0]] = parmParts[1]
                }
            }
        }
    }

    return info
}

func (m *KernelModuleMonitor) shouldWatchModule(name string) bool {
    if len(m.config.WatchModules) == 0 {
        return true
    }

    for _, m := range m.config.WatchModules {
        if m == "*" || name == m || strings.HasPrefix(name, m) {
            return true
        }
    }

    return false
}

func (m *KernelModuleMonitor) onModuleLoaded(mod *ModuleInfo) {
    if !m.config.SoundOnLoad {
        return
    }

    key := fmt.Sprintf("load:%s", mod.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["load"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *KernelModuleMonitor) onModuleUnloaded(mod *ModuleInfo) {
    if !m.config.SoundOnUnload {
        return
    }

    key := fmt.Sprintf("unload:%s", mod.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["unload"]
        if sound != "" {
            m.player.Play(sound, 0.3)
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
| lsmod | System Tool | Free | List modules |
| modinfo | System Tool | Free | Module information |

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
| macOS | Not Supported | No kernel modules |
| Linux | Supported | Uses lsmod, modinfo |
