# Feature: Sound Event Encrypted Volume Monitor

Play sounds for encrypted volume unlock, lock, and key rotation events.

## Summary

Monitor LUKS encrypted volumes and dm-crypt devices, playing sounds for encryption events.

## Motivation

- Security awareness
- Unlock detection
- Key rotation alerts
- Decryption feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Encrypted Volume Events

| Event | Description | Example |
|-------|-------------|---------|
| Volume Unlocked | Device decrypted | cryptsetup luksOpen |
| Volume Locked | Device locked | cryptsetup luksClose |
| Key Added | New keyslot added | luksAddKey |
| Key Removed | Keyslot removed | luksRemoveKey |

### Configuration

```go
type EncryptedVolumeMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchVolumes    []string          `json:"watch_volumes"] // "/dev/sda1", "data"
    SoundOnUnlock   bool              `json:"sound_on_unlock"]
    SoundOnLock     bool              `json:"sound_on_lock"]
    SoundOnKey      bool              `json:"sound_on_key"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 10 default
}

type EncryptedVolumeEvent struct {
    Device      string
    Name        string
    KeySlots    int
    Size        int64
    EventType   string // "unlock", "lock", "key_add", "key_remove"
}
```

### Commands

```bash
/ccbell:luks status                   # Show encrypted volume status
/ccbell:luks add data                 # Add volume to watch
/ccbell:luks remove data
/ccbell:luks sound unlock <sound>
/ccbell:luks sound key <sound>
/ccbell:luks test                     # Test luks sounds
```

### Output

```
$ ccbell:luks status

=== Sound Event Encrypted Volume Monitor ===

Status: Enabled
Unlock Sounds: Yes
Key Sounds: Yes

Watched Volumes: 2

[1] /dev/sda1 (data)
    Status: UNLOCKED
    Mapped: /dev/mapper/data
    Keyslots: 2
    Size: 500 GB
    Sound: bundled:luks-unlock

[2] /dev/sdb1 (backup)
    Status: LOCKED
    Keyslots: 1
    Size: 1 TB
    Sound: bundled:stop

Recent Events:
  [1] /dev/sda1: Volume Unlocked (5 min ago)
       Keyslot 2 added
  [2] /dev/sda1: Key Added (10 min ago)
       New keyslot created
  [3] /dev/sdb1: Volume Locked (1 hour ago)
       Device closed

Encrypted Volume Statistics:
  Unlocked: 1
  Locked: 1
  Key operations: 3

Sound Settings:
  Unlock: bundled:luks-unlock
  Lock: bundled:luks-lock
  Key: bundled:luks-key

[Configure] [Add Volume] [Test All]
```

---

## Audio Player Compatibility

Encrypted volume monitoring doesn't play sounds directly:
- Monitoring feature using dm-crypt tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Encrypted Volume Monitor

```go
type EncryptedVolumeMonitor struct {
    config           *EncryptedVolumeMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    volumeState      map[string]*VolumeInfo
    lastEventTime    map[string]time.Time
}

type VolumeInfo struct {
    Device    string
    Name      string
    Unlocked  bool
    Keyslots  int
    Size      int64
}

func (m *EncryptedVolumeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.volumeState = make(map[string]*VolumeInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *EncryptedVolumeMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotVolumeState()

    for {
        select {
        case <-ticker.C:
            m.checkVolumeState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *EncryptedVolumeMonitor) snapshotVolumeState() {
    // Check /dev/mapper for unlocked volumes
    m.checkUnlockedVolumes()

    // Check for LUKS headers
    m.checkLUKSVolumes()
}

func (m *EncryptedVolumeMonitor) checkVolumeState() {
    m.checkUnlockedVolumes()
    m.checkLUKSVolumes()
}

func (m *EncryptedVolumeMonitor) checkUnlockedVolumes() {
    mapperPath := "/dev/mapper"
    entries, err := os.ReadDir(mapperPath)
    if err != nil {
        return
    }

    currentVolumes := make(map[string]bool)

    for _, entry := range entries {
        if entry.Name() == "control" {
            continue
        }

        device := filepath.Join(mapperPath, entry.Name())
        currentVolumes[entry.Name()] = true

        // Get device info
        info := m.getVolumeInfo(entry.Name())
        info.Unlocked = true

        lastInfo := m.volumeState[entry.Name()]
        m.evaluateVolumeState(entry.Name(), info, lastInfo)

        m.volumeState[entry.Name()] = info
    }

    // Check for locked volumes
    for name, info := range m.volumeState {
        if info.Unlocked && !currentVolumes[name] {
            m.onVolumeLocked(name, info)
            info.Unlocked = false
        }
    }
}

func (m *EncryptedVolumeMonitor) checkLUKSVolumes() {
    // Check /sys/block for LUKS devices
    for _, device := range m.config.WatchVolumes {
        if strings.HasPrefix(device, "/dev/") {
            m.checkLUKSHeader(device)
        }
    }
}

func (m *EncryptedVolumeMonitor) getVolumeInfo(name string) *VolumeInfo {
    // Get size from /sys
    sysPath := filepath.Join("/sys/class/block", name, "size")
    data, err := os.ReadFile(sysPath)
    if err != nil {
        return &VolumeInfo{Name: name}
    }

    sizeSectors, _ := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
    sizeBytes := sizeSectors * 512

    return &VolumeInfo{
        Name: name,
        Size: sizeBytes,
    }
}

func (m *EncryptedVolumeMonitor) checkLUKSHeader(device string) {
    // Use cryptsetup to check if device is LUKS
    cmd := exec.Command("cryptsetup", "isLuks", device)
    if err := cmd.Run(); err != nil {
        return // Not a LUKS device
    }

    // Get keyslot count
    cmd = exec.Command("cryptsetup", "luksDump", device)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    keyslots := m.parseKeyslotCount(string(output))
    name := filepath.Base(device)

    info := &VolumeInfo{
        Device:   device,
        Name:     name,
        Keyslots: keyslots,
    }

    lastInfo := m.volumeState[name]
    if lastInfo != nil && lastInfo.Keyslots != keyslots {
        if keyslots > lastInfo.Keyslots {
            m.onKeyAdded(name, keyslots)
        } else if keyslots < lastInfo.Keyslots {
            m.onKeyRemoved(name, keyslots)
        }
    }

    m.volumeState[name] = info
}

func (m *EncryptedVolumeMonitor) parseKeyslotCount(output string) int {
    lines := strings.Split(output, "\n")
    count := 0

    for _, line := range lines {
        if strings.Contains(line, "Key Slot") {
            count++
        }
    }

    return count
}

func (m *EncryptedVolumeMonitor) evaluateVolumeState(name string, info *VolumeInfo, lastInfo *VolumeInfo) {
    if lastInfo == nil {
        // First detection
        if info.Unlocked {
            m.onVolumeUnlocked(name, info)
        }
        return
    }

    // Check for unlock
    if info.Unlocked && !lastInfo.Unlocked {
        m.onVolumeUnlocked(name, info)
    }
}

func (m *EncryptedVolumeMonitor) shouldWatchVolume(name string) bool {
    if len(m.config.WatchVolumes) == 0 {
        return true
    }

    for _, v := range m.config.WatchVolumes {
        if strings.Contains(name, v) || v == name {
            return true
        }
    }

    return false
}

func (m *EncryptedVolumeMonitor) onVolumeUnlocked(name string, info *VolumeInfo) {
    if !m.config.SoundOnUnlock {
        return
    }

    if !m.shouldWatchVolume(name) {
        return
    }

    key := fmt.Sprintf("unlock:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["unlock"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *EncryptedVolumeMonitor) onVolumeLocked(name string, info *VolumeInfo) {
    if !m.config.SoundOnLock {
        return
    }

    key := fmt.Sprintf("lock:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["lock"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *EncryptedVolumeMonitor) onKeyAdded(name string, keyslots int) {
    if !m.config.SoundOnKey {
        return
    }

    key := fmt.Sprintf("key_add:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["key"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *EncryptedVolumeMonitor) onKeyRemoved(name string, keyslots int) {
    key := fmt.Sprintf("key_remove:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["key_remove"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *EncryptedVolumeMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| cryptsetup | System Tool | Free | LUKS management |
| /dev/mapper | File | Free | DM-Crypt devices |

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
| macOS | Not Supported | No native LUKS |
| Linux | Supported | Uses cryptsetup |
| Windows | Not Supported | ccbell only supports macOS/Linux |
