# Feature: Sound Packs

Download and install community-created sound themes from GitHub.

## Summary

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs are distributed via GitHub releases.

## Motivation

- Users want variety without hunting for sounds
- Easy way to try new themes
- Community can share creations
- Consistent quality within a pack

## Technical Feasibility

### Distribution Model

| Approach | Pros | Cons |
|----------|------|------|
| GitHub Releases | Free, CDN, versioned | Manual management |
| Custom registry | Curated, searchable | Extra infrastructure |
| npm-style registry | Familiar UX | Overkill for sounds |

**Recommended:** GitHub Releases with manifest file.

### Sound Pack Structure

```
sound-pack-name-v1.0.zip/
├── pack.json           # Pack metadata
├── stop.aiff          # Sound files
├── permission_prompt.aiff
├── idle_prompt.aiff
├── subagent.aiff
└── preview.mp3        # Optional: preview audio
```

### pack.json Schema

```json
{
  "name": "minimal-chimes",
  "version": "1.0.0",
  "description": "Clean, minimal chimes for notifications",
  "author": "username",
  "homepage": "https://github.com/username/ccbell-packs",
  "license": "MIT",
  "sounds": {
    "stop": "stop.aiff",
    "permission_prompt": "permission_prompt.aiff",
    "idle_prompt": "idle_prompt.aiff",
    "subagent": "subagent.aiff"
  },
  "tags": ["minimal", "chimes", "calm"],
  "compatibility": {
    "ccbell": ">=0.2.0"
  }
}
```

### GitHub Release Structure

**Repository:** `github.com/mpolatcan/ccbell-packs` or community repos

**Release Assets:**
```
ccbell-pack-minimal-chimes-v1.0.0.zip
ccbell-pack-8bit-retro-v1.2.0.zip
ccbell-pack-zen-bells-v0.9.0.zip
```

**Pack Index (JSON):**
```json
{
  "packs": [
    {
      "id": "minimal-chimes",
      "name": "Minimal Chimes",
      "description": "Clean, minimal chimes",
      "author": "username",
      "version": "1.0.0",
      "download_url": "https://github.com/mpolatcan/ccbell-packs/releases/download/v1.0.0/ccbell-pack-minimal-chimes.zip",
      "tags": ["minimal", "chimes"],
      "rating": 4.5,
      "downloads": 1234
    }
  ]
}
```

## Implementation

### Download & Install Flow

```go
func (c *CCBell) installPack(packURL string) error {
    // 1. Download ZIP
    zipPath := filepath.Join(c.cacheDir, "packs", "download.zip")
    if err := c.downloadFile(packURL, zipPath); err != nil {
        return err
    }

    // 2. Extract to temp
    tempDir, err := c.extractZip(zipPath)
    if err != nil {
        return err
    }

    // 3. Validate pack.json
    pack, err := c.loadPackManifest(tempDir)
    if err != nil {
        return fmt.Errorf("invalid pack: %w", err)
    }

    // 4. Move to installed packs
    installDir := filepath.Join(c.packsDir, pack.ID+"-"+pack.Version)
    if err := os.Rename(tempDir, installDir); err != nil {
        return err
    }

    // 5. Pre-validate sounds exist
    for event, filename := range pack.Sounds {
        soundPath := filepath.Join(installDir, filename)
        if _, err := os.Stat(soundPath); err != nil {
            return fmt.Errorf("missing sound for %s: %s", event, filename)
        }
    }

    return nil
}
```

### Pack Discovery

```go
func (c *CCBell) listPacks() ([]PackInfo, error) {
    // Fetch from index URL
    resp, err := http.Get("https://ccbell.packs.dev/index.json")
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var index PackIndex
    if err := json.NewDecoder(resp.Body).Decode(&index); err != nil {
        return nil, err
    }

    // Filter by installed packs
    for i := range index.Packs {
        if _, err := os.Stat(filepath.Join(c.packsDir, index.Packs[i].ID)); err == nil {
            index.Packs[i].Installed = true
        }
    }

    return index.Packs, nil
}
```

## Commands

### Browse Packs

```bash
/ccbell:packs browse
```

**Output:**
```
=== ccbell Sound Packs ===

[1] Minimal Chimes (v1.0.0) - ⭐ 4.5 (1.2K downloads)
    Clean, minimal chimes for notifications
    Tags: minimal, chimes, calm
    [i] Info  [p] Preview  [i] Install

[2] 8-bit Retro (v1.2.0) - ⭐ 4.2 (856 downloads)
    Classic 8-bit sounds for nostalgiacs
    Tags: retro, 8bit, gaming
    [i] Info  [p] Preview  [i] Install

[3] Zen Bells (v0.9.0) - ⭐ 4.8 (2.1K downloads)
    Peaceful bell sounds for focused work
    Tags: zen, bells, meditation
    [i] Info  [p] Preview  [i] Install

Page 1/3 | [n] Next  [p] Prev  [q] Quit

Select pack to install: 1
Installing Minimal Chimes... ✓
```

### Preview Pack

```bash
/ccbell:packs preview minimal-chimes
Playing preview...
✓ All sounds previewed

/ccbell:packs preview minimal-chimes --single stop
Playing stop sound only...
```

### Install Pack

```bash
/ccbell:packs install minimal-chimes
# Or from URL
/ccbell:packs install https://github.com/user/pack/releases/download/v1.0.0/pack.zip
```

### Manage Packs

```bash
/ccbell:packs list
Installed packs:
  [1] minimal-chimes v1.0.0 (active)
  [2] zen-bells v0.9.0

/ccbell:packs use minimal-chimes
Activated minimal-chimes

/ccbell:packs uninstall zen-bells
Uninstalled zen-bells

/ccbell:packs update
Checking for updates...
minimal-chimes: v1.0.0 → v1.1.0 [Update? y/n]
```

## Configuration

### Apply Pack to Profile

```json
{
  "profiles": {
    "default": {
      "pack": "minimal-chimes",
      "overrides": {
        "stop": "custom:/path/to/custom-stop.wav"
      }
    },
    "focus": {
      "pack": "zen-bells"
    }
  }
}
```

### Pack Config (in `~/.claude/ccbell-packs.json`)

```json
{
  "packs_dir": "~/.claude/ccbell/packs",
  "index_url": "https://ccbell.packs.dev/index.json",
  "installed": {
    "minimal-chimes": {
      "version": "1.0.0",
      "path": "/Users/me/.claude/ccbell/packs/minimal-chimes-v1.0.0",
      "active": true
    }
  }
}
```

## Sound Pack Examples

### Pack: Minimal Chimes

| Event | Sound | Description |
|-------|-------|-------------|
| stop | `stop.aiff` | Soft chime |
| permission | `permission.aiff` | Gentle ding |
| idle | `idle.aiff` | Subtle tone |
| subagent | `subagent.aiff` | Completion chime |

### Pack: 8-bit Retro

| Event | Sound | Description |
|-------|-------|-------------|
| stop | `stop.wav` | Coin pickup sound |
| permission | `permission.wav` | Power-up jingle |
| idle | `idle.wav` | Error buzz |
| subagent | `subagent.wav` | Level complete |

### Pack: Zen Bells

| Event | Sound | Description |
|-------|-------|-------------|
| stop | `stop.wav` | Tibetan bowl |
| permission | `permission.wav` | Soft bell |
| idle | `idle.wav` | Meditation bell |
| subagent | `subagent.wav` | Singing bowl |

## Quality Guidelines

### Pack Requirements

1. **All 4 events** must have sounds
2. **Consistent style** across all sounds
3. **Good quality:** 44.1kHz AIFF/WAV, no clipping
4. **Reasonable length:** 0.5-2.0 seconds
5. **pack.json** with all required fields
6. **License:** Clearly stated (MIT, CC0, etc.)

### Submission Process

1. Fork `ccbell-packs` repository
2. Add pack folder with sounds + pack.json
3. Create PR with pack details
4. Maintainer reviews and merges
5. Release automation creates GitHub release

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Malicious packs | Validate pack.json, checksum verification |
| Broken downloads | Retry logic, verify ZIP integrity |
| Disk space | Show pack sizes, limit cache |
| Version conflicts | Include pack version in path |

## Future Enhancements

- **Pack ratings & reviews**
- **Pack search/filter by tags**
- **Create pack command** - scaffold new pack
- **Export current config as pack**
- **Pack subscriptions** - auto-update

## Dependencies

| Dependency | Purpose | Link |
|------------|---------|------|
| archiver | ZIP extraction | `github.com/mholt/archiver` |
| go-httpfile | Download with resume | `github.com/posener/go-httpfile` |

## References

- [Homebrew Brew Formulas](https://docs.brew.sh/Formula-Cookbook) - Similar distribution model
- [VSCode Extension Marketplace](https://marketplace.visualstudio.com/) - Proven model
- [Neovim Plugin Manager](https://github.com/junegunn/vim-plug) - Community packs
