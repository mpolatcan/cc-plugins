# Feature: Sound Event GPU Status Monitor

Play sounds for GPU utilization, temperature thresholds, and memory usage.

## Summary

Monitor GPU status for utilization, temperature, memory, and fan speed, playing sounds for GPU events.

## Motivation

- GPU performance tracking
- Temperature alerts
- Memory usage monitoring
- Fan speed warnings
- Compute workload feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### GPU Status Events

| Event | Description | Example |
|-------|-------------|---------|
| High Temperature | Temp > threshold | > 80C |
| GPU Load High | Utilization > threshold | > 90% |
| Memory Full | VRAM > threshold | > 95% |
| Fan Speed High | Fan > threshold | > 80% |
| GPU Idle | Utilization drops | < 5% |
| Process Attached | New GPU process | new compute |

### Configuration

```go
type GPUStatusMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchGPUs         []string          `json:"watch_gpus"` // "0", "all"
    TempThreshold     int               `json:"temp_threshold"` // 80 default
    LoadThreshold     float64           `json:"load_threshold"` // 90.0 default
    MemoryThreshold   float64           `json:"memory_threshold"` // 95.0 default
    FanThreshold      int               `json:"fan_threshold"` // 80 default
    SoundOnTemp       bool              `json:"sound_on_temp"`
    SoundOnLoad       bool              `json:"sound_on_load"`
    SoundOnMemory     bool              `json:"sound_on_memory"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:gpu status                     # Show GPU status
/ccbell:gpu add 0                      # Add GPU to watch
/ccbell:gpu temp 80                    # Set temp threshold
/ccbell:gpu load 90                    # Set load threshold
/ccbell:gpu sound temp <sound>
/ccbell:gpu sound load <sound>
/ccbell:gpu test                       # Test GPU sounds
```

### Output

```
$ ccbell:gpu status

=== Sound Event GPU Status Monitor ===

Status: Enabled
Temperature Threshold: 80C
Load Threshold: 90%
Memory Threshold: 95%

Watched GPUs: 2

GPU Status:

[0] NVIDIA GeForce RTX 3080
    Driver: 535.154.05
    Temperature: 65C
    Utilization: 45%
    Memory: 10/12 GB (83%)
    Fan Speed: 35%
    Power: 180/320W (56%)
    Processes: 2
    Sound: bundled:gpu-rtx3080

[1] NVIDIA GeForce GTX 1080
    Driver: 535.154.05
    Temperature: 72C
    Utilization: 0% (Idle)
    Memory: 4/8 GB (50%)
    Fan Speed: 30%
    Power: 20/180W (11%)
    Processes: 0
    Sound: bundled:gpu-gtx1080

GPU Statistics:
  Total GPUs: 2
  Active: 1
  Average Load: 23%
  Average Temp: 68C

Recent Events:
  [1] NVIDIA GeForce RTX 3080: High Load (5 min ago)
       92% > 90% threshold
  [2] NVIDIA GeForce GTX 1080: GPU Idle (1 hour ago)
       Utilization dropped to 0%
  [3] NVIDIA GeForce RTX 3080: Temperature Normalized (2 hours ago)
       78C < 80C threshold

Sound Settings:
  Temperature: bundled:gpu-temp
  Load: bundled:gpu-load
  Memory: bundled:gpu-memory

[Configure] [Add GPU] [Test All]
```

---

## Audio Player Compatibility

GPU monitoring doesn't play sounds directly:
- Monitoring feature using nvidia-smi/rocm-smi
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### GPU Status Monitor

```go
type GPUStatusMonitor struct {
    config          *GPUStatusMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    gpuState        map[string]*GPUInfo
    lastEventTime   map[string]time.Time
}

type GPUInfo struct {
    Index       string
    Name        string
    Driver      string
    Temperature int
    Utilization float64 // percentage
    MemoryUsed  int64   // MB
    MemoryTotal int64   // MB
    FanSpeed    int     // percentage
    PowerUsed   float64 // watts
    PowerMax    float64 // watts
    Processes   int
    LastCheck   time.Time
}

func (m *GPUStatusMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.gpuState = make(map[string]*GPUInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *GPUMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkGPUStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *GPUStatusMonitor) checkGPUStatus() {
    // Check for NVIDIA GPUs
    if m.isNVidiaAvailable() {
        m.checkNvidiaGPUs()
    }

    // Check for AMD GPUs
    if m.isAMDAvailable() {
        m.checkAMdGPUs()
    }
}

func (m *GPUStatusMonitor) isNVidiaAvailable() bool {
    cmd := exec.Command("which", "nvidia-smi")
    return cmd.Run() == nil
}

func (m *GPUStatusMonitor) isAMDAvailable() bool {
    cmd := exec.Command("which", "rocm-smi")
    return cmd.Run() == nil
}

func (m *GPUStatusMonitor) checkNvidiaGPUs() {
    cmd := exec.Command("nvidia-smi", "--query-gpu=index,name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total,fan.speed,power.draw,power.max,compute_p", "--format=csv", "-l", "1")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    // Skip header
    if len(lines) > 1 {
        for i := 1; i < len(lines); i++ {
            line := strings.TrimSpace(lines[i])
            if line == "" {
                continue
            }
            m.parseNvidiaGPU(line)
        }
    }
}

func (m *GPUStatusMonitor) parseNvidiaGPU(line string) {
    parts := strings.Split(line, ", ")
    if len(parts) < 11 {
        return
    }

    info := &GPUInfo{
        Index:       strings.TrimSpace(parts[0]),
        Name:        strings.TrimSpace(parts[1]),
        Driver:      strings.TrimSpace(parts[2]),
        LastCheck:   time.Now(),
    }

    // Parse temperature
    if temp, err := strconv.Atoi(strings.TrimSpace(parts[3])); err == nil {
        info.Temperature = temp
    }

    // Parse utilization
    if util, err := strconv.ParseFloat(strings.TrimSpace(parts[4])); err == nil {
        info.Utilization = util
    }

    // Parse memory
    if memUsed, err := strconv.ParseInt(strings.TrimSpace(parts[5]), 10, 64); err == nil {
        info.MemoryUsed = memUsed
    }
    if memTotal, err := strconv.ParseInt(strings.TrimSpace(parts[6]), 10, 64); err == nil {
        info.MemoryTotal = memTotal
    }

    // Parse fan speed
    if fan, err := strconv.Atoi(strings.TrimSpace(parts[7])); err == nil {
        info.FanSpeed = fan
    }

    // Parse power
    if power, err := strconv.ParseFloat(strings.TrimSpace(parts[8])); err == nil {
        info.PowerUsed = power
    }
    if powerMax, err := strconv.ParseFloat(strings.TrimSpace(parts[9])); err == nil {
        info.PowerMax = powerMax
    }

    // Parse processes
    if procs, err := strconv.Atoi(strings.TrimSpace(parts[10])); err == nil {
        info.Processes = procs
    }

    m.processGPUStatus(info)
}

func (m *GPUStatusMonitor) checkAMdGPUs() {
    cmd := exec.Command("rocm-smi", "--showtemp", "--showuse", "--showmem", "--showfan", "--json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse JSON output (simplified)
    // In production, use proper JSON parsing
    _ = output
}

func (m *GPUStatusMonitor) processGPUStatus(info *GPUInfo) {
    lastInfo := m.gpuState[info.Index]

    if lastInfo == nil {
        m.gpuState[info.Index] = info
        return
    }

    // Check temperature threshold
    if info.Temperature >= m.config.TempThreshold {
        if lastInfo.Temperature < m.config.TempThreshold {
            if m.config.SoundOnTemp {
                m.onHighTemperature(info)
            }
        }
    } else if lastInfo.Temperature >= m.config.TempThreshold {
        // Temperature normalized
    }

    // Check load threshold
    if info.Utilization >= m.config.LoadThreshold {
        if lastInfo.Utilization < m.config.LoadThreshold {
            if m.config.SoundOnLoad {
                m.onHighLoad(info)
            }
        }
    }

    // Check memory threshold
    memoryPct := float64(info.MemoryUsed) / float64(info.MemoryTotal) * 100
    lastMemoryPct := float64(lastInfo.MemoryUsed) / float64(lastInfo.MemoryTotal) * 100

    if memoryPct >= m.config.MemoryThreshold {
        if lastMemoryPct < m.config.MemoryThreshold {
            if m.config.SoundOnMemory {
                m.onHighMemory(info)
            }
        }
    }

    // Check for new processes
    if info.Processes > 0 && lastInfo.Processes == 0 {
        m.onProcessAttached(info)
    }

    m.gpuState[info.Index] = info
}

func (m *GPUStatusMonitor) onHighTemperature(info *GPUInfo) {
    key := fmt.Sprintf("temp:%s", info.Index)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["temp"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *GPUStatusMonitor) onHighLoad(info *GPUInfo) {
    key := fmt.Sprintf("load:%s", info.Index)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["load"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *GPUStatusMonitor) onHighMemory(info *GPUInfo) {
    key := fmt.Sprintf("memory:%s", info.Index)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["memory"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *GPUStatusMonitor) onProcessAttached(info *GPUInfo) {
    // Optional: sound when new process starts using GPU
}

func (m *GPUStatusMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| nvidia-smi | System Tool | Free | NVIDIA GPU status |
| rocm-smi | System Tool | Free | AMD GPU status |

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
| macOS | Supported | Uses nvidia-smi (if available) |
| Linux | Supported | Uses nvidia-smi, rocm-smi |
