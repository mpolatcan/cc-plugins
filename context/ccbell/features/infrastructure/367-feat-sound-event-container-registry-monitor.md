# Feature: Sound Event Container Registry Monitor

Play sounds for container image updates, tag changes, and registry events.

## Summary

Monitor container registry for new image versions, security advisories, and image updates, playing sounds for registry events.

## Motivation

- Image update awareness
- Security patch notifications
- Version change tracking
- Registry sync feedback
- Image vulnerability alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Container Registry Events

| Event | Description | Example |
|-------|-------------|---------|
| New Tag | New image tag created | v1.2.3 released |
| Image Updated | Image digest changed | New build available |
| Manifest Changed | Image manifest updated | Architecture change |
| Tag Deleted | Tag removed | Old version cleaned |
| Vulnerability | Security advisory | CVE in image |

### Configuration

```go
type ContainerRegistryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Registries        []RegistryConfig  `json:"registries"`
    SoundOnUpdate     bool              `json:"sound_on_update"`
    SoundOnNewTag     bool              `json:"sound_on_new_tag"]
    SoundOnVuln       bool              `json:"sound_on_vuln"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 3600 default
}

type RegistryConfig struct {
    Name     string `json:"name"` // "dockerhub", "ghcr"
    URL      string `json:"url"` // "docker.io/library/nginx"
    Username string `json:"username"` // optional
    Password string `json:"password"` // optional
    Token    string `json:"token"` // optional
}

type ContainerRegistryEvent struct {
    Registry    string
    Image       string
    Tag         string
    Digest      string
    EventType   string // "update", "new_tag", "delete", "vuln"
    Severity    string // "low", "medium", "high", "critical"
}
```

### Commands

```bash
/ccbell:registry status               # Show registry status
/ccbell:registry add docker.io/nginx  # Add image to watch
/ccbell:registry remove docker.io/nginx
/ccbell:registry sound update <sound>
/ccbell:registry sound vuln <sound>
/ccbell:registry test                 # Test registry sounds
```

### Output

```
$ ccbell:registry status

=== Sound Event Container Registry Monitor ===

Status: Enabled
Update Sounds: Yes
New Tag Sounds: Yes
Vuln Sounds: Yes

Monitored Registries: 2

[1] docker.io/library/nginx
    Latest Tag: 1.25.3
    Digest: sha256:abc123...
    Last Check: 5 min ago
    Sound: bundled:registry-nginx

[2] ghcr.io/myorg/app
    Latest Tag: v2.1.0
    Digest: sha256:def456...
    Last Check: 10 min ago
    Sound: bundled:registry-app

Recent Events:
  [1] docker.io/nginx: New Tag (5 min ago)
       1.25.2 -> 1.25.3
  [2] ghcr.io/myorg/app: Update Available (1 hour ago)
       v2.0.0 -> v2.1.0
  [3] docker.io/nginx: Vulnerability (2 hours ago)
       CVE-2024-1234 (High)

Registry Statistics:
  Monitored Images: 2
  Updates Today: 3
  Vulnerabilities: 1

Sound Settings:
  Update: bundled:registry-update
  New Tag: bundled:registry-tag
  Vulnerability: bundled:registry-vuln

[Configure] [Add Image] [Test All]
```

---

## Audio Player Compatibility

Registry monitoring doesn't play sounds directly:
- Monitoring feature using curl/skopeo
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Container Registry Monitor

```go
type ContainerRegistryMonitor struct {
    config          *ContainerRegistryMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    imageState      map[string]*ImageInfo
    lastEventTime   map[string]time.Time
}

type ImageInfo struct {
    Registry  string
    Image     string
    Tag       string
    Digest    string
    Manifest  string
    LastCheck time.Time
}

func (m *ContainerRegistryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.imageState = make(map[string]*ImageInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ContainerRegistryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.checkAllImages()

    for {
        select {
        case <-ticker.C:
            m.checkAllImages()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ContainerRegistryMonitor) checkAllImages() {
    for _, reg := range m.config.Registries {
        m.checkImage(&reg)
    }
}

func (m *ContainerRegistryMonitor) checkImage(reg *RegistryConfig) {
    key := fmt.Sprintf("%s/%s", reg.Name, reg.Image)

    // Get current image digest
    cmd := exec.Command("skopeo", "inspect", fmt.Sprintf("docker://%s:%s", reg.URL, "latest"))
    if reg.Token != "" {
        cmd = exec.Command("skopeo", "inspect",
            "--creds", fmt.Sprintf("%s:%s", reg.Username, reg.Password),
            fmt.Sprintf("docker://%s:%s", reg.URL, "latest"))
    }

    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse JSON output
    info := m.parseSkopeoOutput(string(output), reg)
    if info == nil {
        return
    }

    lastInfo := m.imageState[key]
    if lastInfo == nil {
        m.imageState[key] = info
        return
    }

    // Check for changes
    if lastInfo.Digest != info.Digest {
        m.onImageUpdated(key, info, lastInfo)
    }

    if lastInfo.Tag != info.Tag {
        m.onNewTag(key, info, lastInfo)
    }

    m.imageState[key] = info
}

func (m *ContainerRegistryMonitor) parseSkopeoOutput(output string, reg *RegistryConfig) *ImageInfo {
    // This is a simplified parser - would need full JSON parsing
    // Look for "Digest" and "Tags" in the JSON output

    info := &ImageInfo{
        Registry:  reg.Name,
        Image:     reg.Image,
        LastCheck: time.Now(),
    }

    // Extract digest
    re := regexp.MustCompile(`"Digest":\s*"([^"]+)"`)
    match := re.FindStringSubmatch(output)
    if match != nil {
        info.Digest = match[1]
    }

    // Extract tag
    tagRe := regexp.MustCompile(`"Tag":\s*"([^"]+)"`)
    tagMatch := tagRe.FindStringSubmatch(output)
    if tagMatch != nil {
        info.Tag = tagMatch[1]
    }

    return info
}

func (m *ContainerRegistryMonitor) onImageUpdated(key string, newInfo *ImageInfo, lastInfo *ImageInfo) {
    if !m.config.SoundOnUpdate {
        return
    }

    key = fmt.Sprintf("update:%s", key)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["update"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ContainerRegistryMonitor) onNewTag(key string, newInfo *ImageInfo, lastInfo *ImageInfo) {
    if !m.config.SoundOnNewTag {
        return
    }

    key = fmt.Sprintf("new_tag:%s", key)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["new_tag"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ContainerRegistryMonitor) onVulnerability(key string, severity string) {
    if !m.config.SoundOnVuln {
        return
    }

    key = fmt.Sprintf("vuln:%s:%s", key, severity)
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["vuln"]
        if sound != "" {
            volume := 0.5
            if severity == "critical" {
                volume = 0.7
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *ContainerRegistryMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| skopeo | System Tool | Free | Container image inspection |
| curl | System Tool | Free | Registry API calls |

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
| macOS | Supported | Uses skopeo, curl |
| Linux | Supported | Uses skopeo, curl |
