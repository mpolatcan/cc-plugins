# Feature: Sound Event SSL Certificate Monitor

Play sounds for SSL certificate expiration, renewal, and revocation events.

## Summary

Monitor SSL/TLS certificates for expiration dates, renewal requirements, and CRL status, playing sounds for certificate events.

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
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSL Certificate Events

| Event | Description | Example |
|-------|-------------|---------|
| Expiring Soon | < 30 days | 15 days left |
| Expiring Critical | < 7 days | 3 days left |
| Expired | Certificate expired | past expiry |
| Revoked | Certificate revoked | CRL check |
| Renewed | New certificate | replaced |
| New Certificate | New cert installed | new cert |

### Configuration

```go
type SSLCertificateMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchCerts      []string          `json:"watch_certs"` // cert paths or domains
    WarningDays     int               `json:"warning_days"` // 30 default
    CriticalDays    int               `json:"critical_days"` // 7 default
    CheckCRL        bool              `json:"check_crl"` // true default
    SoundOnExpiring bool              `json:"sound_on_expiring"`
    SoundOnExpired  bool              `json:"sound_on_expired"`
    SoundOnRevoked  bool              `json:"sound_on_revoked"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_hours"` // 24 default
}
```

### Commands

```bash
/ccbell:ssl status                  # Show certificate status
/ccbell:ssl add /etc/ssl/certs/cert.pem
/ccbell:ssl add example.com:443
/ccbell:ssl warning 30              # Set warning days
/ccbell:ssl sound expiring <sound>
/ccbell:ssl test                    # Test SSL sounds
```

### Output

```
$ ccbell:ssl status

=== Sound Event SSL Certificate Monitor ===

Status: Enabled
Warning: 30 days
Critical: 7 days

Certificate Status:

[1] /etc/ssl/certs/server.crt
    Status: VALID
    Issuer: Let's Encrypt
    Expires: Feb 14, 2026 (31 days)
    Days Left: 31
    Algorithm: ECDSA P-256
    Serial: ABC123...
    Sound: bundled:ssl-valid

[2] /etc/ssl/certs/api.crt
    Status: EXPIRING SOON *** WARNING ***
    Issuer: DigiCert
    Expires: Jan 20, 2026 (7 days)
    Days Left: 7 *** CRITICAL ***
    Algorithm: RSA 2048
    Sound: bundled:ssl-api *** WARNING ***

[3] /etc/ssl/certs/old.crt
    Status: EXPIRED *** EXPIRED ***
    Issuer: Comodo
    Expires: Jan 1, 2026 (-13 days)
    Days Left: -13
    Algorithm: RSA 2048
    Sound: bundled:ssl-old *** FAILED ***

Recent Events:

[1] /etc/ssl/certs/api.crt: Expiring Critical (5 min ago)
       7 days remaining
       Sound: bundled:ssl-expiring
  [2] /etc/ssl/certs/old.crt: Expired (1 day ago)
       13 days past expiry
       Sound: bundled:ssl-expired
  [3] /etc/ssl/certs/server.crt: Renewed (2 weeks ago)
       New certificate installed
       Sound: bundled:ssl-renewed

Certificate Statistics:
  Total Certs: 3
  Valid: 1
  Expiring: 1
  Expired: 1

Sound Settings:
  Expiring: bundled:ssl-expiring
  Expired: bundled:ssl-expired
  Revoked: bundled:ssl-revoked
  Valid: bundled:ssl-valid

[Configure] [Add Certificate] [Test All]
```

---

## Audio Player Compatibility

SSL monitoring doesn't play sounds directly:
- Monitoring feature using openssl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### SSL Certificate Monitor

```go
type SSLCertificateMonitor struct {
    config        *SSLCertificateMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    certState     map[string]*CertInfo
    lastEventTime map[string]time.Time
}

type CertInfo struct {
    Path        string
    Domain      string
    Issuer      string
    Subject     string
    NotBefore   time.Time
    NotAfter    time.Time
    DaysLeft    int
    Status      string // "valid", "expiring", "critical", "expired", "revoked"
    Algorithm   string
    Serial      string
    Fingerprint string
}

func (m *SSLCertificateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.certState = make(map[string]*CertInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SSLCertificateMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Hour)
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

func (m *SSLCertificateMonitor) snapshotCertState() {
    m.checkCertState()
}

func (m *SSLCertificateMonitor) checkCertState() {
    for _, certPath := range m.config.WatchCerts {
        info := m.checkCertificate(certPath)
        if info != nil {
            m.processCertStatus(info)
        }
    }
}

func (m *SSLCertificateMonitor) checkCertificate(certPath string) *CertInfo {
    info := &CertInfo{
        Path: certPath,
    }

    // Check if it's a file or domain
    if strings.Contains(certPath, "/") || strings.HasSuffix(certPath, ".crt") || strings.HasSuffix(certPath, ".pem") {
        return m.checkLocalCertificate(info, certPath)
    }

    // Assume it's a domain:port
    return m.checkRemoteCertificate(info, certPath)
}

func (m *SSLCertificateMonitor) checkLocalCertificate(info *CertInfo, certPath string) *CertInfo {
    // Check if file exists
    if _, err := os.Stat(certPath); err != nil {
        return nil
    }

    // Get certificate details
    cmd := exec.Command("openssl", "x509", "-in", certPath, "-noout", "-text")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info = m.parseCertificateOutput(info, string(output))

    // Get expiration date
    cmd = exec.Command("openssl", "x509", "-in", certPath, "-noout", "-enddate")
    dateOutput, _ := cmd.Output()

    info.NotAfter = m.parseEndDate(string(dateOutput))

    // Calculate days left
    now := time.Now()
    info.DaysLeft = int(info.NotAfter.Sub(now).Hours() / 24)
    info.Status = m.calculateStatus(info.DaysLeft)

    return info
}

func (m *SSLCertificateMonitor) checkRemoteCertificate(info *CertInfo, domainPort string) *CertInfo {
    parts := strings.Split(domainPort, ":")
    hostname := parts[0]
    port := "443"
    if len(parts) > 1 {
        port = parts[1]
    }

    info.Domain = hostname + ":" + port

    // Get certificate using openssl s_client
    cmd := exec.Command("openssl", "s_client", "-connect",
        fmt.Sprintf("%s:%s", hostname, port), "-servername", hostname)
    cmd.Stdin = strings.NewReader("QUIT\n")

    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info = m.parseCertificateOutput(info, string(output))

    // Extract end date from s_client output
    endDateRe := regexp.MustEach(`notAfter=(.+)`)
    matches := endDateRe.FindStringSubmatch(string(output))
    if len(matches) >= 2 {
        info.NotAfter = m.parseEndDate(matches[1])
    }

    // Calculate days left
    now := time.Now()
    info.DaysLeft = int(info.NotAfter.Sub(now).Hours() / 24)
    info.Status = m.calculateStatus(info.DaysLeft)

    return info
}

func (m *SSLCertificateMonitor) parseCertificateOutput(info *CertInfo, output string) *CertInfo {
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

func (m *SSLCertificateMonitor) parseEndDate(dateStr string) time.Time {
    dateStr = strings.TrimSpace(dateStr)
    dateStr = strings.TrimPrefix(dateStr, "notAfter=")

    // Try different date formats
    formats := []string{
        "Jan  2 15:04:05 2006 GMT",
        "Jan  2 15:04:05 2006 MST",
        "2006-01-02T15:04:05Z",
    }

    for _, format := range formats {
        if t, err := time.Parse(format, dateStr); err == nil {
            return t
        }
    }

    return time.Time{}
}

func (m *SSLCertificateMonitor) calculateStatus(daysLeft int) string {
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

func (m *SSLCertificateMonitor) processCertStatus(info *CertInfo) {
    lastInfo := m.certState[info.Path]

    if lastInfo == nil {
        m.certState[info.Path] = info
        if info.Status == "expired" && m.config.SoundOnExpired {
            m.onCertificateExpired(info)
        } else if info.Status == "critical" && m.config.SoundOnExpiring {
            m.onCertificateCritical(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "expired":
            if m.config.SoundOnExpired {
                m.onCertificateExpired(info)
            }
        case "critical", "expiring":
            if m.config.SoundOnExpiring {
                m.onCertificateExpiring(info)
            }
        }
    }

    m.certState[info.Path] = info
}

func (m *SSLCertificateMonitor) onCertificateExpiring(info *CertInfo) {
    key := fmt.Sprintf("expiring:%s", info.Path)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["expiring"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SSLCertificateMonitor) onCertificateCritical(info *CertInfo) {
    key := fmt.Sprintf("critical:%s", info.Path)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["expiring"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSLCertificateMonitor) onCertificateExpired(info *CertInfo) {
    key := fmt.Sprintf("expired:%s", info.Path)
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["expired"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SSLCertificateMonitor) shouldAlert(key string, interval time.Duration) bool {
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
