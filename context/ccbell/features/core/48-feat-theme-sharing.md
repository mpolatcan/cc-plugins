# Feature: Theme Sharing

Share sound themes with others via URL or paste.

## Summary

Generate shareable URLs or text snippets containing complete theme configurations.

## Motivation

- Share notification themes with team
- Backup configurations externally
- Easy theme distribution

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Sharing Methods

| Method | Pros | Cons |
|--------|------|------|
| Gist URL | Free, permanent | Requires GitHub |
| Pastebin | Free, simple | May expire |
| Base64 string | No service needed | Long URLs |
| QR code | Easy to share | Size limited |

### Base64 Sharing

```bash
# Export theme as base64
ccbell theme export work | base64

# Import from base64
echo "JTNCe29wZW5lZCUzRCU1QiU3..." | base64 -d | ccbell theme import
```

### URL Sharing (Gist)

```bash
# Export to Gist (requires token)
ccbell theme share work --gist --token $GITHUB_TOKEN
# Returns: https://gist.github.com/...

# Import from Gist
ccbell theme import https://gist.github.com/...
```

### Theme Package Structure

```json
{
  "name": "Zen Focus",
  "version": "1.0.0",
  "author": "username",
  "description": "Calm sounds for focused work",
  "events": {
    "stop": {
      "enabled": true,
      "sound": "bundled:soft-chime",
      "volume": 0.4
    }
  },
  "profiles": {
    "default": { ... }
  },
  "checksum": "sha256:abc123..."
}
```

### Commands

```bash
/ccbell:theme export work --base64        # Export as base64
/ccbell:theme export work --gist          # Export to Gist
/ccbell:theme import https://gist.github.com/...  # Import from URL
/ccbell:theme import "base64string"       # Import from base64
/ccbell:theme qrcode work                 # Generate QR code
/ccbell:theme copy work                   # Copy to clipboard
```

---

## Audio Player Compatibility

Theme sharing doesn't interact with audio playback:
- Purely config export/import
- No player changes required
- Theme applies to future playback

---

## Implementation

### Base64 Encoding

```go
func exportThemeBase64(cfg *Config, profile string) (string, error) {
    theme := createThemePackage(cfg, profile)

    data, err := json.Marshal(theme)
    if err != nil {
        return "", err
    }

    return base64.StdEncoding.EncodeToString(data), nil
}

func importThemeBase64(encoded string) (*config.Config, error) {
    data, err := base64.StdEncoding.DecodeString(encoded)
    if err != nil {
        return nil, err
    }

    var theme ThemePackage
    if err := json.Unmarshal(data, &theme); err != nil {
        return nil, err
    }

    return theme.ToConfig()
}
```

### Gist Integration

```go
func shareToGist(theme *ThemePackage, token string) (string, error) {
    data, _ := json.MarshalIndent(theme, "", "  ")

    req, _ := http.NewRequest("POST", "https://api.github.com/gists",
        bytes.NewBuffer(data))
    req.Header.Set("Authorization", "token "+token)
    req.Header.Set("Content-Type", "application/json")

    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(req)
    // Parse response for gist URL
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| GitHub API | External | Free | For Gist sharing |
| base64 | Native | Free | Built-in |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config serialization
- [Profile handling](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L40-L43) - Profile structure

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
