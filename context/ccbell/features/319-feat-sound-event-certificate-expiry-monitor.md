# Feature: Sound Event Certificate Expiry Monitor

Play sounds for SSL/TLS certificate expiration warnings.

## Summary

Monitor SSL/TLS certificate expiration and renewal, playing sounds for certificate events.

## Motivation

- Certificate expiry alerts
- Security certificate awareness
- Renewal reminders
- Trust chain monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Certificate Events

| Event | Description | Example |
|-------|-------------|---------|
| Expiring Soon | < 30 days | Renewal needed |
| Expired | Certificate expired | Cert invalid |
| Renewed | New cert installed | Chain updated |
| Expiring Today | < 24 hours | Critical |

### Configuration

```go
type CertificateExpiryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "/etc/ssl", "/etc/letsencrypt"
    WatchDomains      []string          `json:"watch_domains"] // "example.com"
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnExpired    bool              `json:"sound_on_expired"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 86400 default (1 day)
}

type CertificateEvent struct {
    Path       string
    CommonName string
    Issuer     string
    NotBefore  time.Time
    NotAfter   time.Time
    DaysLeft   int
    EventType  string // "warning", "expired", "renewed", "critical"
}
```

### Commands

```bash
/ccbell:cert status                   # Show certificate status
/ccbell:cert add /etc/ssl             # Add path to watch
/ccbell:cert add example.com          # Add domain to check
/ccbell:cert remove example.com
/ccbell:cert warning 30               # Set warning days
/ccbell:cert sound warning <sound>
/ccbell:cert test                     # Test certificate sounds
```

### Output

```
$ ccbell:cert status

=== Sound Event Certificate Expiry Monitor ===

Status: Enabled
Warning: 30 days
Critical: 7 days

Watched Paths: 2
Watched Domains: 3

[1] /etc/ssl/certs/example.com.crt
    CN: example.com
    Issuer: Let's Encrypt
    Expires: 30 days
    Status: WARNING
    Sound: bundled:cert-warning

[2] /etc/letsencrypt/live/mail.example.com/
    CN: mail.example.com
    Issuer: Let's Encrypt
    Expires: 45 days
    Status: OK
    Sound: bundled:stop

[3] api.example.com:443
    CN: api.example.com
    Issuer: DigiCert
    Expires: 90 days
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] example.com: Expiring Soon (5 min ago)
       30 days remaining
  [2] mail.example.com: Certificate Renewed (1 week ago)
       New cert installed
  [3] old.example.com: Expired (2 weeks ago)
       Certificate has expired

Certificate Statistics:
  Valid: 5
  Expiring soon: 1
  Expired: 0

Sound Settings:
  Warning: bundled:cert-warning
  Expired: bundled:cert-expired
  Critical: bundled:cert-critical

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Certificate monitoring doesn't play sounds directly:
- Monitoring feature using OpenSSL
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Certificate Expiry Monitor

```go
type CertificateExpiryMonitor struct {
    config            *CertificateExpiryMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    certState         map[string]*CertInfo
    lastEventTime     map[string]time.Time
}

type CertInfo struct {
    Path      string
    CommonName string
    Issuer    string
    NotBefore time.Time
    NotAfter  time.Time
    DaysLeft  int
}

func (m *CertificateExpiryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.certState = make(map[string]*CertInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CertificateExpiryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCertificates()

    for {
        select {
        case <-ticker.C:
            m.checkCertificates()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CertificateExpiryMonitor) snapshotCertificates() {
    // Scan watched paths for certificates
    for _, path := range m.config.WatchPaths {
        m.scanCertificatePath(path)
    }

    // Check watched domains
    for _, domain := range m.config.WatchDomains {
        m.checkDomainCertificate(domain)
    }
}

func (m *CertificateExpiryMonitor) scanCertificatePath(path string) {
    entries, err := os.ReadDir(path)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if entry.IsDir() {
            // Check for certificate directories (like letsencrypt live)
            m.scanCertificatePath(filepath.Join(path, entry.Name()))
            continue
        }

        // Check file extensions
        ext := filepath.Ext(entry.Name())
        if ext == ".crt" || ext == ".pem" || ext == ".cert" || ext == ".cer" {
            certPath := filepath.Join(path, entry.Name())
            m.parseCertificate(certPath)
        }
    }
}

func (m *CertificateExpiryMonitor) checkDomainCertificate(domain string) {
    // Check if domain includes port
    hostPort := domain
    if !strings.Contains(domain, ":") {
        hostPort = domain + ":443"
    }

    // Get certificate using openssl
    cmd := exec.Command("openssl", "s_client", "-connect", hostPort, "-servername", domain)
    stdin, _ := cmd.StdinPipe()
    stdin.Write([]byte("QUIT\n"))
    stdin.Close()

    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Extract certificate from output
    certData := m.extractCertificate(string(output))
    if certData != "" {
        m.parseCertificateData(domain, certData)
    }
}

func (m *CertificateExpiryMonitor) parseCertificate(path string) {
    cmd := exec.Command("openssl", "x509", "-in", path, "-noout", "-dates", "-subject", "-issuer")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    certInfo := m.parseOpenSSLOutput(string(output))
    if certInfo != nil {
        certInfo.Path = path
        m.certState[path] = certInfo
        m.evaluateCertStatus(path, certInfo)
    }
}

func (m *CertificateExpiryMonitor) parseCertificateData(name string, data string) {
    cmd := exec.Command("openssl", "x509")
    stdin, _ := cmd.StdinPipe()
    stdin.Write([]byte(data))
    stdin.Close()

    output, err := cmd.Output()
    if err != nil {
        return
    }

    certInfo := m.parseOpenSSLOutput(string(output))
    if certInfo != nil {
        certInfo.Path = name
        m.certState[name] = certInfo
        m.evaluateCertStatus(name, certInfo)
    }
}

func (m *CertificateExpiryMonitor) parseOpenSSLOutput(output string) *CertInfo {
    info := &CertInfo{}

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "notBefore=") {
            dateStr := strings.TrimPrefix(line, "notBefore=")
            t, _ := time.Parse("Jan  2 15:04:05 2006 MST", dateStr)
            info.NotBefore = t
        } else if strings.HasPrefix(line, "notAfter=") {
            dateStr := strings.TrimPrefix(line, "notAfter=")
            t, _ := time.Parse("Jan  2 15:04:05 2006 MST", dateStr)
            info.NotAfter = t
        } else if strings.HasPrefix(line, "subject=") {
            subject := strings.TrimPrefix(line, "subject=")
            // Extract CN from subject
            if cn := m.extractCN(subject); cn != "" {
                info.CommonName = cn
            }
        } else if strings.HasPrefix(line, "issuer=") {
            info.Issuer = strings.TrimPrefix(line, "issuer=")
        }
    }

    // Calculate days left
    now := time.Now()
    info.DaysLeft = int(info.NotAfter.Sub(now).Hours() / 24)

    return info
}

func (m *CertificateExpiryMonitor) extractCN(subject string) string {
    // Parse subject string for CN
    re := regexp.MustCompile(`CN = ([^,]+)`)
    match := re.FindStringSubmatch(subject)
    if match != nil {
        return strings.TrimSpace(match[1])
    }
    return ""
}

func (m *CertificateExpiryMonitor) extractCertificate(output string) string {
    // Extract certificate block from s_client output
    start := strings.Index(output, "-----BEGIN CERTIFICATE-----")
    if start == -1 {
        return ""
    }

    end := strings.Index(output, "-----END CERTIFICATE-----")
    if end == -1 {
        return ""
    }

    return output[start : end+len("-----END CERTIFICATE-----")]
}

func (m *CertificateExpiryMonitor) checkCertificates() {
    // Re-scan all certificates
    m.snapshotCertificates()
}

func (m *CertificateExpiryMonitor) evaluateCertStatus(path string, cert *CertInfo) {
    lastCert := m.certState[path]

    // First time seeing this cert
    if lastCert == nil {
        return
    }

    // Check expiration status
    if cert.DaysLeft <= 0 {
        // Expired
        m.onCertificateExpired(path, cert)
    } else if cert.DaysLeft <= m.config.CriticalDays {
        // Critical - expiring soon
        if lastCert.DaysLeft > m.config.CriticalDays {
            m.onCertificateCritical(path, cert)
        }
    } else if cert.DaysLeft <= m.config.WarningDays {
        // Warning
        if lastCert.DaysLeft > m.config.WarningDays {
            m.onCertificateWarning(path, cert)
        }
    }
}

func (m *CertificateExpiryMonitor) onCertificateWarning(path string, cert *CertInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%s", path)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CertificateExpiryMonitor) onCertificateCritical(path string, cert *CertInfo) {
    key := fmt.Sprintf("critical:%s", path)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *CertificateExpiryMonitor) onCertificateExpired(path string, cert *CertInfo) {
    if !m.config.SoundOnExpired {
        return
    }

    key := fmt.Sprintf("expired:%s", path)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["expired"]
        if sound != "" {
            m.player.Play(sound, 0.8)
        }
    }
}

func (m *CertificateExpiryMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| openssl | System Tool | Free | Certificate parsing |

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
| macOS | Supported | Uses openssl |
| Linux | Supported | Uses openssl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
