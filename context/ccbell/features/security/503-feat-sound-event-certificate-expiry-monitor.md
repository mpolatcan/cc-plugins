# Feature: Sound Event Certificate Expiry Monitor

Play sounds for SSL/TLS certificate expiration warnings and certificate issues.

## Summary

Monitor SSL/TLS certificates for expiration warnings, chain validation issues, and certificate authority problems, playing sounds for certificate events.

## Motivation

- Security awareness
- Certificate renewal
- Trust monitoring
- PKI management
- Downtime prevention

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Medium |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Certificate Events

| Event | Description | Example |
|-------|-------------|---------|
| Expiring Soon | < 30 days | 25 days left |
| Expiring Very Soon | < 7 days | 5 days left |
| Expired | Certificate expired | yesterday |
| Revoked | Certificate revoked | revoked |
| Chain Broken | Chain validation | incomplete |
| Self-Signed | Self-signed detected | self-signed |

### Configuration

```go
type CertificateExpiryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchCertificates []CertificateSpec `json:"watch_certificates"`
    WarningDays       int               `json:"warning_days"` // 30 default
    CriticalDays      int               `json:"critical_days"` // 7 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnExpired    bool              `json:"sound_on_expired"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 86400 default
}

type CertificateSpec struct {
    Path   string // "/etc/ssl/certs/domain.crt"
    Host   string // "example.com:443"
    Type   string // "file", "host"
}
```

### Commands

```bash
/ccbell:cert status                 # Show certificate status
/ccbell:cert add /etc/ssl/cert.pem  # Add certificate to watch
/ccbell:cert add example.com:443    # Add host to check
/ccbell:cert sound warning <sound>
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

[1] example.com (file)
    Issuer: Let's Encrypt
    Subject: example.com
    Expires: 2024-03-15 (60 days) *** HEALTHY ***
    Algorithm: RSA-2048
    SANs: example.com, www.example.com
    Sound: bundled:cert-example

[2] api.example.com (host)
    Issuer: DigiCert
    Subject: *.api.example.com
    Expires: 2024-02-10 (5 days) *** CRITICAL ***
    Algorithm: ECDSA-256
    SANs: api.example.com
    Sound: bundled:cert-api *** CRITICAL ***

[3] internal.crt (file)
    Issuer: Internal CA
    Subject: internal.company.com
    Expires: 2024-01-20 (Expired 5 days ago) *** EXPIRED ***
    Algorithm: RSA-4096
    Sound: bundled:cert-internal *** EXPIRED ***

[4] legacy.company.com (host)
    Issuer: Unknown
    Subject: legacy.company.com
    Expires: Unknown
    Status: CHAIN BROKEN *** ERROR ***
    Error: certificate chain incomplete
    Sound: bundled:cert-legacy *** ERROR ***

Recent Events:

[1] api.example.com: Expiring Soon (5 min ago)
       Expires in 5 days (critical threshold)
       Sound: bundled:cert-critical
  [2] internal.crt: Certificate Expired (5 days ago)
       Certificate expired on 2024-01-20
       Sound: bundled:cert-expired
  [3] legacy.company.com: Chain Broken (1 week ago)
       Certificate chain incomplete
       Sound: bundled:cert-chain-broken

Certificate Statistics:
  Total Certificates: 4
  Healthy: 1
  Warning: 0
  Critical: 1
  Expired: 1
  Error: 1

Sound Settings:
  Warning: bundled:cert-warning
  Critical: bundled:cert-critical
  Expired: bundled:cert-expired
  Chain Broken: bundled:cert-chain-broken

[Configure] [Add Certificate] [Test All]
```

---

## Audio Player Compatibility

Certificate monitoring doesn't play sounds directly:
- Monitoring feature using openssl, curl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Certificate Expiry Monitor

```go
type CertificateExpiryMonitor struct {
    config        *CertificateExpiryMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    certState     map[string]*CertInfo
    lastEventTime time.Time
}

type CertInfo struct {
    Path        string
    Subject     string
    Issuer      string
    NotBefore   time.Time
    NotAfter    time.Time
    DaysRemaining int
    Algorithm   string
    SANs        []string
    Status      string // "healthy", "warning", "critical", "expired", "error"
    ErrorMsg    string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| openssl | System Tool | Free | Certificate parsing |
| curl | System Tool | Free | TLS handshake check |
| timeout | System Tool | Free | Connection timeout |

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
| macOS | Supported | Uses openssl, curl |
| Linux | Supported | Uses openssl, curl |
