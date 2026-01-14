# Feature: Sound Event Certificate Expiry Monitor

Play sounds for SSL/TLS certificate expiration, renewal reminders, and revocation events.

## Summary

Monitor SSL/TLS certificates for expiration dates, renewal requirements, and revocation status, playing sounds for certificate events.

## Motivation

- Certificate awareness
- Expiration alerts
- Renewal reminders
- Security compliance
- Certificate health

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Certificate Events

| Event | Description | Example |
|-------|-------------|---------|
| Expiring Soon | < 30 days | 15 days left |
| Expiring Critical | < 7 days | 3 days left |
| Expired | Certificate expired | past expiry |
| Revoked | Certificate revoked | CRL |
| Renewed | New certificate | replaced |
| New Certificate | New cert installed | new cert |

### Configuration

```go
type CertificateExpiryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchCertificates []string          `json:"watch_certificates"` // "/etc/ssl/certs/*", domains
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    CheckOCSP         bool              `json:"check_ocsp"` // true default
    SoundOnExpiring   bool              `json:"sound_on_expiring"`
    SoundOnExpired    bool              `json:"sound_on_expired"`
    SoundOnRevoked    bool              `json:"sound_on_revoked"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"check_interval_hours"` // 24 default
}
```

### Commands

```bash
/ccbell:cert status                 # Show certificate status
/ccbell:cert add example.com        # Add certificate to watch
/ccbell:cert add /etc/ssl/certs/*
/ccbell:cert warning 30             # Set warning days
/ccbell:cert sound expiring <sound>
/ccbell:cert test                   # Test cert sounds
```

### Output

```
$ ccbell:cert status

=== Sound Event Certificate Expiry Monitor ===

Status: Enabled
Warning: 30 days
Critical: 7 days

Certificate Status:

[1] example.com
    Status: VALID
    Issuer: Let's Encrypt
    Expires: Feb 14, 2026 (31 days)
    Days Left: 31
    Algorithm: ECDSA P-256
    Sound: bundled:cert-example

[2] api.example.com
    Status: EXPIRING SOON *** WARNING ***
    Issuer: DigiCert
    Expires: Jan 20, 2026 (7 days)
    Days Left: 7 *** CRITICAL ***
    Algorithm: RSA 2048
    Sound: bundled:cert-api *** WARNING ***

[3] old.example.com
    Status: EXPIRED *** EXPIRED ***
    Issuer: Comodo
    Expires: Jan 1, 2026 (-13 days)
    Days Left: -13
    Algorithm: RSA 2048
    Sound: bundled:cert-old *** FAILED ***

[4] internal.company.local
    Status: VALID
    Issuer: Company Internal CA
    Expires: Jun 1, 2026 (138 days)
    Days Left: 138
    Algorithm: RSA 4096
    Sound: bundled:cert-internal

Certificate Chain:

  example.com:
    Leaf: ISRG Root X1
    Intermediate: Let's Encrypt R3
    Root: Self-signed

Recent Events:
  [1] api.example.com: Expiring Critical (1 hour ago)
       7 days remaining
       Sound: bundled:cert-critical
  [2] old.example.com: Expired (1 day ago)
       13 days past expiry
       Sound: bundled:cert-expired
  [3] example.com: Certificate Renewed (2 weeks ago)
       New certificate installed
       Sound: bundled:cert-renewed

Certificate Statistics:
  Total Certificates: 4
  Valid: 2
  Expiring: 1
  Expired: 1
  Avg Days Left: 41

Sound Settings:
  Expiring: bundled:cert-expiring
  Expired: bundled:cert-expired
  Critical: bundled:cert-critical
  Revoked: bundled:cert-revoked

[Configure] [Add Certificate] [Test All]
```

---

## Audio Player Compatibility

Certificate monitoring doesn't play sounds directly:
- Monitoring feature using openssl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Certificate Expiry Monitor

```go
type CertificateExpiryMonitor struct {
    config          *CertificateExpiryMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    certState       map[string]*CertificateInfo
    lastEventTime   map[string]time.Time
}

type CertificateInfo struct {
    Path          string
    Domain        string
    Issuer        string
    Subject       string
    NotBefore     time.Time
    NotAfter      time.Time
    DaysLeft      int
    Status        string // "valid", "expiring", "critical", "expired", "revoked"
    Algorithm     string
    Serial        string
    Fingerprint   string
    LastCheck     time.Time
}

func (m *CertificateExpiryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.certState = make(map[string]*CertificateInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CertificateExpiryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Hour)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotCertState()

    for {
        select {
        case <-ticker.C:
            m.checkCertState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CertificateExpiryMonitor) snapshotCertState() {
    m.checkCertState()
}

func (m *CertificateExpiryMonitor) checkCertState() {
    for _, certPath := range m.config.WatchCertificates {
        // Handle glob patterns
        if strings.Contains(certPath, "*") {
            files := m.expandGlob(certPath)
            for _, file := range files {
                info := m.checkCertificate(file)
                if info != nil {
                    m.processCertStatus(info)
                }
            }
        } else if strings.HasPrefix(certPath, "http://") || strings.HasPrefix(certPath, "https://") {
            info := m.checkRemoteCertificate(certPath)
            if info != nil {
                m.processCertStatus(info)
            }
        } else {
            info := m.checkCertificate(certPath)
            if info != nil {
                m.processCertStatus(info)
            }
        }
    }
}

func (m *CertificateExpiryMonitor) checkCertificate(certPath string) *CertificateInfo {
    info := &CertificateInfo{
        Path:      certPath,
        LastCheck: time.Now(),
    }

    // Get certificate details
    cmd := exec.Command("openssl", "x509", "-in", certPath, "-noout", "-text")
    output, err := cmd.Output()

    if err != nil {
        // Try to parse as domain
        return m.checkRemoteCertificate("https://" + certPath)
    }

    info = m.parseCertificateOutput(info, string(output))

    // Get expiration date
    cmd = exec.Command("openssl", "x509", "-in", certPath, "-noend", "-dates")
    dateOutput, _ := cmd.Output()
    info = m.parseCertificateDates(info, string(dateOutput))

    // Calculate days left
    now := time.Now()
    info.DaysLeft = int(info.NotAfter.Sub(now).Hours() / 24)

    // Determine status
    info.Status = m.calculateCertStatus(info.DaysLeft)

    return info
}

func (m *CertificateExpiryMonitor) checkRemoteCertificate(domain string) *CertificateInfo {
    info := &CertificateInfo{
        Domain:    domain,
        LastCheck: time.Now(),
    }

    // Extract hostname
    u, _ := url.Parse(domain)
    hostname := u.Hostname()
    port := u.Port()
    if port == "" {
        port = "443"
    }

    // Get certificate using openssl s_client
    cmd := exec.Command("openssl", "s_client", "-connect",
        fmt.Sprintf("%s:%s", hostname, port), "-servername", hostname)
    cmd.Stdin = strings.NewReader("QUIT\n")

    output, err := cmd.Output()
    if err != nil {
        info.Status = "unreachable"
        return info
    }

    info = m.parseCertificateOutput(info, string(output))

    // Calculate days left
    now := time.Now()
    info.DaysLeft = int(info.NotAfter.Sub(now).Hours() / 24)
    info.Status = m.calculateCertStatus(info.DaysLeft)

    return info
}

func (m *CertificateExpiryMonitor) parseCertificateOutput(info *CertificateInfo, output string) *CertificateInfo {
    // Parse issuer
    issuerRe := regexp.MustEach(`Issuer:\s*(.+)`)
    matches := issuerRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.Issuer = strings.TrimSpace(matches[1])
    }

    // Parse subject
    subjectRe := regexp.MustEach(`Subject:\s*(.+)`)
    matches = subjectRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.Subject = strings.TrimSpace(matches[1])
    }

    // Parse algorithm
    algoRe := regexp.MustEach(`Signature Algorithm:\s*(.+)`)
    matches = algoRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.Algorithm = strings.TrimSpace(matches[1])
    }

    // Parse serial
    serialRe := regexp.MustEach(`Serial Number:\s*(.+)`)
    matches = serialRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.Serial = strings.TrimSpace(matches[1])
    }

    return info
}

func (m *CertificateExpiryMonitor) parseCertificateDates(info *CertificateInfo, output string) *CertificateInfo {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if strings.HasPrefix(line, "notAfter=") {
            dateStr := strings.TrimPrefix(line, "notAfter=")
            t, _ := time.Parse("Jan  2 15:04:05 2006 MST", dateStr)
            info.NotAfter = t
        } else if strings.HasPrefix(line, "notBefore=") {
            dateStr := strings.TrimPrefix(line, "notBefore=")
            t, _ := time.Parse("Jan  2 15:04:05 2006 MST", dateStr)
            info.NotBefore = t
        }
    }
    return info
}

func (m *CertificateExpiryMonitor) calculateCertStatus(daysLeft int) string {
    if daysLeft < 0 {
        return "expired"
    }
    if daysLeft <= m.config.CriticalDays {
        return "critical"
    }
    if daysLeft <= m.config.WarningDays {
        return "expiring"
    }
    return "valid"
}

func (m *CertificateExpiryMonitor) expandGlob(pattern string) []string {
    var files []string
    matches, err := filepath.Glob(pattern)
    if err == nil {
        for _, match := range matches {
            if info, err := os.Stat(match); err == nil && !info.IsDir() {
                files = append(files, match)
            }
        }
    }
    return files
}

func (m *CertificateExpiryMonitor) processCertStatus(info *CertificateInfo) {
    key := info.Path
    if info.Domain != "" {
        key = info.Domain
    }

    lastInfo := m.certState[key]

    if lastInfo == nil {
        m.certState[key] = info
        if info.Status == "expired" && m.config.SoundOnExpired {
            m.onCertExpired(info)
        } else if info.Status == "critical" && m.config.SoundOnExpiring {
            m.onCertCritical(info)
        } else if info.Status == "expiring" && m.config.SoundOnExpiring {
            m.onCertExpiring(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "expired":
            if m.config.SoundOnExpired {
                m.onCertExpired(info)
            }
        case "critical":
            if m.config.SoundOnExpiring {
                m.onCertCritical(info)
            }
        case "expiring":
            if m.config.SoundOnExpiring {
                m.onCertExpiring(info)
            }
        case "valid":
            if lastInfo.Status == "expired" || lastInfo.Status == "critical" {
                // Certificate was renewed
            }
        }
    }

    m.certState[key] = info
}

func (m *CertificateExpiryMonitor) onCertExpiring(info *CertificateInfo) {
    key := fmt.Sprintf("expiring:%s", info.Path)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["expiring"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CertificateExpiryMonitor) onCertCritical(info *CertificateInfo) {
    key := fmt.Sprintf("critical:%s", info.Path)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CertificateExpiryMonitor) onCertExpired(info *CertificateInfo) {
    key := fmt.Sprintf("expired:%s", info.Path)
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["expired"]
        if sound != "" {
            m.player.Play(sound, 0.6)
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
| openssl | System Tool | Free | SSL/TLS toolkit |

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
