# Feature: Sound Preset Sharing

Share sound presets via URL.

## Summary

Share preset configurations through shareable URLs.

## Motivation

- Easy configuration sharing
- Community presets
- Quick setup

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Share Format

| Method | Description | Example |
|--------|-------------|---------|
| URL | Share via URL | ccbell://preset/work |
| Base64 | Inline configuration | ccbell:base64:eyJuYW1l... |
| File | Export as file | work-preset.json |

### Configuration

```go
type ShareConfig struct {
    BaseURL      string `json:"base_url"`      // "https://ccbell.app/share"
    APIEndpoint  string `json:"api_endpoint"`  // share API
    ExpiryDays   int    `json:"expiry_days"`   // URL expiry
    MaxDownloads int    `json:"max_downloads"` // download limit
}

type SharedPreset struct {
    ID          string    `json:"id"`
    Preset      *SoundPreset `json:"preset"`
    Downloads   int       `json:"downloads"`
    MaxDownloads int      `json:"max_downloads"`
    CreatedAt   time.Time `json:"created_at"`
    ExpiresAt   time.Time `json:"expires_at"`
}
```

### Commands

```bash
/ccbell:share create mypreset          # Create share link
/ccbell:share create mypreset --url    # URL format
/ccbell:share create mypreset --base64 # Base64 format
/ccbell:share import https://ccbell.app/share/abc123
/ccbell:share import "ccbell:base64:..."
/ccbell:share list                     # List shared presets
/ccbell:share revoke abc123            # Revoke share
/ccbell:share stats abc123             # Show download stats
```

### Output

```
$ ccbell:share create work-preset

=== Share Preset ===

Preset: work-preset
Format: URL

Share URL:
https://ccbell.app/share/abc123

Expires: 30 days
Downloads: 0 / unlimited

[Copy] [QR Code] [Revoke]

$ ccbell:share import https://ccbell.app/share/abc123

Downloading preset...
Verifying...
Importing...

Success: work-preset imported
  Volume: 30%
  Events: 3 configured

Apply now? [Yes] [No]
```

---

## Audio Player Compatibility

Sharing doesn't play sounds:
- Configuration transfer
- No player changes required

---

## Implementation

### URL Generation

```go
func (s *ShareManager) CreateShareLink(presetName string) (string, error) {
    preset, ok := s.presets[presetName]
    if !ok {
        return "", fmt.Errorf("preset not found: %s", presetName)
    }

    // Generate unique ID
    id := generateID()

    // Create shared preset record
    shared := &SharedPreset{
        ID:           id,
        Preset:       preset,
        CreatedAt:    time.Now(),
        ExpiresAt:    time.Now().AddDate(0, 1, 0), // 30 days
        MaxDownloads: s.config.MaxDownloads,
    }

    s.shares[id] = shared
    s.saveShares()

    // Generate URL
    hash := s.generateHash(preset)
    return fmt.Sprintf("%s/%s#%s", s.config.BaseURL, id, hash), nil
}
```

### Base64 Encoding

```go
func (s *ShareManager) ExportAsBase64(presetName string) (string, error) {
    preset, ok := s.presets[presetName]
    if !ok {
        return "", fmt.Errorf("preset not found: %s", presetName)
    }

    data, err := json.Marshal(preset)
    if err != nil {
        return "", err
    }

    encoded := base64.StdEncoding.EncodeToString(data)
    return fmt.Sprintf("ccbell:base64:%s", encoded), nil
}
```

### Import Processing

```go
func (s *ShareManager) Import(shareURL string) (*SoundPreset, error) {
    // Parse URL or base64
    var preset *SoundPreset
    var err error

    if strings.HasPrefix(shareURL, "ccbell:base64:") {
        preset, err = s.importFromBase64(shareURL)
    } else {
        preset, err = s.importFromURL(shareURL)
    }

    if err != nil {
        return nil, err
    }

    // Apply to current config
    s.presets[preset.Name] = preset
    return preset, s.savePresets()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go (base64, HTTP) |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Preset export
- [Profile management](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Preset import

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
