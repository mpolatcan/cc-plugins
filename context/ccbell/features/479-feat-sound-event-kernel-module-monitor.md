# Feature: Sound Event Kernel Module Monitor

Play sounds for kernel module loading, unloading, and parameter changes.

## Summary

Monitor kernel modules for loading, unloading, dependency changes, and parameter modifications, playing sounds for module events.

## Motivation

- Module awareness
- Security monitoring
- Driver changes
- Performance impact
- Kernel extension tracking

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
| Module Loaded | New module | nvidia loaded |
| Module Unloaded | Module removed | nvidia unloaded |
| Module Failed | Load failed | failed to load |
| Parameter Changed | Module param | changed |
| Dependency Added | New dependency | added |
| Info Changed | Version changed | info updated |

### Configuration

```go
type KernelModuleMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchModules   []string          `json:"watch_modules"` // "*" for all
    SoundOnLoad    bool              `json:"sound_on_load"`
    SoundOnUnload  bool              `json:"sound_on_unload"`
    SoundOnFailed  bool              `json:"sound_on_failed"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:kmod status                 # Show kernel module status
/ccbell:kmod add nvidia             # Add module to watch
/ccbell:kmod sound load <sound>
/ccbell:kmod test                   # Test kernel module sounds
```

### Output

```
$ ccbell:kmod status

=== Sound Event Kernel Module Monitor ===

Status: Enabled
Watch Modules: all

Kernel Module Status:

[1] nvidia (loaded)
    Status: LOADED
    Size: 50 MB
    Used By: 2 (nvidia_uvm, nvidia_modeset)
    Description: NVIDIA driver
    Sound: bundled:kmod-nvidia

[2] vboxguest (loaded)
    Status: LOADED
    Size: 2 MB
    Used By: 0
    Description: VirtualBox guest
    Sound: bundled:kmod-vbox

[3] wl (loaded)
    Status: LOADED
    Size: 5 MB
    Used By: 1 (brcmfmac)
    Description: Broadcom wireless
    Sound: bundled:kmod-wifi

Recent Events:

[1] v4l2loopback: Module Loaded (5 min ago)
       v4l2loopback.ko loaded
       Sound: bundled:kmod-load
  [2] nvidia: Parameter Changed (1 hour ago)
       NVreg_EnableBacklightBars=0
       Sound: bundled:kmod-param
  [3] vboxsf: Module Unloaded (2 hours ago)
       VirtualBox shared folder unloaded
       Sound: bundled:kmod-unload

Kernel Module Statistics:
  Total Modules: 145
  Loaded Today: 2
  Unloaded Today: 1

Sound Settings:
  Load: bundled:kmod-load
  Unload: bundled:kmod-unload
  Failed: bundled:kmod-failed
  Param: bundled:kmod-param

[Configure] [Add Module] [Test All]
```

---

## Audio Player Compatibility

Kernel module monitoring doesn't play sounds directly:
- Monitoring feature using lsmod, modinfo
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Kernel Module Monitor

```go
type KernelModuleMonitor struct {
    config        *KernelModuleMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    moduleState   map[string]*ModuleInfo
    lastEventTime map[string]time.Time
}

type ModuleInfo struct {
    Name        string
    Status      string // "loaded", "unloaded"
    Size        int64
    UsedBy      int
    Description string
    Params      map[string]string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lsmod | System Tool | Free | Loaded modules list |
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
| macOS | Supported | Uses kextstat |
| Linux | Supported | Uses lsmod, modinfo |
