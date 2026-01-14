# Feature: Sound Event SSL Certificate Monitor

Play sounds for SSL certificate expiration warnings and certificate changes.

## Summary

Monitor SSL/TLS certificate expiration, validity changes, and certificate events, playing sounds for certificate events.

## Motivation

- Certificate expiration alerts
- SSL renewal awareness
- Certificate change detection
- Security certificate feedback
- Certificate authority warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SSL Certificate Events

| Event | Description | Example |
|-------|-------------|---------|
| Expiring Soon | Certificate expiring | 7 days left |
| Expired | Certificate expired | 0 days left |
| Renewed | Certificate renewed | New cert installed |
| Revoked | Certificate revoked | CA revoked |
| Chain Changed | Certificate chain changed | New intermediate |

### Configuration

```go
type SSLCertificateMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Certificates      []CertConfig      `json:"certificates"`
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    SoundOnExpiring   bool              `json:"sound_on_expiring"]
    SoundOnExpired    bool              `json:"sound_on_expired"]
    SoundOnRenewed    bool              `json:"sound_on_renewed"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 86400 default
}

type CertConfig struct {
    Name     string `json:"name"` // "example.com"
    Host     string `json:"host"` // "example.com:443"
    Path     string `json:"path"` // "/path/to/cert.pem"
    Type     string `json:"type"` // "host" or "file"
}

type SSLCertificateEvent struct {
    Certificate  string
    Host         string
    Issuer       string
    Subject      string
    NotBefore    time.Time
    NotAfter     time.Time
    DaysLeft     int
    EventType    string // "expiring", "expired", "renewed", "revoked"
}
```

### Commands

```bash
/ccbell:ssl status                    # Show SSL certificate status
/ccbell:ssl add example.com           # Add certificate to watch
/ccbell:ssl remove example.com
/ccbell:ssl warning 30                # Set warning days
/ccbell:ssl sound expiring <sound>
/ccbell:ssl test                      # Test SSL sounds
```

### Output

```
$ ccbell:ssl status

=== Sound Event SSL Certificate Monitor ===

Status: Enabled
Warning: 30 days
Critical: 7 days
Expiring Sounds: Yes
Expired Sounds: Yes
Renewed Sounds: Yes

Monitored Certificates: 3

[1] example.com
    Subject: example.com
    Issuer: Let's Encrypt
    Valid: 89 days remaining
    Status: OK
    Sound: bundled:ssl-example

[2] api.example.org
    Subject: api.example.org
    Issuer: DigiCert
    Valid: 5 days remaining *** EXPIRING ***
    Status: CRITICAL
    Sound: bundled:ssl-api

[3] internal.corp
    Subject: internal.corp
    Issuer: Corp CA
    Valid: 200 days remaining
    Status: OK
    Sound: bundled:ssl-internal

Recent Events:
  [1] api.example.org: Expiring Soon (5 min ago)
       5 days remaining
  [2] example.com: Certificate Renewed (1 week ago)
       New certificate installed
  [3] internal.corp: Chain Changed (2 weeks ago)
       New intermediate CA

Certificate Statistics:
  Monitored: 3
  Valid: 2
  Expiring: 1
  Expired: 0

Sound Settings:
  Expiring: bundled:ssl-expiring
  Expired: bundled:ssl-expired
  Renewed: bundled:ssl-renewed

[Configure] [Add Certificate] [Test All]
```

---

## Audio Player Compatibility

SSL certificate monitoring doesn't play sounds directly:
- Monitoring feature using openssl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SSL Certificate Monitor

```go
type SSLCertificateMonitor struct {
    config          *SSLCertificateMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    certState       map[string]*CertInfo
    lastEventTime   map[string]time.Time
}

type CertInfo struct {
    Name       string
    Host       string
    Issuer     string
    Subject    string
    NotBefore  time.Time
    NotAfter   time.Time
    DaysLeft   int
    Serial     string
    LastCheck  time.Time
}

func (m *SSLCertificateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.certState = make(map[string]*CertInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SSLCertificateMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
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
    for _, cert := range m.config.Certificates {
        m.checkCertificate(&cert)
    }
}

func (m *SSLCertificateMonitor) checkCertificate(config *CertConfig) {
    info := m.getCertificateInfo(config)
    if info == nil {
        return
    }

    key := config.Name
    lastInfo := m.certState[key]

    if lastInfo == nil {
        m.certState[key] = info
        return
    }

    // Check expiration status
    m.evaluateCertEvents(key, info, lastInfo)
    m.certState[key] = info
}

func (m *SSLCertificateMonitor) getCertificateInfo(config *CertConfig) *CertInfo {
    var cmd *exec.Cmd

    if config.Type == "host" {
        // Get certificate from host
        cmd = exec.Command("openssl", "s_client", "-connect", config.Host,
            "-servername", config.Host, "-showcerts")
        fmt.Fprintf(cmd.Stdin, "QUIT\n")
    } else {
        // Get certificate from file
        cmd = exec.Command("openssl", "x509", "-in", config.Path, "-noout", "-text")
    }

    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    return m.parseCertificateOutput(string(output), config)
}

func (m *SSLCertificateMonitor) parseCertificateOutput(output string, config *CertConfig) *CertInfo {
    info := &CertInfo{
        Name:      config.Name,
        Host:      config.Host,
        LastCheck: time.Now(),
    }

    // Extract subject
    subjectRe := regexp.MustCompile(`Subject:\s*(.+)`)
    match := subjectRe.FindStringSubmatch(output)
    if match != nil {
        info.Subject = strings.TrimSpace(match[1])
    }

    // Extract issuer
    issuerRe := regexp.MustCompile(`Issuer:\s*(.+)`)
    match = issuerRe.FindStringSubmatch(output)
    if match != nil {
        info.Issuer = strings.TrimSpace(match[1])
    }

    // Extract validity dates
    notBeforeRe := regexp.MustCompile(`Not Before:\s*(.+)`)
    match = notBeforeRe.FindStringSubmatch(output)
    if match != nil {
        if t, err := time.Parse("Jan  2 15:04:05 2006 MST", strings.TrimSpace(match[1])); err == nil {
            info.NotBefore = t
        }
    }

    notAfterRe := regexp.MustCompile(`Not After :\s*(.+)`)
    match = notAfterRe.FindStringSubmatch(output)
    if match != nil {
        if t, err := time.Parse("Jan  2 15:04:05 2006 MST", strings.TrimSpace(match[1])); err == nil {
            info.NotAfter = t
            info.DaysLeft = int(time.Until(t).Hours() / 24)
        }
    }

    // Extract serial
    serialRe := regexp.MustCompile(`Serial Number:\s*(.+)`)
    match = serialRe.FindStringSubmatch(output)
    if match != nil {
        info.Serial = strings.TrimSpace(match[1])
    }

    return info
}

func (m *SSLCertificateMonitor) evaluateCertEvents(key string, newInfo *CertInfo, lastInfo *CertInfo) {
    // Check for expiring
    if newInfo.DaysLeft <= m.config.CriticalDays && lastInfo.DaysLeft > m.config.CriticalDays {
        m.onCertificateExpired(key, newInfo)
    } else if newInfo.DaysLeft <= m.config.WarningDays && lastInfo.DaysLeft > m.config.WarningDays {
        m.onCertificateExpiring(key, newInfo)
    }

    // Check for renewal (serial changed)
    if lastInfo.Serial != "" && newInfo.Serial != lastInfo.Serial {
        m.onCertificateRenewed(key, newInfo, lastInfo)
    }

    // Check if still valid after being expired
    if lastInfo.DaysLeft <= 0 && newInfo.DaysLeft > 0 {
        m.onCertificateRenewed(key, newInfo, lastInfo)
    }
}

func (m *SSLCertificateMonitor) onCertificateExpiring(key string, info *CertInfo) {
    if !m.config.SoundOnExpiring {
        return
    }

    key = fmt.Sprintf("expiring:%s", key)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["expiring"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SSLCertificateMonitor) onCertificateExpired(key string, info *CertInfo) {
    if !m.config.SoundOnExpired {
        return
    }

    key = fmt.Sprintf("expired:%s", key)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["expired"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *SSLCertificateMonitor) onCertificateRenewed(key string, newInfo *CertInfo, lastInfo *CertInfo) {
    if !m.config.SoundOnRenewed {
        return
    }

    key = fmt.Sprintf("renewed:%s", key)
    if m.shouldAlert(key, 7*24*time.Hour) {
        sound := m.config.Sounds["renewed"]
        if sound != "" {
            m.player.Play(sound, 0.4)
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
| openssl | System Tool | Free | Certificate inspection |
| s_client | System Tool | Free | SSL client connection |

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
