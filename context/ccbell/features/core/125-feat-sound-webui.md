# Feature: Sound WebUI

Web-based user interface for sound management.

## Summary

Web interface for managing sounds through a browser.

## Motivation

- Visual management
- Easy configuration
- Cross-platform UI

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | High |
| **Estimated Effort** | 7-10 days |

---

## Technical Feasibility

### UI Features

| Feature | Description | Implementation |
|---------|-------------|----------------|
| Dashboard | Overview | Statistics, status |
| Sound Manager | Browse/manage | List, preview, edit |
| Configuration | Settings UI | Form-based config |
| Profiles | Profile management | Create, switch, edit |
| Visualizer | Sound visualization | Waveform display |
| Settings | Global settings | All options |

### UI Structure

```
webui/
├── index.html          # Main page
├── css/
│   └── styles.css      # Styles
├── js/
│   ├── app.js          # Main app
│   ├── api.js          # API client
│   └── components/     # UI components
└── assets/
    └── icons/          # Icons
```

### Commands

```bash
/ccbell:webui enable                 # Enable web UI
/ccbell:webui disable                # Disable web UI
/ccbell:webui port 3000              # Set port
/ccbell:webui open                   # Open browser
/ccbell:webui theme dark             # Dark theme
/ccbell:webui status                 # Show UI status
/ccbell:webui rebuild                # Rebuild UI assets
```

### Output

```
$ ccbell:webui status

=== Web UI Status ===

Status: Enabled
Port: 3000
URL: http://localhost:3000

Features:
  ✓ Dashboard
  ✓ Sound Manager
  ✓ Configuration
  ✓ Profiles
  ✗ Visualizer (ffmpeg required)

[Open Browser] [Configure] [Rebuild] [Disable]
```

---

## Audio Player Compatibility

WebUI uses existing audio player:
- API calls `player.Play()` for preview
- Same format support
- No player changes required

---

## Implementation

### HTTP Server

```go
func (s *WebUIManager) Start() error {
    // Serve static files
    fs := http.FileServer(http.Dir(s.webRoot))

    // API routes
    router := mux.NewRouter()
    router.PathPrefix("/api/").Handler(s.apiHandler)
    router.PathPrefix("/").Handler(fs)

    // Start server
    addr := fmt.Sprintf(":%d", s.config.Port)
    return http.ListenAndServe(addr, router)
}
```

### API Integration

```go
// API client for web UI
const API_BASE = '/api/v1';

async function playSound(soundId) {
    const response = await fetch(`${API_BASE}/play`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sound: soundId, volume: 0.5 })
    });
    return response.json();
}

async function listSounds() {
    const response = await fetch(`${API_BASE}/sounds`);
    return response.json();
}
```

### Sound Preview Component

```javascript
function SoundCard({ sound }) {
    return `
        <div class="sound-card" data-id="${sound.id}">
            <div class="preview-btn" onclick="preview('${sound.id}')">
                ▶
            </div>
            <div class="sound-info">
                <h3>${sound.name}</h3>
                <p>${sound.duration}s</p>
            </div>
            <div class="waveform">
                <canvas id="waveform-${sound.id}"></canvas>
            </div>
        </div>
    `;
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go (static files + API) |

---

## References

### ccbell Implementation Research

- [API feature](features/123-feat-sound-api.md) - WebUI backend
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Preview playback

### Research Sources

- [Go HTTP server](https://pkg.go.dev/net/http)
- [Web UI patterns](https://developer.mozilla.org/en-US/docs/Web)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go + static files |
| Linux | ✅ Supported | Pure Go + static files |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
