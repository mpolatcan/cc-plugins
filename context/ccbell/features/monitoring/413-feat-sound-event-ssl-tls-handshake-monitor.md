# Feature: Sound Event SSL/TLS Handshake Monitor

Play sounds for SSL/TLS certificate expiration, handshake failures, and certificate changes.

## Summary

Monitor SSL/TLS certificates and HTTPS endpoints for expiration, handshake status, and certificate changes, playing sounds for TLS events.

## Motivation

- Certificate expiration alerts
- Handshake failure detection
- Certificate change tracking
- Security monitoring
- TLS compliance awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSL/TLS Events

| Event | Description | Example |
|-------|-------------|---------|
| Certificate Expiring | Expires soon | 7 days left |
| Certificate Expired | Already expired | past expiry |
| Handshake Failed | Connection error | timeout |
| Certificate Changed | New certificate | new issuer |
| Weak Cipher | Insecure suite | TLS 1.0 |
| Expiring Soon | Warning threshold | 30 days |

### Configuration

```go
type SSLHandshakeMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchHosts        []string          `json:"watch_hosts"` // "example.com", "https://api.example.com"
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    CheckInterval     int               `json:"check_interval_hours"` // 24 default
    SoundOnExpiring   bool              `json:"sound_on_expiring"`
    SoundOnExpired    bool              `json:"sound_on_expired"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    Sounds            map[string]string `json:"sounds"`
}
```

### Commands

```bash
/ccbell:tls status                   # Show TLS status
/ccbell:tls add example.com          # Add host to watch
/ccbell:tls remove example.com
/ccbell:tls warning 30               # Set warning days
/ccbell:tls sound expiring <sound>
/ccbell:tls sound expired <sound>
/ccbell:tls test                     # Test TLS sounds
```

### Output

```
$ ccbell:tls status

=== Sound Event SSL/TLS Handshake Monitor ===

Status: Enabled
Expiring Sounds: Yes
Expired Sounds: Yes
Failed Sounds: Yes

Watched Hosts: 4

Certificate Status:

[1] example.com
    Status: VALID
    Issuer: Let's Encrypt
    Expires: 2026-02-14 (31 days)
    Algorithm: ECDSA P-256
    Cipher: TLS_AES_256_GCM_SHA384
    Handshake: SUCCESS
    Sound: bundled:tls-example

[2] api.example.com
    Status: EXPIRING SOON
    Issuer: DigiCert
    Expires: 2026-01-20 (7 days) *** WARNING ***
    Algorithm: RSA 2048
    Cipher: TLS_AES_256_GCM_SHA384
    Handshake: SUCCESS
    Sound: bundled:tls-api *** WARNING ***

[3] secure.example.org
    Status: EXPIRED
    Issuer: GoDaddy
    Expires: 2026-01-01 (-13 days) *** FAILED ***
    Algorithm: RSA 2048
    Handshake: FAILED
    Sound: bundled:tls-secure *** FAILED ***

[4] internal.company.local
    Status: VALID
    Issuer: Company Internal CA
    Expires: 2026-06-01 (138 days)
    Algorithm: RSA 4096
    Cipher: TLS_AES_256_GCM_SHA384
    Handshake: SUCCESS
    Sound: bundled:tls-internal

Certificate Chain:

  example.com:
    Leaf: ISRG Root X1
    Intermediate: Let's Encrypt R3
    Root: Self-signed

Recent Events:
  [1] api.example.com: Certificate Expiring (1 hour ago)
       7 days until expiration
  [2] secure.example.org: Certificate Expired (1 day ago)
       13 days past expiry
  [3] example.com: Certificate Changed (3 days ago)
       New issuer detected

TLS Statistics:
  Total Hosts: 4
  Valid: 2
  Expiring: 1
  Expired: 1
  Handshake Failures: 1

Sound Settings:
  Expiring: bundled:tls-expiring
  Expired: bundled:tls-expired
  Failed: bundled:tls-failed
  Changed: bundled:tls-changed

[Configure] [Add Host] [Test All]
```

---

## Audio Player Compatibility

TLS monitoring doesn't play sounds directly:
- Monitoring feature using openssl s_client
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSL/TLS Handshake Monitor

```go
type SSLHandshakeMonitor struct {
    config          *SSLHandshakeMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    certState       map[string]*CertInfo
    lastEventTime   map[string]time.Time
}

type CertInfo struct {
    Host          string
    Issuer        string
    Subject       string
    NotBefore     time.Time
    NotAfter      time.Time
    Algorithm     string
    Serial        string
    Fingerprint   string
    Status        string // "valid", "expiring", "expired", "failed"
    HandshakeOK   bool
    Error         string
    DaysRemaining int
}

func (m *SSLHandshakeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.certState = make(map[string]*CertInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SSLHandshakeMonitor) monitor() {
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

func (m *SSLHandshakeMonitor) snapshotCertState() {
    m.checkCertState()
}

func (m *SSLHandshakeMonitor) checkCertState() {
    for _, host := range m.config.WatchHosts {
        info := m.checkCertificate(host)

        if info != nil {
            m.processCertStatus(host, info)
        }
    }
}

func (m *SSLHandshakeMonitor) checkCertificate(host string) *CertInfo {
    // Ensure host has scheme
    if !strings.HasPrefix(host, "https://") && !strings.HasPrefix(host, "http://") {
        host = "https://" + host
    }

    // Extract hostname
    u, err := url.Parse(host)
    if err != nil {
        return nil
    }

    hostname := u.Hostname()
    port := u.Port()
    if port == "" {
        port = "443"
    }

    // Get certificate using openssl
    cmd := exec.Command("openssl", "s_client", "-connect",
        fmt.Sprintf("%s:%s", hostname, port), "-servername", hostname)
    cmd.Stdin = strings.NewReader("QUIT\n")

    output, err := cmd.Output()
    if err != nil {
        return &CertInfo{
            Host:        hostname,
            Status:      "failed",
            HandshakeOK: false,
            Error:       err.Error(),
        }
    }

    return m.parseCertificateOutput(hostname, string(output))
}

func (m *SSLHandshakeMonitor) parseCertificateOutput(host, output string) *CertInfo {
    info := &CertInfo{
        Host: host,
    }

    // Extract certificate dates
    dateRe := regexp.MustEach(`notBefore=(.+)`)
    matches := dateRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.NotBefore, _ = time.Parse("Jan _2 15:04:05 2006 MST", matches[1])
    }

    dateRe = regexp.MustEach(`notAfter=(.+)`)
    matches = dateRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.NotAfter, _ = time.Parse("Jan _2 15:04:05 2006 MST", matches[1])
    }

    // Extract issuer
    issuerRe := regexp.MustEach(`issuer = (.+)`)
    matches = issuerRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.Issuer = strings.TrimSpace(matches[1])
    }

    // Extract subject
    subjectRe := regexp.MustEach(`subject = (.+)`)
    matches = subjectRe.FindStringSubmatch(output)
    if len(matches) >= 2 {
        info.Subject = strings.TrimSpace(matches[1])
    }

    // Calculate days remaining
    now := time.Now()
    info.DaysRemaining = int(info.NotAfter.Sub(now).Hours() / 24)

    // Determine status
    if info.DaysRemaining <= 0 {
        info.Status = "expired"
    } else if info.DaysRemaining <= m.config.CriticalDays {
        info.Status = "expiring_critical"
    } else if info.DaysRemaining <= m.config.WarningDays {
        info.Status = "expiring"
    } else {
        info.Status = "valid"
    }

    info.HandshakeOK = true

    // Get algorithm and other details
    cmd := exec.Command("openssl", "x509", "-noout", "-text")
    certInput := m.extractCertificate(output)
    if certInput != "" {
        certCmd := exec.Command("openssl", "x509", "-noout", "-text")
        certCmd.Stdin = strings.NewReader(certInput)
        certOut, _ := certCmd.Output()
        certText := string(certOut)

        // Extract algorithm
        algoRe := regexp.MustEach(`Signature Algorithm: (.+)`)
        algoMatches := algoRe.FindStringSubmatch(certText)
        if len(algoMatches) >= 2 {
            info.Algorithm = strings.TrimSpace(algoMatches[1])
        }
    }

    return info
}

func (m *SSLHandshakeMonitor) extractCertificate(output string) string {
    // Extract PEM certificate from s_client output
    start := strings.Index(output, "-----BEGIN CERTIFICATE-----")
    if start == -1 {
        return ""
    }

    end := strings.Index(output[start:], "-----END CERTIFICATE-----")
    if end == -1 {
        return ""
    }

    return output[start : start+end+len("-----END CERTIFICATE-----")]
}

func (m *SSLHandshakeMonitor) processCertStatus(host string, info *CertInfo) {
    lastInfo := m.certState[host]

    if lastInfo == nil {
        m.certState[host] = info
        return
    }

    // Check for certificate changes
    if lastInfo.Issuer != info.Issuer || lastInfo.Fingerprint != info.Fingerprint {
        if m.shouldAlert(host+":changed", 24*time.Hour) {
            m.onCertificateChanged(info)
        }
    }

    // Check status changes
    if lastInfo.Status != info.Status {
        switch info.Status {
        case "expired":
            if m.config.SoundOnExpired {
                m.onCertificateExpired(info)
            }
        case "expiring", "expiring_critical":
            if m.config.SoundOnExpiring {
                m.onCertificateExpiring(info)
            }
        }
    }

    // Check handshake failures
    if !info.HandshakeOK && lastInfo.HandshakeOK {
        if m.config.SoundOnFailed {
            m.onHandshakeFailed(info)
        }
    }

    m.certState[host] = info
}

func (m *SSLHandshakeMonitor) shouldWatchHost(host string) bool {
    if len(m.config.WatchHosts) == 0 {
        return true
    }

    for _, h := range m.config.WatchHosts {
        if h == "*" || strings.Contains(h, host) {
            return true
        }
    }

    return false
}

func (m *SSLHandshakeMonitor) onCertificateExpiring(info *CertInfo) {
    key := fmt.Sprintf("expiring:%s", info.Host)
    interval := 24 * time.Hour
    if info.Status == "expiring_critical" {
        interval = 1 * time.Hour
    }

    if m.shouldAlert(key, interval) {
        sound := m.config.Sounds["expiring"]
        if sound != "" {
            volume := 0.4
            if info.Status == "expiring_critical" {
                volume = 0.5
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *SSLHandshakeMonitor) onCertificateExpired(info *CertInfo) {
    key := fmt.Sprintf("expired:%s", info.Host)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["expired"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SSLHandshakeMonitor) onCertificateChanged(info *CertInfo) {
    key := fmt.Sprintf("changed:%s", info.Host)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["changed"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SSLHandshakeMonitor) onHandshakeFailed(info *CertInfo) {
    key := fmt.Sprintf("failed:%s", info.Host)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSLHandshakeMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| s_client | OpenSSL Command | Free | Client connection |
| x509 | OpenSSL Command | Free | Certificate parsing |

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
| macOS | Supported | Uses openssl (built-in) |
| Linux | Supported | Uses openssl (usually installed) |
