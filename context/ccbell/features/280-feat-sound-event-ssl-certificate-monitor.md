# Feature: Sound Event SSL Certificate Monitor

Play sounds for SSL certificate expiration and validation events.

## Summary

Monitor SSL certificate expiration, validation errors, and certificate changes, playing sounds for certificate events.

## Motivation

- Certificate expiration alerts
- Security awareness
- Renewal reminders
- Validation failure alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### SSL Certificate Events

| Event | Description | Example |
|-------|-------------|---------|
| Expiring Soon | Cert < 30 days | 20 days left |
| Expired | Cert expired | 1 day ago |
| Expiring Today | Cert expires today | 0 days left |
| Validation Failed | Cert invalid | Self-signed |
| New Certificate | New cert installed | Chain updated |

### Configuration

```go
type SSLCertificateMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchHosts        []string          `json:"watch_hosts"` // host:port pairs
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnExpired    bool              `json:"sound_on_expired"]
    SoundOnFailed     bool              `json:"sound_on_failed"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_hours"` // 24 default
}

type SSLCertificateEvent struct {
    HostName     string
    Issuer       string
    Subject      string
    DaysRemaining int
    ExpiresAt    time.Time
    EventType    string // "warning", "expired", "validation_failed", "new"
}
```

### Commands

```bash
/ccbell:ssl status                     # Show SSL status
/ccbell:ssl add example.com:443        # Add host to watch
/ccbell:ssl remove example.com:443
/ccbell:ssl sound warning <sound>
/ccbell:ssl sound expired <sound>
/ccbell:ssl test                       # Test SSL sounds
```

### Output

```
$ ccbell:ssl status

=== Sound Event SSL Certificate Monitor ===

Status: Enabled
Warning: 30 days
Critical: 7 days

Watched Certificates: 4

[1] example.com:443
    Issuer: Let's Encrypt
    Subject: example.com
    Expires: 25 days (Jan 20, 2025)
    Status: OK
    Sound: bundled:stop

[2] api.example.com:443
    Issuer: DigiCert
    Subject: api.example.com
    Expires: 5 days (Dec 31, 2024)
    Status: CRITICAL
    Sound: bundled:stop

[3] old.example.com:443
    Issuer: Comodo
    Subject: old.example.com
    Expires: EXPIRED (Dec 15, 2024)
    Status: EXPIRED
    Sound: bundled:stop

[4] selfsigned.local:443
    Issuer: selfsigned.local
    Subject: selfsigned.local
    Status: VALIDATION FAILED
    Error: self-signed certificate
    Sound: bundled:stop

Recent Events:
  [1] api.example.com: Expiring Soon (1 day ago)
       5 days remaining
  [2] old.example.com: Expired (5 days ago)
  [3] selfsigned.local: Validation Failed (1 week ago)
       Self-signed certificate

Sound Settings:
  Warning: bundled:stop
  Expired: bundled:stop
  Validation Failed: bundled:stop

[Configure] [Add Host] [Test All]
```

---

## Audio Player Compatibility

SSL certificate monitoring doesn't play sounds directly:
- Monitoring feature using SSL/TLS tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSL Certificate Monitor

```go
type SSLCertificateMonitor struct {
    config           *SSLCertificateMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    certState        map[string]*CertStatus
    lastWarningTime  map[string]time.Time
}

type CertStatus struct {
    HostName       string
    Issuer         string
    Subject        string
    ExpiresAt      time.Time
    DaysRemaining  int
    Status         string // "ok", "warning", "critical", "expired", "failed"
    LastCheck      time.Time
}
```

```go
func (m *SSLCertificateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.certState = make(map[string]*CertStatus)
    m.lastWarningTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SSLCertificateMonitor) monitor() {
    interval := time.Duration(m.config.PollInterval) * time.Hour
    ticker := time.NewTicker(interval)
    defer ticker.Stop()

    // Initial check
    m.checkAllCertificates()

    for {
        select {
        case <-ticker.C:
            m.checkAllCertificates()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SSLCertificateMonitor) checkAllCertificates() {
    for _, host := range m.config.WatchHosts {
        m.checkCertificate(host)
    }
}

func (m *SSLCertificateMonitor) checkCertificate(host string) {
    // Use openssl to get certificate info
    cmd := exec.Command("openssl", "s_client", "-connect", host, "-servername", strings.Split(host, ":")[0])
    cmd.Stdin = strings.NewReader("QUIT\n")

    output, err := cmd.Output()
    if err != nil {
        // Connection failed - certificate might be invalid
        m.onValidationFailed(host, err.Error())
        return
    }

    certInfo := m.parseSSLCertificate(string(output), host)
    m.evaluateCertificate(host, certInfo)
}

func (m *SSLCertificateMonitor) parseSSLCertificate(output string, host string) *CertStatus {
    status := &CertStatus{
        HostName:  host,
        LastCheck: time.Now(),
    }

    // Extract certificate data
    // Look for the BEGIN CERTIFICATE block
    certStart := strings.Index(output, "-----BEGIN CERTIFICATE-----")
    if certStart == -1 {
        status.Status = "failed"
        return status
    }

    // Use openssl x509 to parse the certificate
    certData := output[certStart:]
    cmd := exec.Command("openssl", "x509", "-noout", "-subject", "-issuer", "-enddate")
    cmd.Stdin = strings.NewReader(certData)

    certOutput, err := cmd.Output()
    if err != nil {
        status.Status = "failed"
        return status
    }

    // Parse certificate details
    lines := strings.Split(string(certOutput), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "subject=") {
            status.Subject = strings.TrimPrefix(line, "subject=")
        } else if strings.HasPrefix(line, "issuer=") {
            status.Issuer = strings.TrimPrefix(line, "issuer=")
        } else if strings.HasPrefix(line, "notAfter=") {
            dateStr := strings.TrimPrefix(line, "notAfter=")
            // Parse date format: "Mon Jan 15 23:59:59 2025 GMT"
            expiresAt, err := time.Parse("Jan 2 15:04:05 2006 MST", dateStr)
            if err == nil {
                status.ExpiresAt = expiresAt
                daysRemaining := int(time.Until(expiresAt).Hours() / 24)
                status.DaysRemaining = daysRemaining

                if daysRemaining <= 0 {
                    status.Status = "expired"
                } else if daysRemaining <= m.config.CriticalDays {
                    status.Status = "critical"
                } else if daysRemaining <= m.config.WarningDays {
                    status.Status = "warning"
                } else {
                    status.Status = "ok"
                }
            }
        }
    }

    return status
}

func (m *SSLCertificateMonitor) evaluateCertificate(host string, status *CertStatus) {
    lastState := m.certState[host]

    if lastState == nil {
        m.certState[host] = status
        return
    }

    // Check for status changes
    if lastState.Status != status.Status {
        switch status.Status {
        case "warning":
            m.onCertificateWarning(host, status)
        case "critical":
            m.onCertificateCritical(host, status)
        case "expired":
            m.onCertificateExpired(host, status)
        case "failed":
            m.onValidationFailed(host, "certificate validation failed")
        }
    }

    m.certState[host] = status
}

func (m *SSLCertificateMonitor) onCertificateWarning(host string, status *CertStatus) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%s", host)
    if m.shouldAlert(key, 7*24*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSLCertificateMonitor) onCertificateCritical(host string, status *CertStatus) {
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *SSLCertificateMonitor) onCertificateExpired(host string, status *CertStatus) {
    if !m.config.SoundOnExpired {
        return
    }

    sound := m.config.Sounds["expired"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *SSLCertificateMonitor) onValidationFailed(host string, errorMsg string) {
    if !m.config.SoundOnFailed {
        return
    }

    key := fmt.Sprintf("failed:%s", host)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["validation_failed"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SSLCertificateMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastWarningTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastWarningTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| openssl | System Tool | Free | SSL/TLS toolkit |
| x509 | System Tool | Free | Certificate parsing |

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
