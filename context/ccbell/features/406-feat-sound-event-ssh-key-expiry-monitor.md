# Feature: Sound Event SSH Key Expiry Monitor

Play sounds for SSH key expiration warnings, certificate expiry, and key regeneration reminders.

## Summary

Monitor SSH keys and certificates for expiration dates, providing alerts before keys expire, playing sounds for expiry events.

## Motivation

- Key expiration awareness
- Certificate management
- Automated key rotation
- Security compliance
- Access continuity

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSH Key Expiry Events

| Event | Description | Example |
|-------|-------------|---------|
| Key Expiring Soon | Days to expire | < 7 days |
| Key Expired | Key has expired | today |
| CA Certificate Expiry | CA cert expiring | < 30 days |
| New Key Generated | Key created | new RSA key |
| Key Revoked | Key was revoked | compromised |

### Configuration

```go
type SSHKeyExpiryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "~/.ssh", "/etc/ssh", "*"
    WarningDays       int               `json:"warning_days"` // 30 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnExpired    bool              `json:"sound_on_expired"`
    SoundOnNew        bool              `json:"sound_on_new"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 86400 default
}
```

### Commands

```bash
/ccbell:sshkey status                  # Show SSH key status
/ccbell:sshkey add ~/.ssh              # Add path to watch
/ccbell:sshkey warning 30              # Set warning days
/ccbell:sshkey sound warning <sound>
/ccbell:sshkey sound expired <sound>
/ccbell:sshkey test                    # Test SSH key sounds
```

### Output

```
$ ccbell:sshkey status

=== Sound Event SSH Key Expiry Monitor ===

Status: Enabled
Warning Threshold: 30 days
Warning Sounds: Yes
Expired Sounds: Yes

Watched Paths: 2

SSH Key Status:

[1] ~/.ssh/id_ed25519 (Ed25519)
    Status: VALID
    Expires: In 45 days
    Comment: work key
    Sound: bundled:sshkey-ed25519

[2] ~/.ssh/id_rsa (RSA 2048-bit)
    Status: EXPIRING SOON
    Expires: In 5 days
    Comment: old key
    Sound: bundled:sshkey-rsa *** WARNING ***

[3] ~/.ssh/id_ecdsa (ECDSA)
    Status: VALID
    Expires: In 180 days
    Comment: backup key
    Sound: bundled:sshkey-ecdsa

[4] /etc/ssh/ssh_host_rsa_key (RSA)
    Status: VALID
    Expires: Never (host key)
    Comment: host key
    Sound: bundled:sshkey-host

Recent Events:
  [1] ~/.ssh/id_rsa: Key Expiring Soon (1 day ago)
       5 days remaining
  [2] ~/.ssh/id_ed25519: New Key Generated (1 month ago)
       Created new Ed25519 key
  [3] ~/.ssh/id_ecdsa: Key Expiring (2 months ago)
       Renewed before expiration

Key Statistics:
  Total Keys: 4
  Valid: 3
  Expiring: 1
  Expired: 0

Sound Settings:
  Warning: bundled:sshkey-warning
  Expired: bundled:sshkey-expired
  New: bundled:sshkey-new

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

SSH key monitoring doesn't play sounds directly:
- Monitoring feature using ssh-keygen
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSH Key Expiry Monitor

```go
type SSHKeyExpiryMonitor struct {
    config          *SSHKeyExpiryMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    keyState        map[string]*SSHKeyInfo
    lastEventTime   map[string]time.Time
}

type SSHKeyInfo struct {
    Path       string
    Type       string // "RSA", "Ed25519", "ECDSA"
    Bits       int
    Comment    string
    ExpiresAt  time.Time
    Status     string // "valid", "expiring", "expired"
    CreatedAt  time.Time
}

func (m *SSHKeyExpiryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.keyState = make(map[string]*SSHKeyInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SSHKeyExpiryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotKeyState()

    for {
        select {
        case <-ticker.C:
            m.checkKeyState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSHKeyExpiryMonitor) snapshotKeyState() {
    for _, path := range m.config.WatchPaths {
        expandedPath := m.expandPath(path)
        m.scanDirectory(expandedPath)
    }
}

func (m *SSHKeyExpiryMonitor) checkKeyState() {
    currentKeys := m.listCurrentKeys()

    for path, keyInfo := range currentKeys {
        lastInfo := m.keyState[path]

        if lastInfo == nil {
            m.keyState[path] = keyInfo
            if m.config.SoundOnNew {
                m.onNewKey(keyInfo)
            }
            continue
        }

        // Check expiration status
        m.checkKeyExpiration(path, keyInfo, lastInfo)

        m.keyState[path] = keyInfo
    }
}

func (m *SSHKeyExpiryMonitor) scanDirectory(dirPath string) {
    entries, err := os.ReadDir(dirPath)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if entry.IsDir() {
            continue
        }

        name := entry.Name()
        // Match SSH key patterns
        if strings.HasPrefix(name, "id_") || strings.HasPrefix(name, "ssh_host_") {
            fullPath := filepath.Join(dirPath, name)
            keyInfo := m.getKeyInfo(fullPath)
            if keyInfo != nil {
                m.keyState[fullPath] = keyInfo
            }
        }
    }
}

func (m *SSHKeyExpiryMonitor) listCurrentKeys() map[string]*SSHKeyInfo {
    keys := make(map[string]*SSHKeyInfo)

    for _, path := range m.config.WatchPaths {
        expandedPath := m.expandPath(path)

        entries, err := os.ReadDir(expandedPath)
        if err != nil {
            continue
        }

        for _, entry := range entries {
            if entry.IsDir() {
                continue
            }

            name := entry.Name()
            if strings.HasPrefix(name, "id_") || strings.HasPrefix(name, "ssh_host_") {
                fullPath := filepath.Join(expandedPath, name)
                keyInfo := m.getKeyInfo(fullPath)
                if keyInfo != nil {
                    keys[fullPath] = keyInfo
                }
            }
        }
    }

    return keys
}

func (m *SSHKeyExpiryMonitor) getKeyInfo(path string) *SSHKeyInfo {
    // Check if file exists
    fileInfo, err := os.Stat(path)
    if err != nil {
        return nil
    }

    // Skip public keys
    if strings.HasSuffix(path, ".pub") {
        return nil
    }

    keyInfo := &SSHKeyInfo{
        Path:      path,
        CreatedAt: fileInfo.ModTime(),
    }

    // Use ssh-keygen to get key details
    cmd := exec.Command("ssh-keygen", "-l", "-f", path)
    output, err := cmd.Output()

    if err == nil {
        // Parse output: "2048 SHA256:xxx user@host (RSA)"
        outputStr := strings.TrimSpace(string(output))
        parts := strings.Fields(outputStr)

        if len(parts) >= 4 {
            // Parse key type and bits
            keyInfo.Bits, _ = strconv.Atoi(parts[0])

            // Extract type from comment
            for i, part := range parts {
                if part == "(RSA)" || part == "(ECDSA)" || part == "(Ed25519)" {
                    keyInfo.Type = strings.Trim(part, "()")
                    if i+1 < len(parts) {
                        keyInfo.Comment = strings.Join(parts[i+1:], " ")
                    }
                    break
                }
            }
        }
    }

    // Check for certificates (.crt, -cert.pub)
    certPath := path + "-cert.pub"
    if _, err := os.Stat(certPath); err == nil {
        m.parseCertificate(certPath, keyInfo)
    }

    // Set status based on expiration
    keyInfo.Status = m.getKeyStatus(keyInfo)

    return keyInfo
}

func (m *SSHKeyExpiryMonitor) parseCertificate(certPath string, keyInfo *SSHKeyInfo) {
    cmd := exec.Command("ssh-keygen", "-L", "-f", certPath)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Valid: forever") {
            keyInfo.ExpiresAt = time.Time{}
        } else if strings.Contains(line, "Valid: from") {
            // Parse expiration date
            re := regexp.MustEach(`to (\w+ \w+ \w+ \w+ \w+ \w+)`)
            // Extract date
            _ = re
        }
    }
}

func (m *SSHKeyExpiryMonitor) getKeyStatus(keyInfo *SSHKeyInfo) string {
    if keyInfo.ExpiresAt.IsZero() {
        return "valid" // No expiration
    }

    daysUntilExpiry := int(time.Until(keyInfo.ExpiresAt).Hours() / 24)

    if daysUntilExpiry < 0 {
        return "expired"
    } else if daysUntilExpiry <= m.config.WarningDays {
        return "expiring"
    }
    return "valid"
}

func (m *SSHKeyExpiryMonitor) checkKeyExpiration(path string, currentInfo, lastInfo *SSHKeyInfo) {
    if lastInfo.Status != currentInfo.Status {
        switch currentInfo.Status {
        case "expiring":
            if m.config.SoundOnWarning {
                m.onKeyExpiring(currentInfo)
            }
        case "expired":
            if m.config.SoundOnExpired {
                m.onKeyExpired(currentInfo)
            }
        }
    }
}

func (m *SSHKeyExpiryMonitor) onKeyExpiring(keyInfo *SSHKeyInfo) {
    daysUntil := int(time.Until(keyInfo.ExpiresAt).Hours() / 24)
    key := fmt.Sprintf("expiring:%s", keyInfo.Path)

    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSHKeyExpiryMonitor) onKeyExpired(keyInfo *SSHKeyInfo) {
    key := fmt.Sprintf("expired:%s", keyInfo.Path)

    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["expired"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SSHKeyExpiryMonitor) onNewKey(keyInfo *SSHKeyInfo) {
    key := fmt.Sprintf("new:%s", keyInfo.Path)

    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["new"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SSHKeyExpiryMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *SSHKeyExpiryMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ssh-keygen | System Tool | Free | SSH key management |
| os.ReadDir | Go Stdlib | Free | Directory reading |

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
| macOS | Supported | Uses ssh-keygen |
| Linux | Supported | Uses ssh-keygen |
