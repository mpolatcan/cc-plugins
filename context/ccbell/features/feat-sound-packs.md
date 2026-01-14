# Feature: Sound Packs 🎁

## Summary

Allow users to browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs are distributed via GitHub releases.

## Benefit

- **One-click variety**: Install complete sound themes with a single command
- **Community creativity**: Developers share their curated notification sounds
- **Consistent experience**: All sounds in a pack are designed to work together
- **Easy discovery**: Browse and preview packs without manual downloading

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Medium |
| **Category** | Audio |

## Technical Feasibility

### Configuration

```json
{
  "profiles": {
    "default": {
      "pack": "minimal-chimes",
      "overrides": {
        "stop": "custom:/path/to/custom-stop.wav"
      }
    }
  }
}
```

### Implementation

```go
type PackManager struct {
    packsDir string
    indexURL string
}

type SoundPack struct {
    Name        string            `json:"name"`
    Description string            `json:"description"`
    Author      string            `json:"author"`
    Version     string            `json:"version"`
    Sounds      map[string]string `json:"sounds"`
}

func (p *PackManager) Install(packName string) error {
    resp, err := http.Get(p.indexURL)
    var index PackIndex
    json.NewDecoder(resp.Body).Decode(&index)

    for _, pack := range index.Packs {
        if pack.Name == packName {
            return p.downloadAndExtract(pack.DownloadURL, packName)
        }
    }
    return fmt.Errorf("pack not found: %s", packName)
}

func (p *PackManager) List() ([]SoundPack, error) {
    resp, err := http.Get(p.indexURL)
    var index PackIndex
    json.NewDecoder(resp.Body).Decode(&index)
    return index.Packs, err
}
```

### Commands

```bash
/ccbell:packs browse              # Browse available packs
/ccbell:packs preview minimal     # Preview a pack
/ccbell:packs install minimal     # Install a pack
/ccbell:packs use minimal         # Activate a pack
/ccbell:packs uninstall minimal   # Remove a pack
/ccbell:packs list                # List installed packs
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `packs` section and `pack:` sound scheme support |
| **Core Logic** | Add | Add `PackManager` with List/Install/Use/Uninstall methods |
| **New File** | Add | `internal/pack/packs.go` for pack management |
| **Player** | Modify | Extend `ResolveSoundPath()` to handle `pack:` scheme |
| **Commands** | Add | New `packs` command |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/packs.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference pack configuration |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [Sound path resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)

---

[Back to Feature Index](index.md)
