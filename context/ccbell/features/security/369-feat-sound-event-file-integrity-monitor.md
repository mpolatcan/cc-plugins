# Feature: Sound Event File Integrity Monitor

Play sounds for file changes, permission modifications, and integrity violations.

## Summary

Monitor file integrity, detect unauthorized changes, and track file system modifications, playing sounds for integrity events.

## Motivation

- Security monitoring
- Change detection
- Permission tracking
- Tampering detection
- Audit trail feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### File Integrity Events

| Event | Description | Example |
|-------|-------------|---------|
| File Changed | File modified | config.yaml changed |
| Permission Changed | Permissions updated | chmod 755 -> 644 |
| Owner Changed | Ownership changed | chown user |
| File Created | New file detected | New file created |
| File Deleted | File removed | File deleted |
| Hash Mismatch | Integrity violation | Hash changed |

### Configuration

```go
type FileIntegrityMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []WatchPathConfig `json:"watch_paths"`
    HashAlgorithm     string            `json:"hash_algorithm"` // "sha256", "sha512"
    SoundOnChange     bool              `json:"sound_on_change"`
    SoundOnCreate     bool              `json:"sound_on_create"]
    SoundOnDelete     bool              `json:"sound_on_delete"]
    SoundOnPerms      bool              `json:"sound_on_perms"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type WatchPathConfig struct {
    Path        string `json:"path"` // "/etc", "/var/www"
    Recursive   bool   `json:"recursive"` // true
    Exclude     []string `json:"exclude"` // patterns to skip
}

type FileIntegrityEvent struct {
    Path        string
    ChangeType  string // "modified", "created", "deleted", "permissions", "owner"
    OldHash     string
    NewHash     string
    OldPerms    string
    NewPerms    string
    User        string
    EventType   string // "change", "create", "delete", "perms", "owner"
}
```

### Commands

```bash
/ccbell:integrity status              # Show integrity status
/ccbell:integrity add /etc            # Add path to watch
/ccbell:integrity remove /etc
/ccbell:integrity scan                # Run full scan
/ccbell:integrity sound change <sound>
/ccbell:integrity test                # Test integrity sounds
```

### Output

```
$ ccbell:integrity status

=== Sound Event File Integrity Monitor ===

Status: Enabled
Hash Algorithm: sha256
Change Sounds: Yes
Create Sounds: Yes
Delete Sounds: Yes

Watched Paths: 2

[1] /etc (Recursive)
    Files: 450
    Last Scan: 5 min ago
    Changes: 0
    Sound: bundled:integrity-etc

[2] /var/www/app (Recursive)
    Files: 1200
    Last Scan: 10 min ago
    Changes: 2
    Sound: bundled:integrity-app

Recent Events:
  [1] /var/www/app/config/prod.json (5 min ago)
       Permissions changed: 644 -> 600
  [2] /var/www/app/uploads/new.jpg (10 min ago)
       File created: 2.5 MB
  [3] /etc/nginx/nginx.conf (1 hour ago)
       Hash changed: [sha256 mismatch]

Integrity Statistics:
  Monitored Files: 1650
  Changes Today: 5
  Critical: 0

Sound Settings:
  Change: bundled:integrity-change
  Create: bundled:integrity-create
  Delete: bundled:integrity-delete
  Perms: bundled:integrity-perms

[Configure] [Add Path] [Scan All]
```

---

## Audio Player Compatibility

File integrity monitoring doesn't play sounds directly:
- Monitoring feature using find/stat/sha256sum
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File Integrity Monitor

```go
type FileIntegrityMonitor struct {
    config          *FileIntegrityMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    baseline        map[string]*FileInfo
    lastEventTime   map[string]time.Time
}

type FileInfo struct {
    Path       string
    Hash       string
    Perms      string
    Owner      string
    Group      string
    Size       int64
    ModTime    time.Time
    IsDir      bool
}

func (m *FileIntegrityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.baseline = make(map[string]*FileInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FileIntegrityMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Build initial baseline
    m.buildBaseline()

    for {
        select {
        case <-ticker.C:
            m.checkForChanges()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileIntegrityMonitor) buildBaseline() {
    for _, wp := range m.config.WatchPaths {
        m.scanPath(wp.Path, wp.Recursive, true)
    }
}

func (m *FileIntegrityMonitor) checkForChanges() {
    for _, wp := range m.config.WatchPaths {
        m.scanPath(wp.Path, wp.Recursive, false)
    }
}

func (m *FileIntegrityMonitor) scanPath(path string, recursive bool, building bool) {
    var walkFunc filepath.WalkFunc

    walkFunc = func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return nil
        }

        // Check exclusions
        for _, pattern := range m.config.Exclude {
            if matched, _ := filepath.Match(pattern, filepath.Base(path)); matched {
                if info.IsDir() && pattern[len(pattern)-1] != '/' {
                    return nil
                }
                return nil
            }
        }

        key := path
        fileInfo := m.getFileInfo(path, info)

        if building {
            // Building baseline
            m.baseline[key] = fileInfo
            return nil
        }

        lastInfo := m.baseline[key]
        if lastInfo == nil {
            // New file created
            m.baseline[key] = fileInfo
            if m.config.SoundOnCreate {
                m.onFileCreated(fileInfo)
            }
            return nil
        }

        // Check for modifications
        m.evaluateFileChanges(path, fileInfo, lastInfo)

        // Update baseline
        m.baseline[key] = fileInfo

        return nil
    }

    if recursive {
        filepath.Walk(path, walkFunc)
    } else {
        entries, _ := os.ReadDir(path)
        for _, entry := range entries {
            fullPath := filepath.Join(path, entry.Name())
            info, _ := entry.Info()
            walkFunc(fullPath, info, nil)
        }
    }
}

func (m *FileIntegrityMonitor) getFileInfo(path string, info os.FileInfo) *FileInfo {
    fileInfo := &FileInfo{
        Path:    path,
        Size:    info.Size(),
        ModTime: info.ModTime(),
        IsDir:   info.IsDir(),
    }

    // Get permissions
    fileInfo.Perms = info.Mode().Perm().String()

    // Get owner
    stat := info.Sys().(*syscall.Stat_t)
    user, _ := user.LookupId(strconv.Itoa(int(stat.Uid)))
    fileInfo.Owner = user.Name

    // Calculate hash for non-directories
    if !info.IsDir() {
        fileInfo.Hash = m.calculateHash(path)
    }

    return fileInfo
}

func (m *FileIntegrityMonitor) calculateHash(path string) string {
    var cmd *exec.Cmd

    switch m.config.HashAlgorithm {
    case "sha512":
        cmd = exec.Command("sha512sum", path)
    default:
        cmd = exec.Command("sha256sum", path)
    }

    output, err := cmd.Output()
    if err != nil {
        return ""
    }

    parts := strings.Fields(string(output))
    if len(parts) > 0 {
        return parts[0]
    }

    return ""
}

func (m *FileIntegrityMonitor) evaluateFileChanges(path string, newInfo *FileInfo, lastInfo *FileInfo) {
    // Check hash change
    if newInfo.Hash != "" && lastInfo.Hash != "" && newInfo.Hash != lastInfo.Hash {
        m.onFileChanged(path, newInfo, lastInfo)
    }

    // Check permission change
    if newInfo.Perms != lastInfo.Perms {
        m.onPermsChanged(path, newInfo, lastInfo)
    }

    // Check owner change
    if newInfo.Owner != lastInfo.Owner {
        m.onOwnerChanged(path, newInfo, lastInfo)
    }
}

func (m *FileIntegrityMonitor) onFileChanged(path string, newInfo *FileInfo, lastInfo *FileInfo) {
    if !m.config.SoundOnChange {
        return
    }

    key := fmt.Sprintf("change:%s", path)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["change"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FileIntegrityMonitor) onFileCreated(newInfo *FileInfo) {
    if !m.config.SoundOnCreate {
        return
    }

    key := fmt.Sprintf("create:%s", newInfo.Path)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["create"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileIntegrityMonitor) onPermsChanged(path string, newInfo *FileInfo, lastInfo *FileInfo) {
    if !m.config.SoundOnPerms {
        return
    }

    key := fmt.Sprintf("perms:%s", path)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["perms"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FileIntegrityMonitor) onOwnerChanged(path string, newInfo *FileInfo, lastInfo *FileInfo) {
    // Optional: sound for owner changes
}

func (m *FileIntegrityMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| sha256sum | System Tool | Free | Hash calculation |
| find | System Tool | Free | File enumeration |

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
| macOS | Supported | Uses shasum, find |
| Linux | Supported | Uses sha256sum, find |
